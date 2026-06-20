"""Runs the Claude Agent SDK headless for one incident investigation.

Loads the project's `.claude/` settings (read-only permissions + guardrail hooks), the `.mcp.json`
data-source servers, the AGENTS.md operating doctrine as the system prompt, and the filesystem
subagents — then streams the investigation to completion and returns a transcript.
"""
from __future__ import annotations

import logging
from pathlib import Path

from .config import Settings
from .pagerduty import IncidentEvent
from .prompts import build_incident_prompt

logger = logging.getLogger("sre_agent.runner")


def _load_system_prompt(project_root: Path) -> str:
    """The agent's operating doctrine is AGENTS.md (CLAUDE.md is a thin pointer to it)."""
    agents_md = project_root / "AGENTS.md"
    if agents_md.exists():
        return agents_md.read_text(encoding="utf-8")
    logger.warning("AGENTS.md not found at %s; falling back to a minimal read-only prompt", agents_md)
    return (
        "You are an autonomous SRE. Investigate the incident read-only, correlate telemetry, and "
        "produce a root-cause analysis with a recommended (never executed) mitigation."
    )


async def run_investigation(incident: IncidentEvent, settings: Settings) -> str:
    """Investigate one incident headlessly. Returns the assistant transcript.

    Read-only is enforced by `.claude/settings.json` (permission allowlist + PreToolUse guardrail
    hook), which is loaded via `setting_sources=["project"]`. `permission_mode="dontAsk"` denies
    anything not pre-approved — there is no human in the loop to answer a prompt.
    """
    # Imported lazily so the webhook server (and its tests) don't require the SDK to be installed
    # just to receive and route a webhook.
    from claude_agent_sdk import (
        AssistantMessage,
        ClaudeAgentOptions,
        ResultMessage,
        TextBlock,
        query,
    )

    project_root = Path(settings.project_root).resolve()

    options = ClaudeAgentOptions(
        cwd=str(project_root),
        model=settings.orchestrator_model,
        system_prompt=_load_system_prompt(project_root),
        # Load .claude/settings.json (permissions + hooks) and the filesystem subagents/skills.
        setting_sources=["project"],
        # Deny anything not on the allowlist — non-interactive run, fail closed.
        permission_mode="dontAsk",
        # Data-source MCP servers (read-only credentials); CLI expands ${ENV} placeholders.
        mcp_servers=str(project_root / ".mcp.json"),
    )

    prompt = build_incident_prompt(
        incident, slack_channel=settings.slack_incident_channel, dry_run=settings.dry_run
    )

    logger.info(
        "Starting investigation for incident %s (%s) dry_run=%s",
        incident.incident_id, incident.service, settings.dry_run,
    )

    transcript: list[str] = []
    async for message in query(prompt=prompt, options=options):
        if isinstance(message, AssistantMessage):
            for block in message.content:
                if isinstance(block, TextBlock) and block.text.strip():
                    transcript.append(block.text)
                    logger.debug("agent: %s", block.text[:200])
        elif isinstance(message, ResultMessage):
            logger.info(
                "Investigation finished for %s: subtype=%s turns=%s cost=$%.4f is_error=%s",
                incident.incident_id, message.subtype, message.num_turns,
                message.total_cost_usd or 0.0, message.is_error,
            )

    return "\n\n".join(transcript)
