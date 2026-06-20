"""PagerDuty V3 webhook handling: signature verification + payload parsing.

PagerDuty signs each V3 webhook with HMAC-SHA256 over the raw request body, using the subscription's
signing secret. The signature arrives in the `X-PagerDuty-Signature` header as one or more
comma-separated `v1=<hexdigest>` values (PagerDuty may send several during secret rotation). A
request is valid if ANY provided `v1` signature matches our computed digest.
"""
from __future__ import annotations

import hashlib
import hmac
from dataclasses import dataclass

_SIGNATURE_SCHEME = "v1"


def compute_signature(body: bytes, secret: str) -> str:
    """Return the hex HMAC-SHA256 of `body` under `secret` (no scheme prefix)."""
    return hmac.new(secret.encode("utf-8"), body, hashlib.sha256).hexdigest()


def verify_signature(body: bytes, signature_header: str | None, secret: str) -> bool:
    """Constant-time-verify a PagerDuty V3 webhook signature.

    `signature_header` is the raw `X-PagerDuty-Signature` value (e.g. "v1=abc,v1=def").
    Returns False on any missing/malformed input rather than raising — callers turn this into 401.
    """
    if not secret or not signature_header:
        return False

    expected = compute_signature(body, secret)
    for part in signature_header.split(","):
        scheme, _, provided = part.strip().partition("=")
        if scheme == _SIGNATURE_SCHEME and provided and hmac.compare_digest(provided, expected):
            return True
    return False


@dataclass(frozen=True)
class IncidentEvent:
    """The fields we pull out of a V3 `incident.triggered` webhook to drive the investigation."""

    event_type: str
    incident_id: str
    incident_number: int | None
    title: str
    service: str
    urgency: str
    status: str
    created_at: str
    html_url: str

    @property
    def is_triggered(self) -> bool:
        return self.event_type == "incident.triggered"


def parse_incident_event(payload: dict) -> IncidentEvent:
    """Extract an IncidentEvent from a PagerDuty V3 webhook payload.

    V3 shape: {"event": {"event_type": ..., "data": {<incident>}}}. Missing fields degrade to
    sensible defaults so a slightly-different payload still yields a usable investigation prompt.
    """
    event = payload.get("event", {}) or {}
    data = event.get("data", {}) or {}
    service = data.get("service", {}) or {}

    return IncidentEvent(
        event_type=event.get("event_type", ""),
        incident_id=data.get("id", ""),
        incident_number=data.get("incident_number"),
        title=data.get("title", "(no title)"),
        service=service.get("summary") or service.get("name") or "(unknown service)",
        urgency=data.get("urgency", "high"),
        status=data.get("status", "triggered"),
        created_at=data.get("created_at", ""),
        html_url=data.get("html_url", ""),
    )
