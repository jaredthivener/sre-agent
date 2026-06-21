#!/usr/bin/env python3
"""PreToolUse guardrail — layer 2 of the read-only contract.

The SRE agent is investigate-and-recommend only: it must never mutate production. The permission
allowlist in `.claude/settings.json` is the first line of defense; this hook is the second. It
hard-denies any mutating shell command or MCP write tool even if a permission rule is missing or
too broad.

Hook protocol: reads a PreToolUse event as JSON on stdin, prints a PreToolUse decision as JSON on
stdout, exits 0. `decide()` is a pure function so it can be unit-tested directly.
"""
from __future__ import annotations

import json
import re
import sys

# Mutating verbs/subcommands for CLI tools we expose via Bash. Matched case-insensitively as
# whole words anywhere in the command (covers pipes, env prefixes, and flag noise).
_MUTATING_CLI_PATTERNS: list[re.Pattern[str]] = [
    # kubectl / helm
    re.compile(r"\bkubectl\b.*\b(apply|delete|edit|scale|patch|rollout|cordon|drain|uncordon|"
               r"exec|replace|create|label|annotate|set|taint|expose|run|attach|cp)\b"),
    re.compile(r"\bhelm\b.*\b(install|upgrade|uninstall|rollback|delete)\b"),
    # aws — write-shaped operation. AWS CLI operations are `verb-noun` (e.g. delete-table,
    # put-object). Match the verb only when it begins an operation token (preceded by whitespace,
    # not by `-`), so read flags like `--start-time` / `--max-items` don't false-positive.
    re.compile(r"\baws\b.*(?<![-\w])(create|update|delete|put|terminate|modify|reboot|run|start|"
               r"stop|set|attach|detach|associate|disassociate|register|deregister|enable|disable|"
               r"reset|restore|cancel|publish|send|invoke|remove|add|tag|untag|reset|import)-"),
    # aws s3 high-level mutating verbs (no hyphen): `aws s3 cp|mv|rm|rb|sync`
    re.compile(r"\baws\s+s3\s+(cp|mv|rm|rb|sync)\b"),
    # git write ops
    re.compile(r"\bgit\b.*\b(push|commit|reset|checkout|merge|rebase|tag|branch\s+-[dD]|"
               r"clean|stash\s+drop)\b"),
    # destructive shell
    re.compile(r"\brm\b"),
    re.compile(r"\bsudo\b"),
    re.compile(r"\b(mv|cp|chmod|chown|truncate|dd|mkfs|tee)\b"),
    re.compile(r">>?"),          # output redirection = a write
    re.compile(r"\b(curl|wget)\b"),  # exfil / arbitrary network egress
]

# MCP tools that mutate state. Matched as a substring against the (namespaced) tool name.
_MUTATING_MCP_SUBSTRINGS: tuple[str, ...] = (
    "create", "update", "delete", "put", "patch", "modify", "remove", "edit", "write",
    "set_", "resolve", "acknowledge", "manage_incident", "snooze", "merge", "add_responder",
    "scale", "restart", "rollout", "apply", "terminate", "reboot",
)

# Built-in tools that mutate the workspace directly.
_MUTATING_BUILTIN_TOOLS: tuple[str, ...] = (
    "Write",
    "Edit",
    "MultiEdit",
    "NotebookEdit",
)

# MCP write tools we DO allow — the agent's only sanctioned outbound writes (posting findings).
_ALLOWED_MCP_WRITES: tuple[str, ...] = (
    "mcp__pagerduty__add_note_to_incident",
    "mcp__slack__post_message",
    "mcp__slack__postMessage",
)

_DENY = "deny"
_ALLOW = "allow"


def decide(tool_name: str, tool_input: dict) -> dict:
    """Return a PreToolUse decision dict for the given tool call.

    `permissionDecision` is "deny" to block, or "allow"/"" to defer to normal permission rules.
    """
    name = tool_name or ""

    # Bash: scan the command string for mutating patterns.
    if name == "Bash":
        command = (tool_input or {}).get("command", "") or ""
        for pattern in _MUTATING_CLI_PATTERNS:
            if pattern.search(command):
                return _deny(f"Blocked mutating shell command (matched /{pattern.pattern}/). "
                             f"The SRE agent is read-only; recommend this action in the RCA instead.")
        return _ok()

    # Built-in file tools: deny workspace mutations even though they are not shell commands.
    if name in _MUTATING_BUILTIN_TOOLS:
        return _deny(f"Blocked mutating built-in tool '{name}'. The SRE agent is read-only; "
                     f"recommend this action in the RCA instead.")

    # MCP tools: explicitly allow the sanctioned writes, deny anything else mutating.
    if name.startswith("mcp__"):
        if name in _ALLOWED_MCP_WRITES:
            return _ok()
        lowered = name.lower()
        for needle in _MUTATING_MCP_SUBSTRINGS:
            if needle in lowered:
                return _deny(f"Blocked mutating MCP tool '{name}'. The SRE agent is read-only; "
                             f"recommend this action in the RCA instead.")
        return _ok()

    return _ok()


def _deny(reason: str) -> dict:
    return {"permissionDecision": _DENY, "permissionDecisionReason": reason}


def _ok() -> dict:
    # Empty decision = defer to the normal permission system (allowlist in settings.json).
    return {"permissionDecision": "", "permissionDecisionReason": ""}


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        # Fail closed on unparseable input.
        event = {}

    decision = decide(event.get("tool_name", ""), event.get("tool_input", {}))
    output = {
        "hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            **decision,
        }
    }
    print(json.dumps(output))
    return 0


if __name__ == "__main__":
    sys.exit(main())
