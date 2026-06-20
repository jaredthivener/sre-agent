---
name: rca-report
description: How to write and post the incident root-cause analysis using the standard template. Use as the final step of an investigation to assemble findings into a skimmable RCA and deliver it as a PagerDuty note + Slack message (or log it when DRY_RUN=1). Backs the incident-scribe subagent.
---

# RCA report — write & post

Turn correlated findings into one crisp, **skimmable** report. The on-call human is stressed —
**lead with the answer.** Read-only: the report *recommends* mitigations; it never executes them, and
you never resolve/acknowledge the incident.

## Use the template
Fill in [`template.md`](template.md). Rules:
- **Every section gets a value.** If something is unknown, write "unknown / needs human verification"
  — never silently drop a section.
- **Every evidence claim cites a signal** — a PromQL/LogQL query and the number it returned, a trace
  ID, a kubectl event, a CloudWatch alarm, a PR/commit SHA.
- **State confidence** (high/medium/low) on the root cause.
- **Blameless** throughout — describe changes and systems, not people.
- **Redact** all secrets/PII before posting.

## TL;DR quality bar
The TL;DR must stand alone — a reader who sees only it should know: *what's broken, blast radius,
severity, the leading cause, and the one action to take now.*

## Delivery
1. **PagerDuty note** — post the full rendered report via `add_note_to_incident` (incident id from
   the prompt).
2. **Slack** — post a condensed version to the incident channel: TL;DR + severity + top recommended
   action + a pointer to the full note. Use `post_message`.
3. **DRY_RUN=1** — do **not** post. Instead output the full rendered report *and* the condensed Slack
   message in your response so they're captured in the transcript/logs.

## After posting
Confirm what was posted where (or, in DRY_RUN, that it was rendered, not sent). Do not change the
incident's status.
