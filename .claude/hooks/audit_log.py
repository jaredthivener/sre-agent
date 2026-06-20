#!/usr/bin/env python3
"""PostToolUse audit trail — layer 4 of the read-only contract.

Appends one JSONL record per tool call to an audit log so that, after any incident, you can prove
exactly what the agent touched — and confirm it took zero mutating actions. Read by the staged
go-live check described in the README.

Records are written to $SRE_AGENT_AUDIT_LOG (default: audit/tool-calls.jsonl). Never throws into the
agent's path: any failure is swallowed so auditing can't break an investigation.
"""
from __future__ import annotations

import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

_DEFAULT_PATH = "audit/tool-calls.jsonl"
# Keys whose values may contain secrets; redacted before they ever hit the log.
_REDACT_HINTS = ("token", "secret", "password", "key", "authorization", "credential")


def _redact(obj):
    if isinstance(obj, dict):
        return {
            k: ("***REDACTED***" if any(h in k.lower() for h in _REDACT_HINTS) else _redact(v))
            for k, v in obj.items()
        }
    if isinstance(obj, list):
        return [_redact(v) for v in obj]
    return obj


def build_record(event: dict) -> dict:
    return {
        "ts": datetime.now(timezone.utc).isoformat(),
        "session_id": event.get("session_id"),
        "tool_name": event.get("tool_name"),
        "tool_input": _redact(event.get("tool_input", {})),
        # Truncate large outputs; we only need a fingerprint for the audit.
        "tool_response_preview": str(event.get("tool_response", ""))[:500],
    }


def main() -> int:
    try:
        event = json.load(sys.stdin)
    except (json.JSONDecodeError, ValueError):
        return 0

    try:
        path = Path(os.environ.get("SRE_AGENT_AUDIT_LOG", _DEFAULT_PATH))
        path.parent.mkdir(parents=True, exist_ok=True)
        with path.open("a", encoding="utf-8") as fh:
            fh.write(json.dumps(build_record(event)) + "\n")
    except OSError:
        # Auditing must never break an investigation.
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
