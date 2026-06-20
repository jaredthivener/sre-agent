# Runbook: <service-name>

> Template. Copy to `<service-name>.md` and fill in. Delete the guidance comments.

## Overview
- **What it does:** <one-line responsibility>
- **Owning team / Slack:** <#team-channel>
- **Tier / criticality:** <SEV mapping if it's down — e.g. "down = SEV1, customer checkout">
- **Repo(s):** <org/repo>

## Topology
- **Runtime:** <k8s namespace + deployment, and/or ECS service / Lambda function>
- **Upstream (callers):** <who calls this>
- **Downstream (dependencies):** <DBs, caches, queues, external APIs — these are your usual suspects>

## Key signals (golden-signal dashboards & queries)
- **Latency:** <Grafana dashboard link / PromQL>
- **Traffic:** <PromQL>
- **Errors:** <PromQL + the Loki query for its error logs>
- **Saturation:** <CPU/mem/pool/queue PromQL — and the resource that saturates first>

## Known failure modes (most→least common)
| Symptom | Usual cause | Recommended mitigation (human runs it) |
|---|---|---|
| <e.g. p99 latency spike> | <e.g. DB connection pool exhaustion under load> | <e.g. scale replicas; raise pool size> |
| <e.g. 5xx after deploy> | <e.g. bad migration / config> | <e.g. roll back to last-known-good> |
| <e.g. CrashLoop> | <e.g. OOM from memory leak> | <e.g. restart + raise limit; track leak> |

## Recent-change checklist
- Where deploys show up: <CD pipeline / release tag convention>
- Feature flags that affect it: <flag names / dashboard>
- Config / secret sources: <ConfigMap / param-store paths>

## Notes
<Anything an on-call would wish they'd known. Update after every incident.>
