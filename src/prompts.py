"""Builds the investigation prompt handed to the agent for a given incident.

The agent's *doctrine* lives in AGENTS.md/CLAUDE.md (loaded as system prompt via setting_sources).
This module only assembles the incident-specific kickoff message.
"""
from __future__ import annotations

from .pagerduty import IncidentEvent


def build_incident_prompt(incident: IncidentEvent, slack_channel: str, dry_run: bool) -> str:
    """Compose the user-turn prompt that kicks off the investigation."""
    dry_run_note = (
        "DRY_RUN is ON: do NOT post to PagerDuty or Slack. Instead, have the incident-scribe output "
        "the full rendered RCA report and the condensed Slack message in its response."
        if dry_run
        else "DRY_RUN is OFF: post the report as a PagerDuty incident note and to the Slack channel."
    )

    return f"""\
You have been paged. Investigate this PagerDuty incident now by running the `incident-triage` skill.

## Incident
- Title: {incident.title}
- Incident ID: {incident.incident_id}
- Incident #: {incident.incident_number}
- Service: {incident.service}
- Urgency: {incident.urgency}
- Status: {incident.status}
- Triggered at (T0): {incident.created_at}
- Link: {incident.html_url}

## Your task
Follow the SRE method in AGENTS.md and the `incident-triage` playbook:
1. Orient and triage (scope, blast radius, provisional severity). Check `service-runbooks` for a
   runbook matching "{incident.service}".
2. Run `deploy-correlator` early — what changed near T0?
3. Fan out to the relevant subagents in parallel (metrics / logs / traces / k8s / aws).
4. Correlate findings on one timeline anchored to T0; rank hypotheses; verify the top one.
5. Produce a recommended (NOT executed) mitigation, the root cause, and a prevention follow-up.
6. Hand off to `incident-scribe` to deliver the RCA.

## Delivery
Slack incident channel: {slack_channel}
{dry_run_note}

## Non-negotiable
You are READ-ONLY against production. Recommend mitigations; never execute them. Cite evidence for
every claim. Redact secrets. Be fast — a good answer in minutes beats a perfect one in an hour.
"""
