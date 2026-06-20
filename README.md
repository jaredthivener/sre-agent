# Autonomous SRE Agent

A **PagerDuty-triggered, read-only Site Reliability Engineer agent**. When an incident fires, a
webhook invokes the [Claude Agent SDK](https://docs.claude.com/en/docs/agent-sdk) (headless). The
agent correlates **multiple telemetry sources**, identifies the most likely root cause, and writes a
structured RCA + mitigation + prevention report back onto the incident and to Slack.

It does the first-responder toil — triage, correlation, hypothesis, evidence-gathering — the moment
an alert pages, so a human joins the bridge already holding the answer. Modeled on the
[AWS DevOps Agent + Datadog MCP pattern](https://aws.amazon.com/blogs/devops/production-ready-autonomous-incident-resolution-with-aws-devops-agent-now-ga-and-datadog-mcp-server/),
built on Grafana/Prometheus + Kubernetes + AWS.

## Safety model (read this first)

**This agent is strictly read-only against production. It never mutates prod.** Mitigation steps are
*recommended*, never executed. The read-only contract is enforced in depth:

1. **Permission allowlist** — [`.claude/settings.json`](.claude/settings.json) allows only read
   verbs (`kubectl get/describe/logs`, `aws … describe/list/get`, read-only MCP tools) and denies
   everything else by default.
2. **PreToolUse guardrail hook** — [`.claude/hooks/block_mutations.py`](.claude/hooks/block_mutations.py)
   hard-denies any mutating command or non-allowlisted MCP write, even if a permission rule is missed.
3. **Read-scoped credentials** — Grafana VIEWER token, AWS read-only IAM, GitHub read scope, K8s
   read-only RBAC. The agent *cannot* mutate even if it tried.
4. **Audit trail** — [`.claude/hooks/audit_log.py`](.claude/hooks/audit_log.py) records every tool
   call to JSONL for the postmortem.

## How it works

```
PagerDuty incident.triggered (V3 webhook)
  └─> FastAPI receiver (verify HMAC signature, ACK 202 fast, run agent async)
  └─> Claude Agent SDK (headless, read-only) loads AGENTS.md + skills + subagents + .mcp.json
  └─> ORCHESTRATOR runs the incident-triage skill:
        1. pull incident context (PagerDuty MCP)
        2. fan out to context-isolated subagents in parallel:
             metrics-analyst (Prometheus) · logs-analyst (Loki) · trace-analyst (Tempo/Sift)
             k8s-investigator (kubectl RO) · aws-investigator (CloudWatch/ECS/Lambda RO)
             deploy-correlator (GitHub: what changed?)
        3. correlate evidence → rank hypotheses → confirm root cause
        4. incident-scribe writes the RCA and posts it (PagerDuty note + Slack)
```

See [AGENTS.md](AGENTS.md) for the full operating doctrine, and the
[implementation plan](.) for design rationale.

## Project layout

| Path | Purpose |
|---|---|
| [AGENTS.md](AGENTS.md) | Canonical agent operating manual (SRE method, golden signals, guardrails) |
| [CLAUDE.md](CLAUDE.md) | Claude-specific pointer to AGENTS.md + skill/subagent/MCP map |
| [.mcp.json](.mcp.json) | MCP server definitions (pagerduty, grafana, kubernetes, aws, github, slack) |
| [.claude/settings.json](.claude/settings.json) | Read-only permission model + hook wiring |
| [.claude/agents/](.claude/agents/) | Specialized investigation subagents |
| [.claude/skills/](.claude/skills/) | Triage playbook, signal-analysis recipes, RCA template, runbooks |
| [.claude/hooks/](.claude/hooks/) | `block_mutations.py` (deny writes), `audit_log.py` |
| [src/](src/) | FastAPI webhook receiver + Agent SDK runner |
| [tests/](tests/) | Signature, webhook, and guardrail tests |
| [deploy/](deploy/) | Dockerfile + read-only K8s deployment |

## Quickstart (local, dry-run)

```bash
# 1. Install
python -m venv .venv && source .venv/bin/activate
pip install -e ".[dev]"

# 2. Configure (READ-ONLY credentials only)
cp .env.example .env   # fill in tokens; keep DRY_RUN=1 for local testing

# 3. Run the tests (no credentials needed — guardrails + signature + webhook)
pytest -q

# 4. Start the receiver
uvicorn src.webhook_server:app --host 0.0.0.0 --port 8080

# 5. Fire a sample incident (valid HMAC computed from PAGERDUTY_WEBHOOK_SECRET)
python -m tests.send_sample   # posts tests/fixtures/pagerduty_incident_v3.json
```

In `DRY_RUN=1` the agent runs the full investigation but the scribe **logs** the RCA instead of
posting to PagerDuty/Slack — safe for local end-to-end testing.

## Going live

1. Create a **PagerDuty V3 webhook subscription** pointing at `https://<host>/webhook/pagerduty`
   for `incident.triggered`; copy the signing secret to `PAGERDUTY_WEBHOOK_SECRET`.
2. Provision **read-only** credentials for every data source (see `.env.example`).
3. Deploy with [deploy/](deploy/) under a read-only Kubernetes ServiceAccount.
4. Set `DRY_RUN=0` only after a staged test confirms the audit log shows **zero** mutating calls.

## Extending

- **Add a service runbook:** drop a file in
  [.claude/skills/service-runbooks/](.claude/skills/service-runbooks/) using the template.
- **Add a data source:** add an MCP server to [.mcp.json](.mcp.json) and allowlist its read tools in
  [.claude/settings.json](.claude/settings.json).
- **Future: propose-for-approval remediation** — gate write actions behind a Slack approval hook
  (deliberately out of scope in this read-only release).
