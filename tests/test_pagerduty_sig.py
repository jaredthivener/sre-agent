"""Signature verification: valid passes, tampered body fails."""
from src.pagerduty import compute_signature, parse_incident_event, verify_signature

SECRET = "whsec_test_secret"


def test_valid_signature_passes():
    body = b'{"event":{"event_type":"incident.triggered"}}'
    header = f"v1={compute_signature(body, SECRET)}"
    assert verify_signature(body, header, SECRET) is True


def test_tampered_body_fails():
    body = b'{"event":{"event_type":"incident.triggered"}}'
    header = f"v1={compute_signature(body, SECRET)}"
    tampered = body + b" "
    assert verify_signature(tampered, header, SECRET) is False


def test_wrong_secret_fails():
    body = b'{"x":1}'
    header = f"v1={compute_signature(body, 'other-secret')}"
    assert verify_signature(body, header, SECRET) is False


def test_missing_header_fails():
    assert verify_signature(b"{}", None, SECRET) is False


def test_multiple_signatures_any_match_passes():
    """PagerDuty may send several v1= signatures during secret rotation; any match is valid."""
    body = b'{"x":1}'
    good = compute_signature(body, SECRET)
    header = f"v1=deadbeef,v1={good}"
    assert verify_signature(body, header, SECRET) is True


def test_parse_incident_event_extracts_fields():
    payload = {
        "event": {
            "event_type": "incident.triggered",
            "data": {
                "id": "PABC",
                "incident_number": 7,
                "title": "boom",
                "urgency": "high",
                "status": "triggered",
                "created_at": "2026-06-20T14:30:00Z",
                "html_url": "https://x/incidents/PABC",
                "service": {"summary": "checkout-api"},
            },
        }
    }
    incident = parse_incident_event(payload)
    assert incident.incident_id == "PABC"
    assert incident.service == "checkout-api"
    assert incident.is_triggered is True
