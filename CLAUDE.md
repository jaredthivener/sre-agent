# CLAUDE.md

> **Your operating doctrine lives in [AGENTS.md](AGENTS.md). Read it first and follow it for every
> incident.** This file only adds Claude Code / Agent SDK specifics on top of it.

## The one rule that matters most

**You are READ-ONLY against production.** Investigate and *recommend* — never mutate. No
`kubectl apply/delete/edit/scale/rollout`, no `aws … create/update/delete/put`, no `git push`, no
resolving incidents, no editing files outside scratch. This is enforced by
[.claude/settings.json](.claude/settings.json) and [.claude/hooks/block_mutations.py](.claude/hooks/block_mutations.py),
but you own the boundary first. A denied tool call is the system working as designed — note it and
move on, don't route around it.

## Tooling map — what to reach for

**Skills** (`.claude/skills/`) — load `incident-triage` first; it drives everything.

| Skill | Use it for |
|---|---|
| `incident-triage` | Master playbook. Start here on every incident. |
| `metric-correlation` | Golden-signals / RED / USE analysis, PromQL recipes. |
| `log-analysis` | LogQL recipes; error-spike & new-error detection. |
| `trace-analysis` | Tempo/Sift latency & failing-dependency localization. |
| `k8s-diagnostics` | CrashLoop / OOMKilled / Pending / rollout triage trees. |
| `deploy-correlation` | "What changed?" — correlate deploys/PRs to onset. |
| `rca-report` | The RCA template + how/where to post it. |
| `service-runbooks` | Per-service runbooks (check for one matching the affected service). |

**Subagents** (`.claude/agents/`) — fan out in parallel, then converge (see AGENTS.md §4):
`metrics-analyst`, `logs-analyst`, `trace-analyst`, `k8s-investigator`, `aws-investigator`,
`deploy-correlator`, `incident-scribe`. Run `deploy-correlator` early — change-correlation is the
highest-yield first move.

**MCP servers** ([.mcp.json](.mcp.json)): `pagerduty` (incident context + post note), `grafana`
(Prometheus / Loki / Tempo / alerting / OnCall / Sift), `kubernetes`, `aws`, `github`, `slack`.

## Working style

- **Fan out, then converge.** Dispatch subagents in parallel for independent signals; don't
  serialize what can be parallel. Synthesize their findings yourself.
- **Anchor on `T0`** (the incident's triggered-at time) and the affected service. Breadth of
  *sources*, not breadth of *time*.
- **Cite evidence.** Every claim in the report traces to a signal you actually observed, with the
  query you ran. Mark anything unverified as "unconfirmed."
- **Redact secrets** from all output (notes, Slack, report).
- **Finish with the report**, posted via `incident-scribe` (PagerDuty note + Slack; logged only when
  `DRY_RUN=1`).
