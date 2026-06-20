---
name: deploy-correlation
description: Method for answering "what changed?" — correlating recent deploys, releases, merged PRs, config/flag changes, and code diffs against an incident's onset time via the GitHub MCP server. Use early in EVERY investigation; most incidents are change-induced. Backs the deploy-correlator subagent.
---

# Deploy correlation — "what changed?"

Most incidents follow a change (Google SRE; The Phoenix Project). This is the **highest-yield first
move** in any investigation. Read-only — you read history, you never push or revert.

## Method
1. **Anchor "what's running now."** Get the current revision from the workload: the running image tag
   / git SHA (from k8s-investigator) or the deployed release. This is the head of your suspect range.
2. **Enumerate changes in the window** (`[T0 − 60m, now]`, widen to hours for slow-burn): deployments
   / releases for the service, merged PRs, tags, and the commits between last-known-good and now.
   Don't forget the *non-code* changes that page just as often:
   - config / ConfigMap / parameter-store changes,
   - feature-flag flips,
   - secret / credential / certificate rotation,
   - infra/IaC changes, dependency version bumps, schema migrations.
3. **Time-align to onset.** Rank changes by proximity to `T0`. The closest one is the prime suspect.
   A change at `T0 − Nm` where the first error appears at `T0` is a tight causal chain.
4. **Assess blast plausibility.** Skim the suspect diff: does it touch the failing area (hot path,
   the erroring endpoint, the saturated resource, the config the app loads)? A risky diff landing at
   onset is a strong signal; an unrelated docs change is not.
5. **Identify the rollback target.** Record the precise last-known-good revision/tag/image so the
   report can recommend an exact rollback — the single most common effective mitigation.

## Verdicts
- **Change found at onset, touches failing area** → leading hypothesis; recommend rollback to LKG.
- **Change found but unrelated** → note it, keep it as a lower-ranked alternative.
- **No change in window** → likely *not* change-induced; pivot to load/saturation (metrics) or an
  external dependency / infra event (aws-investigator). This negative result is itself valuable.

## Output
Time-ordered changes (closest-to-onset first); the suspect change with a one-line "what it changed"
and why it's plausible; the exact last-known-good rollback target; confidence + gaps.

**Blameless:** describe the change, never the person who made it.
