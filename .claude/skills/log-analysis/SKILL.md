---
name: log-analysis
description: Method and LogQL recipes for analyzing Loki logs during an incident — finding the onset moment, detecting new vs known errors, and extracting the actual error text behind a metrics anomaly. Use when you need the human-readable "why". Backs the logs-analyst subagent.
---

# Log analysis — onset, new-error detection & LogQL

Find the *why* behind an anomaly and pin the **onset moment**, via the Grafana MCP server's Loki
access. Read-only. Distinguish **causal** errors (new) from **symptomatic** ones (known errors
spiking under load).

## What to determine
1. **First occurrence** of the failure pattern in the window — the onset timestamp for correlation.
2. **New vs known:** a brand-new error string at onset is likely the cause; a known error spiking in
   volume is usually a symptom of load/saturation.
3. **Self vs downstream:** are the errors generated here, or are they timeouts/refusals from a
   dependency?

## LogQL recipes (adapt labels to your stack)

**Error volume over the window:**
```logql
sum(count_over_time({service="$svc"} |= "error" [5m]))
```

**Top error lines (group to find the dominant pattern):**
```logql
topk(10, sum by (msg) (count_over_time({service="$svc"} | json | level="error" [1h])))
```

**First occurrence of a specific pattern (narrow the time range to bisect onset):**
```logql
{service="$svc"} |= "context deadline exceeded"
```

**Errors excluding known-noise (surface the new thing):**
```logql
{service="$svc"} | json | level="error" != "ContextCanceled" != "client disconnected"
```

**Dependency failures:**
```logql
{service="$svc"} |~ "(connection refused|timeout|ECONNREFUSED|5\\d\\d|pool exhausted|too many open files)"
```

## Tell-tale strings → likely cause
| String | Points to |
|---|---|
| `OOMKilled`, `cannot allocate memory` | memory saturation (→ k8s-investigator) |
| `context deadline exceeded`, `timeout` | slow/erroring downstream (→ trace-analyst) |
| `connection refused`, `ECONNREFUSED` | dependency down / wrong endpoint |
| `pool exhausted`, `too many connections` | connection-pool saturation |
| `429`, `throttl`, `quota` | rate limiting / service-quota cap (→ aws-investigator) |
| `permission denied`, `403`, `expired`, `x509` | credential/cert rotation (→ deploy-correlator) |
| `panic`, new stack trace at onset | code bug from a recent deploy (→ deploy-correlator) |

## Method
1. Get error volume over the window; find the spike edge.
2. Bisect to the first occurrence; capture that timestamp.
3. Group errors by pattern; identify the dominant one and whether it's new.
4. Pull a representative, **redacted** sample (no secrets/PII).

## Output
Onset timestamp (relative to `T0`); dominant pattern(s) with counts + sample; causal vs symptomatic;
any implicated dependency; confidence + gaps; the LogQL you ran.
