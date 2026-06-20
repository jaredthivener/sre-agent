"""FastAPI receiver for PagerDuty V3 incident webhooks.

Verifies the HMAC signature, returns 202 immediately (PagerDuty expects a fast ACK), and routes the
investigation through a bounded, concurrency-limited, timeout-guarded queue. Deduplicates by
incident id (persisted in SQLite, so it survives restarts) and releases the claim on failure or
timeout so a redelivery can retry.
"""
from __future__ import annotations

import json
import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI, Header, Request, Response, status

from .agent_runner import run_investigation
from .config import Settings, get_settings
from .investigation_queue import IncidentDeduper, InvestigationDispatcher
from .pagerduty import parse_incident_event, verify_signature
from .secrets_loader import bootstrap_secrets

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger("sre_agent.webhook")

_dispatcher: InvestigationDispatcher | None = None
_deduper: IncidentDeduper | None = None


def _get_deduper(settings: Settings) -> IncidentDeduper:
    global _deduper
    if _deduper is None:
        _deduper = IncidentDeduper(settings.investigation_dedupe_db)
    return _deduper


def _get_dispatcher(settings: Settings) -> InvestigationDispatcher:
    global _dispatcher
    if _dispatcher is None:
        deduper = _get_deduper(settings)

        async def handler(incident) -> None:
            # Completion bookkeeping lives here (not in the endpoint) so it runs for every outcome.
            # try/finally also runs under cancellation, so a worker timeout still releases the claim.
            succeeded = False
            try:
                await run_investigation(incident, settings)
                succeeded = True
            finally:
                if succeeded:
                    # Investigated once — don't re-investigate the same incident on redelivery.
                    deduper.mark_complete(incident.incident_id)
                else:
                    # Failed or timed out — release so a PagerDuty redelivery can retry.
                    deduper.release(incident.incident_id)
                    logger.error("Investigation did not complete for incident %s; claim released",
                                 incident.incident_id)

        _dispatcher = InvestigationDispatcher(
            max_queue_size=settings.investigation_queue_size,
            max_concurrency=settings.investigation_max_concurrency,
            timeout_seconds=settings.investigation_timeout_seconds,
            handler=handler,
        )
    return _dispatcher


@asynccontextmanager
async def lifespan(app: FastAPI):
    # Load secrets from AWS Secrets Manager (OIDC/IRSA) before pydantic-settings builds
    # the Settings object. No-ops when SECRETS_MANAGER_PREFIX is unset (local dev / tests).
    bootstrap_secrets()
    get_settings.cache_clear()  # ensure Settings is constructed with Secrets Manager values
    settings = get_settings()
    if not settings.pagerduty_webhook_secret:
        logger.warning("PAGERDUTY_WEBHOOK_SECRET is empty — every webhook will be rejected (401). "
                       "Set it to the PagerDuty V3 subscription signing secret.")
    if not settings.dry_run:
        logger.warning("DRY_RUN is OFF — the agent will post results to PagerDuty/Slack for real.")
    yield
    # Graceful shutdown: drain in-flight workers.
    if _dispatcher is not None:
        await _dispatcher.stop()


app = FastAPI(title="Autonomous SRE Agent", version="0.1.0", lifespan=lifespan)


@app.get("/healthz")
async def healthz() -> dict[str, object]:
    """Liveness + readiness: reports queue depth and lifetime counters when the queue is live."""
    body: dict[str, object] = {"status": "ok"}
    if _dispatcher is not None:
        body["queue"] = _dispatcher.stats()
    return body


@app.post("/webhook/pagerduty")
async def pagerduty_webhook(
    request: Request,
    x_pagerduty_signature: str | None = Header(default=None),
) -> Response:
    settings = get_settings()
    body = await request.body()

    if not verify_signature(body, x_pagerduty_signature, settings.pagerduty_webhook_secret):
        logger.warning("Rejected PagerDuty webhook: invalid signature")
        return Response(status_code=status.HTTP_401_UNAUTHORIZED)

    try:
        payload = json.loads(body)
    except (json.JSONDecodeError, ValueError):
        logger.warning("Rejected PagerDuty webhook: malformed JSON body")
        return Response(status_code=status.HTTP_400_BAD_REQUEST)
    if not isinstance(payload, dict):
        logger.warning("Rejected PagerDuty webhook: JSON body is not an object")
        return Response(status_code=status.HTTP_400_BAD_REQUEST)

    incident = parse_incident_event(payload)

    # We only act on newly-triggered incidents.
    if not incident.is_triggered:
        logger.info("Ignoring event %s for %s (not incident.triggered)",
                    incident.event_type, incident.incident_id)
        return Response(status_code=status.HTTP_202_ACCEPTED)

    deduper = _get_deduper(settings)
    if not deduper.claim(incident.incident_id):
        logger.info("Deduped: incident %s already seen", incident.incident_id)
        return Response(status_code=status.HTTP_202_ACCEPTED)

    dispatcher = _get_dispatcher(settings)
    if not await dispatcher.enqueue(incident):
        deduper.release(incident.incident_id)  # undo the claim so it can be retried
        logger.warning("Rejected incident %s (%s): investigation queue is full",
                       incident.incident_id, incident.service)
        return Response(status_code=status.HTTP_429_TOO_MANY_REQUESTS)

    logger.info("Accepted incident %s (%s); investigating asynchronously",
                incident.incident_id, incident.service)
    return Response(status_code=status.HTTP_202_ACCEPTED)


def main() -> None:
    import uvicorn

    settings = get_settings()
    uvicorn.run(app, host=settings.sre_agent_host, port=settings.sre_agent_port)


if __name__ == "__main__":
    main()
