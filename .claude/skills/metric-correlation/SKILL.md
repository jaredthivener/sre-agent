---
name: metric-correlation
description: Method and PromQL recipes for analyzing Prometheus metrics during an incident — the four golden signals, RED, and USE. Use when characterizing how badly a service is degraded and which signal moved first. Backs the metrics-analyst subagent.
---

# Metric correlation — golden signals, RED & USE

Quantify the incident and find the **leading** signal (the one that moved first), via the Grafana
MCP server's Prometheus access. Read-only. Always compare **baseline vs incident** and find the
**inflection point** near `T0`.

## The frameworks
- **Four golden signals** (Google SRE): Latency, Traffic, Errors, Saturation.
- **RED** (request-driven services): Rate, Errors, Duration.
- **USE** (resources): Utilization, Saturation, Errors.

The causal order in most saturation incidents: **Saturation ↑ → Latency ↑ → Errors ↑**, with Traffic
as either a cause (spike) or effect (clients retrying / giving up). Find which moved first.

## PromQL recipes (adapt metric/label names to your stack)

**Error rate (RED — Errors):**
```promql
sum(rate(http_requests_total{service="$svc",code=~"5.."}[5m]))
  / sum(rate(http_requests_total{service="$svc"}[5m]))
```

**Request rate (RED — Rate / golden Traffic):**
```promql
sum(rate(http_requests_total{service="$svc"}[5m]))
```

**Latency p95/p99 (RED — Duration / golden Latency):**
```promql
histogram_quantile(0.95, sum(rate(http_request_duration_seconds_bucket{service="$svc"}[5m])) by (le))
histogram_quantile(0.99, sum(rate(http_request_duration_seconds_bucket{service="$svc"}[5m])) by (le))
```

**CPU saturation (throttling):**
```promql
sum(rate(container_cpu_cfs_throttled_periods_total{pod=~"$svc-.*"}[5m]))
  / sum(rate(container_cpu_cfs_periods_total{pod=~"$svc-.*"}[5m]))
```

**Memory saturation (→ OOM risk):**
```promql
max(container_memory_working_set_bytes{pod=~"$svc-.*"})
  / max(kube_pod_container_resource_limits{pod=~"$svc-.*",resource="memory"})
```

**Saturation — connection pool / queue (adapt to your exporters):**
```promql
max(db_connection_pool_in_use{service="$svc"}) / max(db_connection_pool_max{service="$svc"})
```

**Dependency error rate (is it us or downstream?):**
```promql
sum(rate(client_requests_total{service="$svc",code=~"5.."}[5m])) by (upstream)
```

## Method
1. Graph each signal across `[T0 − 60m, now]`; mark the inflection time.
2. Rank signals by *when* they moved; the earliest is your causal anchor.
3. Cross-check the leading signal against logs (onset error) and deploys (change time).
4. Report deviations with numbers ("p99 12ms → 4.3s at T0−1m") and the query you used.

## Output
Which signals deviated, by how much, when; the leading signal; 1–2 metric-supported hypotheses with
their queries; confidence + gaps.
