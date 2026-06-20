"""Webhook receiver: 202 on valid signature, 401 on bad, 400 on malformed, dedupe, async dispatch."""
import json
import time
from pathlib import Path

import pytest
from fastapi.testclient import TestClient

from src import webhook_server
from src.config import Settings
from src.pagerduty import compute_signature

SECRET = "whsec_test_secret"
FIXTURE = Path(__file__).resolve().parent / "fixtures" / "pagerduty_incident_v3.json"


@pytest.fixture
def client(monkeypatch, tmp_path):
    # Known secret + dry-run + an isolated, temporary dedupe DB so claims don't leak across tests
    # or pollute the repo. Stub the (expensive, network-bound) investigation.
    dedupe_db = str(tmp_path / "dedupe.sqlite3")
    monkeypatch.setattr(
        webhook_server, "get_settings",
        lambda: Settings(pagerduty_webhook_secret=SECRET, dry_run=True, investigation_dedupe_db=dedupe_db),
    )
    calls: list[str] = []

    async def fake_run(incident, settings):
        calls.append(incident.incident_id)
        return "stubbed report"

    monkeypatch.setattr(webhook_server, "run_investigation", fake_run)
    webhook_server._dispatcher = None
    webhook_server._deduper = None
    c = TestClient(webhook_server.app)
    c.calls = calls  # type: ignore[attr-defined]
    return c


def _signed(body: bytes) -> dict[str, str]:
    return {"X-PagerDuty-Signature": f"v1={compute_signature(body, SECRET)}",
            "Content-Type": "application/json"}


def _wait_until(predicate, timeout: float = 3.0) -> bool:
    """Investigations run on the dispatcher's background workers; poll for the side effect."""
    deadline = time.time() + timeout
    while time.time() < deadline:
        if predicate():
            return True
        time.sleep(0.02)
    return predicate()


def test_healthz(client):
    assert client.get("/healthz").json()["status"] == "ok"


def test_valid_signature_returns_202_and_investigates(client):
    body = FIXTURE.read_bytes()
    r = client.post("/webhook/pagerduty", content=body, headers=_signed(body))
    assert r.status_code == 202
    assert _wait_until(lambda: client.calls == ["PINCIDENT123"]), client.calls


def test_bad_signature_returns_401(client):
    body = FIXTURE.read_bytes()
    r = client.post("/webhook/pagerduty", content=body,
                    headers={"X-PagerDuty-Signature": "v1=deadbeef"})
    assert r.status_code == 401
    assert client.calls == []


def test_malformed_json_returns_400(client):
    body = b"{not valid json"
    r = client.post("/webhook/pagerduty", content=body, headers=_signed(body))
    assert r.status_code == 400
    assert client.calls == []


def test_non_triggered_event_is_ignored(client):
    payload = json.loads(FIXTURE.read_text())
    payload["event"]["event_type"] = "incident.resolved"
    body = json.dumps(payload).encode()
    r = client.post("/webhook/pagerduty", content=body, headers=_signed(body))
    assert r.status_code == 202
    assert client.calls == []  # resolved events don't kick off an investigation


def test_duplicate_incident_is_deduped(client):
    body = FIXTURE.read_bytes()
    # Pretend this incident was already claimed (same isolated DB the endpoint will use).
    deduper = webhook_server._get_deduper(webhook_server.get_settings())
    deduper.claim("PINCIDENT123")
    r = client.post("/webhook/pagerduty", content=body, headers=_signed(body))
    assert r.status_code == 202
    # Give any (incorrectly-dispatched) worker a chance, then confirm it never ran.
    time.sleep(0.1)
    assert client.calls == []


def test_health_reports_queue_stats_after_dispatch(client):
    body = FIXTURE.read_bytes()
    client.post("/webhook/pagerduty", content=body, headers=_signed(body))
    assert _wait_until(lambda: client.calls == ["PINCIDENT123"])
    queue = client.get("/healthz").json().get("queue")
    assert queue is not None and queue["processed"] >= 1
