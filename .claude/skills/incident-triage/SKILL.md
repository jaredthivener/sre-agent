---
name: incident-triage
description: Master incident-response playbook for the autonomous SRE agent. Use this the moment a PagerDuty incident arrives — it drives the whole investigation from triage through correlated diagnosis to a recommended (never executed) mitigation. Orchestrates the specialized subagents and the other skills.
---

# Incident triage — master playbook

This is the playbook you run for **every** incident. You are the orchestrator: fan out to
context-isolated subagents, then converge on a ranked root cause. **Read-only — recommend, never
mutate.**

## 0. Orient (≤ 30s)
From the incident prompt, extract: **affected service**, **`T0`** (triggered-at), **urgency**, and
any **alert detail/links**. Set the window to `[T0 − 60m, now]` (widen for slow-burn issues).
Pull richer context from PagerDuty if needed (`get_incident`, `list_incident_notes`) and **check for
a matching service runbook** (`service-runbooks` skill) — if one exists, let it steer your checks.

## 1. Triage — scope & severity
Answer: *what is broken, for whom, how badly, since when?* Establish blast radius (pod → AZ →
service → downstream) and assign a provisional SEV (see AGENTS.md §7). Frame against SLO/error budget
if known. Write this down — it anchors the report's TL;DR.

## 2. Change first — run `deploy-correlator` immediately
Most incidents are change-induced. Dispatch `deploy-correlator` right away to answer **"what
changed?"** in the window. A deploy/PR/config change aligned with `T0` is your leading hypothesis
until disproven. (Use the `deploy-correlation` skill's method.)

## 3. Fan out — dispatch subagents in parallel
Based on the alert and signals so far, dispatch the relevant subagents **concurrently** (don't
serialize independent work). Give each the service, `T0`, and the window:

| If the signal / question is… | Dispatch | Skill it uses |
|---|---|---|
| how bad / which golden signal moved | `metrics-analyst` | `metric-correlation` |
| what's the actual error / onset moment | `logs-analyst` | `log-analysis` |
| where in the request path / which dependency | `trace-analyst` | `trace-analysis` |
| pod health, rollouts, OOM, scheduling | `k8s-investigator` | `k8s-diagnostics` |
| managed-service / cloud resource health | `aws-investigator` | — |

Default to running `metrics-analyst` + `logs-analyst` + `deploy-correlator` at minimum; add the
others when the signal points their way.

## 4. Correlate on one timeline
Lay every finding on the same timeline anchored to `T0`:
- the **onset edge** (first error from logs, first metric inflection),
- the **change** (deploy/config from deploy-correlator),
- the **failing component** (span from traces, pod/resource from k8s/aws).
A change immediately preceding the onset edge, touching the failing component, is a strong causal
chain. Resolve any contradictions between subagents before concluding.

## 5. Hypothesize, rank, and verify
Form 1–3 explicit hypotheses. For your top one, actively seek **disconfirming** evidence — try to
break it, don't just confirm it. Prefer the explanation covering the most signals with the fewest
assumptions. Assign honest confidence (high/medium/low).

## 6. Recommend (do NOT execute)
Decide the fastest safe path back to green and the durable fix:
- **Immediate mitigation** — concrete commands/steps for a *human* (e.g. precise rollback target
  from deploy-correlator, scale-up, fail-over, raise a limit). Flag risk.
- **Root cause** — your ranked conclusion + ruled-out alternatives.
- **Prevention** — the follow-up that stops recurrence (5-whys, missing alert, guardrail).

## 7. Deliver — hand off to `incident-scribe`
Pass your synthesized findings to `incident-scribe`, which writes the report with the `rca-report`
template and posts it (PagerDuty note + Slack; logs only when `DRY_RUN=1`).

---

### Guardrails reminder
Read-only always. A denied tool call is the system working as designed — note the limitation, don't
route around it. No secrets in any output. Blameless tone. Speed matters: a good answer in 3 minutes
beats a perfect one in 30.
