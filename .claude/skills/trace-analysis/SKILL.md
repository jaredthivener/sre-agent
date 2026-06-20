---
name: trace-analysis
description: Method for localizing latency and errors across a distributed request path using Tempo traces and Grafana Sift investigations. Use when an incident spans multiple services or involves elevated latency, to find the failing edge in the dependency graph. Backs the trace-analyst subagent.
---

# Trace analysis — fault localization across the request path

Find *where* in the request path the problem lives, via the Grafana MCP server (Tempo + Sift).
Read-only. The goal is to tell **cause from victim**: is the affected service slow itself, or waiting
on a slow/erroring downstream?

## Method
1. **Pull exemplars.** Get traces for slow and failing requests in the window — prioritize traces
   right at the onset edge. If metrics gave you a p99 spike, find the exemplar behind it.
2. **Walk the spans.** Identify the span that contributes the latency or carries the error status.
   Compare the affected service's *self* time vs time spent *waiting on children*:
   - high self time → CPU / GC / lock contention / slow local work,
   - high child wait → a downstream dependency is the real culprit.
3. **Map the dependency graph** for the path and mark the unhealthy edge. Follow it: the failing edge
   often points to the service you should actually be investigating.
4. **Run Grafana Sift** on the affected resource + window if available — it auto-surfaces correlated
   anomalies (error-log patterns, noisy-neighbor pods, related firing alerts) and can short-circuit a
   lot of manual correlation.
5. **Compare to a healthy baseline trace** so "what changed" in the path is obvious.

## What to look for
- A single downstream span whose latency/error rate jumped at onset → that dependency is the cause.
- Fan-out amplification (one slow dependency × many calls per request) → latency multiplied.
- Retries storms (the same span repeated) → a retry config turning a blip into an outage.
- A newly-appearing span / changed call pattern → corroborates a recent deploy.

## Output
The origin span/service of the latency or error (the failing edge); cause vs victim verdict for the
affected service; any Sift findings; trace IDs/links; confidence + gaps (e.g. low sampling).
