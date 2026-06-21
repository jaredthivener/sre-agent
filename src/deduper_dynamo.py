"""DynamoDB-backed incident deduplication for the SQS consumer.

Replaces the SQLite-backed deduper (investigation_queue.py) for production
deployments where multiple Fargate tasks may run simultaneously.

Schema (single table):
  PK: incident_id (String)
  status: "claimed" | "complete"
  claimed_at: ISO-8601 timestamp
  ttl: epoch seconds (auto-deleted after 24h by DynamoDB TTL)

The `claim` / `release` / `mark_complete` contract:
  - claim()        → True if this process now owns the incident, False if duplicate
  - release()      → removes the claim (called on investigation failure so it retries)
  - mark_complete() → sets status=complete so retries are blocked
"""
from __future__ import annotations

import logging
import time
from datetime import datetime, timezone

import boto3
from botocore.exceptions import ClientError

logger = logging.getLogger("sre_agent.deduper_dynamo")

_TTL_SECONDS = 86400  # 24h — stale claims auto-expire even if release() is missed


class DynamoDeduper:
    def __init__(self, table_name: str, region: str = "us-east-1") -> None:
        self._table_name = table_name
        self._client = boto3.client("dynamodb", region_name=region)

    def claim(self, incident_id: str) -> bool:
        """Atomically claim an incident. Returns True if this caller won the race."""
        try:
            self._client.put_item(
                TableName=self._table_name,
                Item={
                    "incident_id": {"S": incident_id},
                    "status": {"S": "claimed"},
                    "claimed_at": {"S": datetime.now(timezone.utc).isoformat()},
                    "ttl": {"N": str(int(time.time()) + _TTL_SECONDS)},
                },
                # Atomic conditional write — succeeds only if no item exists yet
                ConditionExpression="attribute_not_exists(incident_id)",
            )
            logger.info("Claimed incident %s", incident_id)
            return True
        except ClientError as e:
            if e.response["Error"]["Code"] == "ConditionalCheckFailedException":
                logger.info("Incident %s already claimed or complete — skipping", incident_id)
                return False
            raise

    def release(self, incident_id: str) -> None:
        """Release a claim so the incident can be retried (call on investigation failure)."""
        try:
            self._client.delete_item(
                TableName=self._table_name,
                Key={"incident_id": {"S": incident_id}},
                ConditionExpression="attribute_exists(incident_id)",
            )
            logger.info("Released claim on incident %s", incident_id)
        except ClientError as e:
            if e.response["Error"]["Code"] != "ConditionalCheckFailedException":
                raise

    def mark_complete(self, incident_id: str) -> None:
        """Mark an incident as complete so future duplicate messages are silently discarded."""
        self._client.update_item(
            TableName=self._table_name,
            Key={"incident_id": {"S": incident_id}},
            UpdateExpression="SET #s = :complete",
            ExpressionAttributeNames={"#s": "status"},
            ExpressionAttributeValues={":complete": {"S": "complete"}},
        )
        logger.info("Marked incident %s complete", incident_id)
