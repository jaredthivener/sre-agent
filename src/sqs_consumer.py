"""SQS long-poll consumer — production entrypoint replacing asyncio.Queue.

In production the Fargate task runs this loop instead of webhook_server.py.
It polls the SQS queue, claims each message via DynamoDB dedup, runs one
investigation per message, then deletes the message on success (or leaves it
for the visibility timeout to expire so it retries and eventually hits the DLQ).

Start via:
    python -m src.sqs_consumer
or as the Dockerfile CMD when SQS_QUEUE_URL is set.
"""
from __future__ import annotations

import asyncio
import json
import logging
import os
import signal
import sys

import boto3

from .agent_runner import run_investigation
from .config import get_settings
from .deduper_dynamo import DynamoDeduper
from .pagerduty import IncidentEvent
from .secrets_loader import bootstrap_secrets

logger = logging.getLogger("sre_agent.sqs_consumer")


def _parse_incident(body: str) -> IncidentEvent | None:
    try:
        payload = json.loads(body)
        # PagerDuty V3 webhook wraps the event under event.data
        event_data = payload.get("event", payload)
        data = event_data.get("data", event_data)
        return IncidentEvent(
            incident_id=data.get("id", "unknown"),
            incident_number=data.get("incident_number", 0),
            title=data.get("title", ""),
            service=data.get("service", {}).get("summary", "unknown"),
            urgency=data.get("urgency", "high"),
            triggered_at=data.get("created_at", ""),
            html_url=data.get("html_url", ""),
            details=data.get("body", {}).get("details", ""),
        )
    except Exception:
        logger.exception("Failed to parse SQS message body as PagerDuty incident")
        return None


async def _handle_message(message: dict, deduper: DynamoDeduper, settings) -> None:
    body = message.get("Body", "")
    receipt_handle = message["ReceiptHandle"]
    incident = _parse_incident(body)

    if incident is None:
        logger.error("Unparseable message — sending to DLQ via max-receive exhaustion: %s", body[:200])
        return

    if not deduper.claim(incident.incident_id):
        logger.info("Duplicate incident %s — deleting message", incident.incident_id)
        _delete_message(receipt_handle, settings)
        return

    try:
        logger.info("Investigating incident %s (%s)", incident.incident_id, incident.service)
        await run_investigation(incident, settings)
        deduper.mark_complete(incident.incident_id)
        _delete_message(receipt_handle, settings)
        logger.info("Investigation complete for %s", incident.incident_id)
    except Exception:
        logger.exception("Investigation failed for %s — leaving for retry/DLQ", incident.incident_id)
        deduper.release(incident.incident_id)


def _delete_message(receipt_handle: str, settings) -> None:
    sqs = boto3.client("sqs", region_name=settings.aws_region)
    sqs.delete_message(QueueUrl=settings.sqs_queue_url, ReceiptHandle=receipt_handle)


async def consume(settings, deduper: DynamoDeduper) -> None:
    sqs = boto3.client("sqs", region_name=settings.aws_region)
    logger.info("SQS consumer started — polling %s", settings.sqs_queue_url)

    running = True

    def _stop(sig, frame):
        nonlocal running
        logger.info("Received signal %s — draining and stopping", sig)
        running = False

    signal.signal(signal.SIGTERM, _stop)
    signal.signal(signal.SIGINT, _stop)

    while running:
        response = sqs.receive_message(
            QueueUrl=settings.sqs_queue_url,
            MaxNumberOfMessages=1,       # one investigation at a time per task
            WaitTimeSeconds=20,          # long poll — reduces empty-receive API cost
            VisibilityTimeout=settings.investigation_timeout_seconds,
            AttributeNames=["All"],
            MessageAttributeNames=["All"],
        )

        messages = response.get("Messages", [])
        if not messages:
            continue

        await _handle_message(messages[0], deduper, settings)


def main() -> None:
    logging.basicConfig(
        level=logging.INFO,
        format="%(asctime)s %(levelname)s %(name)s %(message)s",
        stream=sys.stdout,
    )

    bootstrap_secrets()
    get_settings.cache_clear()
    settings = get_settings()

    if not settings.sqs_queue_url:
        logger.error("SQS_QUEUE_URL is not set — cannot start consumer")
        sys.exit(1)

    deduper = DynamoDeduper(
        table_name=settings.dynamo_dedup_table,
        region=settings.aws_region,
    )

    asyncio.run(consume(settings, deduper))


if __name__ == "__main__":
    main()
