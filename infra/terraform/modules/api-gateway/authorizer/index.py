"""
Lambda authorizer for the PagerDuty webhook.

Validates X-PagerDuty-Signature using HMAC-SHA256 (V3 webhook signing).
Returns an IAM policy allowing or denying the API Gateway invocation.
The signing secret is fetched from Secrets Manager on first invocation and
cached in the Lambda execution environment for the lifetime of the container.
"""
from __future__ import annotations

import hashlib
import hmac
import json
import logging
import os
from functools import lru_cache

import boto3

logger = logging.getLogger()
logger.setLevel(logging.INFO)

SECRET_ARN = os.environ["WEBHOOK_SECRET_ARN"]


@lru_cache(maxsize=1)
def _get_signing_secret() -> str:
    client = boto3.client("secretsmanager", region_name=os.environ.get("AWS_REGION", "us-east-1"))
    response = client.get_secret_value(SecretId=SECRET_ARN)
    return response["SecretString"]


def _verify_signature(body: str, signature_header: str, secret: str) -> bool:
    """PagerDuty V3: X-PagerDuty-Signature: v1=<hex>"""
    if not signature_header:
        return False
    expected = "v1=" + hmac.new(
        secret.encode(), body.encode(), hashlib.sha256
    ).hexdigest()
    for part in signature_header.split(","):
        if hmac.compare_digest(part.strip(), expected):
            return True
    return False


def _policy(effect: str, method_arn: str) -> dict:
    return {
        "principalId": "pagerduty-webhook",
        "policyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Action": "execute-api:Invoke",
                    "Effect": effect,
                    "Resource": method_arn,
                }
            ],
        },
    }


def handler(event: dict, context) -> dict:
    try:
        secret = _get_signing_secret()
    except Exception:
        logger.exception("Failed to fetch webhook signing secret")
        raise Exception("Unauthorized")

    body = event.get("body") or ""
    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    sig = headers.get("x-pagerduty-signature", "")

    if _verify_signature(body, sig, secret):
        logger.info("Webhook signature valid")
        return _policy("Allow", event["methodArn"])

    logger.warning("Webhook signature invalid or missing")
    return _policy("Deny", event["methodArn"])
