---
name: k8s-diagnostics
description: Read-only Kubernetes triage trees for common pod/workload failure modes — CrashLoopBackOff, OOMKilled, Pending/unschedulable, ImagePullBackOff, probe failures, and bad rollouts. Use when an incident may be workload- or cluster-related. Backs the k8s-investigator subagent.
---

# Kubernetes diagnostics — read-only triage trees

Diagnose workload/cluster failures with **read-only** `kubectl` (`get/describe/logs/top/events`) and
the Kubernetes MCP server. **Never** `apply/delete/edit/scale/patch/rollout/exec` — recommend those
in the report; they are blocked.

## Start here
```bash
kubectl get pods -n $ns -o wide -l app=$svc        # status, restarts, age, node
kubectl rollout history deployment/$svc -n $ns      # recent rollouts?
kubectl get events -n $ns --sort-by=.lastTimestamp | tail -50
kubectl top pods -n $ns -l app=$svc                 # CPU/mem vs limits
```

## Triage trees by symptom

**CrashLoopBackOff**
→ `kubectl logs $pod -n $ns --previous` (the crash output is in the *previous* container).
→ App error on startup? bad config/secret? failed migration? → check recent deploy (deploy-correlator).
→ OOMKilled on start? → memory limit too low (see below).

**OOMKilled** (`describe pod` → `Last State: Terminated, Reason: OOMKilled`)
→ Compare `container_memory_working_set_bytes` to the memory **limit**. Hit the ceiling?
→ Leak (steady climb) vs step-change after a deploy vs load-driven. → Recommend: raise limit / fix
   leak / roll back the deploy that raised footprint.

**Pending / FailedScheduling** (`describe pod` → events)
→ Insufficient cpu/memory on nodes (cluster saturation) → recommend scale nodes / right-size requests.
→ Node affinity / taints / PVC unbound / no nodes Ready.

**ImagePullBackOff / ErrImagePull**
→ Bad image tag (typo in a deploy), missing registry credential, or registry outage. → strong
   change-induced signal; check the rollout's image vs last-known-good.

**Probe failures** (`describe pod` → `Unhealthy` events)
→ Readiness failing → pods out of rotation → capacity drop → latency/errors. Liveness failing →
   restart loop. Check probe path/timeout vs a recently changed app.

**Bad rollout**
→ New ReplicaSet created near `T0`? Compare image/config of new vs old RS. Recommend rollback to the
   prior revision (give the exact revision number / image) — hand the target to deploy-correlator to
   tie back to the PR.

## Node-level
```bash
kubectl get nodes -o wide                 # NotReady? pressure conditions?
kubectl describe node $node               # MemoryPressure/DiskPressure/PIDPressure, taints
kubectl top nodes
```

## Output
Workload health summary with the anomaly + timing; whether a rollout occurred and the image/config
delta; most likely k8s-level cause; **recommended** (not executed) remediation with the exact target;
confidence + gaps.
