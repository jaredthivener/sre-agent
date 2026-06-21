# Autonomous SRE Agent

A **PagerDuty-triggered, read-only Site Reliability Engineer agent**. When an incident fires, a
webhook invokes the [Claude Agent SDK](https://docs.claude.com/en/docs/agent-sdk) (headless). The
agent correlates **multiple telemetry sources**, identifies the most likely root cause, and writes a
structured RCA + mitigation + prevention report back onto the incident and to Slack.

It does the first-responder toil -- triage, correlation, hypothesis, evidence-gathering -- the moment
an alert pages, so a human joins the bridge already holding the answer. Modeled on the
[AWS DevOps Agent + Datadog MCP pattern](https://aws.amazon.com/blogs/devops/production-ready-autonomous-incident-resolution-with-aws-devops-agent-now-ga-and-datadog-mcp-server/),
built on Grafana/Prometheus + Kubernetes + AWS.

## Architecture

[![Architecture diagram](infra/architecture.drawio)](infra/architecture.drawio)

Open `infra/architecture.drawio` in [draw.io](https://app.diagrams.net/) or the VS Code Draw.io
extension for the full interactive diagram.

**Incident flow (hot path):**

```
PagerDuty incident.triggered (V3 webhook)
  [1] API Gateway v2  POST /webhook/pagerduty
        * Lambda HMAC-SHA256 authorizer  (verify X-PagerDuty-Signature)
        * SQS-SendMessage direct integration  (no Lambda in the hot path)
  [2] SQS Queue  (sre-agent)
  [3] ECS Fargate Task  sre-agent  (arm64 / Wolfi base / zero-CVE)
        * sqs_consumer.py  --  long-polls the queue
        * agent_runner.py  --  Claude Agent SDK  (claude-opus-4-8)
        * MCP clients: PagerDuty / Grafana / Kubernetes / AWS / GitHub / Slack
        * 7 subagents run in parallel:
            metrics-analyst    logs-analyst    trace-analyst    k8s-investigator
            aws-investigator   deploy-correlator   incident-scribe
        * ADOT sidecar  --  OTLP metrics/logs to CloudWatch
        * Langfuse sidecar  --  OTLP traces for LLM observability
  [4] incident-scribe posts RCA note (PagerDuty) + stakeholder update (Slack)
```

## Safety model (read this first)

**This agent is strictly read-only against production. It never mutates prod.** Mitigation steps are
*recommended*, never executed. The read-only contract is enforced in depth:

1. **Permission allowlist** -- [`.claude/settings.json`](.claude/settings.json) allows only read
   verbs (`kubectl get/describe/logs`, `aws describe/list/get`, read-only MCP tools) and denies
   everything else by default.
2. **PreToolUse guardrail hook** -- [`.claude/hooks/block_mutations.py`](.claude/hooks/block_mutations.py)
   hard-denies any mutating command or non-allowlisted MCP write, even if a permission rule is missed.
3. **Read-scoped credentials** -- Grafana VIEWER token, AWS read-only IAM, GitHub read scope, K8s
   read-only RBAC. The agent *cannot* mutate even if it tried.
4. **Audit trail** -- [`.claude/hooks/audit_log.py`](.claude/hooks/audit_log.py) records every tool
   call to JSONL for the postmortem.

## Project layout

| Path | Purpose |
|---|---|
| [AGENTS.md](AGENTS.md) | Canonical agent operating manual (SRE method, golden signals, guardrails) |
| [CLAUDE.md](CLAUDE.md) | Claude-specific pointer to AGENTS.md + skill/subagent/MCP map |
| [.mcp.json](.mcp.json) | MCP server definitions (pagerduty, grafana, kubernetes, aws, github, slack, drawio) |
| [.claude/settings.json](.claude/settings.json) | Read-only permission model + hook wiring |
| [.claude/agents/](.claude/agents/) | Specialized investigation subagents |
| [.claude/skills/](.claude/skills/) | Triage playbook, signal-analysis recipes, RCA template, runbooks |
| [.claude/hooks/](.claude/hooks/) | `block_mutations.py` (deny writes), `audit_log.py` |
| [src/](src/) | FastAPI webhook receiver + Agent SDK runner |
| [tests/](tests/) | Signature, webhook, and guardrail tests |
| [infra/Dockerfile](infra/Dockerfile) | Multi-stage Docker build (Wolfi base, zero-CVE, arm64) |
| [infra/architecture.drawio](infra/architecture.drawio) | Full AWS architecture diagram |
| [infra/terraform/](infra/terraform/) | Terraform modules for all AWS infrastructure |

## Quickstart (local, dry-run)

```bash
# 1. Install
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# 2. Configure -- duplicate .env.example as .env and fill in tokens (keep DRY_RUN=1)

# 3. Run the tests (no credentials needed -- guardrails + signature + webhook)
pytest -q

# 4. Start the receiver
uvicorn src.webhook_server:app --host 0.0.0.0 --port 8080

# 5. Fire a sample incident (valid HMAC computed from PAGERDUTY_WEBHOOK_SECRET)
python -m tests.send_sample   # posts tests/fixtures/pagerduty_incident_v3.json
```

In `DRY_RUN=1` the agent runs the full investigation but the scribe **logs** the RCA instead of
posting to PagerDuty/Slack -- safe for local end-to-end testing.

## Infrastructure (Terraform)

All AWS resources live under [`infra/terraform/`](infra/terraform/).

```
infra/terraform/
    main.tf                     root module -- S3 backend, 8 module calls
    variables.tf / outputs.tf
    terraform.tfvars.example    fill in before first apply
    modules/
        networking/             VPC, NAT GWs, SGs, VPC endpoints
        iam/                    ECS task + execution roles, API GW role, CloudTrail role
        secrets/                8 SecretsManager secrets + 8 SSM parameters
        queue/                  SQS queue + DLQ + CloudWatch alarm
        api-gateway/            HTTP API v2 + Lambda HMAC authorizer + SQS direct integration
        ecs/                    ECS Fargate cluster + task definition (agent + ADOT sidecar)
        langfuse/               Langfuse ECS service + RDS Postgres + ElastiCache Redis
        observability/          CloudWatch log groups, dashboard, CloudTrail
```

```bash
cd infra/terraform
# Duplicate terraform.tfvars.example as terraform.tfvars and fill in your values
terraform init
terraform plan
terraform apply
```

All modules use official AWS-verified Terraform modules (`terraform-aws-modules/*`) at their latest
stable versions.

## Docker image

Built for `linux/arm64` (Apple Silicon / ECS Graviton), zero-CVE Chainguard Wolfi base.

```bash
docker build -f infra/Dockerfile -t sre-agent:local .

# CVE scan (filesystem -- 0 vulns after undici patch)
trivy image sre-agent:local

# Layer efficiency analysis
dive sre-agent:local
```

Image stats: ~987 MB uncompressed / ~252 MB pushed, 99.94% layer efficiency.

## Going live

1. **Provision infra** -- `terraform apply` in `infra/terraform/` after filling in `terraform.tfvars`.
2. **Build and push** the Docker image to ECR (`linux/arm64`).
3. **PagerDuty webhook** -- create a V3 subscription pointing at the API Gateway URL for
   `incident.triggered`; store the signing secret in Secrets Manager.
4. **Provision read-only credentials** for every data source (see `.env.example`).
5. **Set `DRY_RUN=0`** only after a staged test confirms the audit log shows **zero** mutating calls.

## Extending

- **Add a service runbook:** drop a file in
  [.claude/skills/service-runbooks/](.claude/skills/service-runbooks/) using the template.
- **Add a data source:** add an MCP server to [.mcp.json](.mcp.json) and allowlist its read tools in
  [.claude/settings.json](.claude/settings.json).
- **Future: propose-for-approval remediation** -- gate write actions behind a Slack approval hook
  (deliberately out of scope in this read-only release).
