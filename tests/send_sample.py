"""Post the sample incident fixture to a locally-running webhook server with a valid signature.

Usage:
    PAGERDUTY_WEBHOOK_SECRET=whsec_test_secret python -m tests.send_sample
    # optional: SRE_AGENT_URL=http://localhost:8080
"""
import os
import sys
from pathlib import Path

import httpx

from src.pagerduty import compute_signature

FIXTURE = Path(__file__).resolve().parent / "fixtures" / "pagerduty_incident_v3.json"


def main() -> int:
    secret = os.environ.get("PAGERDUTY_WEBHOOK_SECRET")
    if not secret:
        print("Set PAGERDUTY_WEBHOOK_SECRET to the value the server is configured with.")
        return 2

    url = os.environ.get("SRE_AGENT_URL", "http://localhost:8080") + "/webhook/pagerduty"
    body = FIXTURE.read_bytes()
    headers = {
        "X-PagerDuty-Signature": f"v1={compute_signature(body, secret)}",
        "Content-Type": "application/json",
    }
    resp = httpx.post(url, content=body, headers=headers, timeout=10.0)
    print(f"POST {url} -> {resp.status_code}")
    return 0 if resp.status_code == 202 else 1


if __name__ == "__main__":
    sys.exit(main())
