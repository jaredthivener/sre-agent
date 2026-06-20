---
name: service-runbooks
description: Per-service incident runbooks. Check here at the start of every investigation — if a runbook exists for the affected service, it encodes known failure modes, key dashboards/queries, dependencies, and proven mitigations that should steer the triage. Add one file per service.
---

# Service runbooks

Institutional knowledge that turns a generic investigation into a targeted one. **At the start of
every incident, check whether a runbook exists for the affected service** — if so, let its known
failure modes and dashboards steer your checks before you go exploring.

## How to use
1. Match the incident's service to a runbook file in this directory (`<service-name>.md`).
2. If found: start from its **known failure modes** and **key signals** — these are the things that
   actually break this service. Use its dashboards/queries and dependency list directly.
3. If not found: fall back to the generic `incident-triage` flow, and note in the report that no
   runbook exists (a prevention follow-up: write one).

## How to add a runbook
Copy [`_example-service.md`](_example-service.md) to `<service-name>.md` and fill it in. Keep it
current — a stale runbook is worse than none. Good runbooks come out of postmortems: every resolved
incident should leave the relevant runbook a little better.

## Index
| Service | Runbook |
|---|---|
| _example-service_ | [_example-service.md](_example-service.md) (template) |
| _(add yours here)_ | |
