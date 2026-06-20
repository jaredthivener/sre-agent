"""Bootstrap: fetch read-only tokens from AWS Secrets Manager into os.environ.

Call bootstrap_secrets() once at startup (before get_settings() and before MCP servers are
spawned). In production the agent has no static AWS credentials — it uses OIDC-derived temporary
credentials (IRSA on EKS, ECS task role, EC2 instance profile) that boto3 picks up automatically
via the default credential chain.

In local development, set SECRETS_MANAGER_PREFIX="" (or omit it) and supply tokens directly as
environment variables — the loader skips gracefully when the prefix is empty or boto3 is absent.
"""
from __future__ import annotations

import json
import logging
import os

logger = logging.getLogger("sre_agent.secrets")

# Maps env var name → Secrets Manager secret name (relative to the configured prefix).
# Plain-string secrets (the token itself) and single-key JSON objects are both supported.
_SECRET_MAP: dict[str, str] = {
    "ANTHROPIC_API_KEY": "anthropic-api-key",
    "PAGERDUTY_API_TOKEN": "pagerduty-api-token",
    "PAGERDUTY_WEBHOOK_SECRET": "pagerduty-webhook-secret",
    "GRAFANA_SERVICE_ACCOUNT_TOKEN": "grafana-service-account-token",
    "GITHUB_TOKEN": "github-token",
    "SLACK_BOT_TOKEN": "slack-bot-token",
}


def load_secrets(prefix: str, region: str) -> None:
    """Fetch secrets from Secrets Manager and inject into os.environ.

    Env vars already set in the environment are left alone (local-dev override wins).
    Missing secrets are logged as warnings but never raise — startup must not fail because
    a non-critical secret (e.g. Slack) is absent.
    """
    try:
        import boto3
        import botocore.exceptions
    except ImportError:
        logger.info("boto3 not installed; skipping Secrets Manager (local dev mode)")
        return

    client = boto3.client("secretsmanager", region_name=region)
    prefix = prefix.rstrip("/")
    loaded, missing = 0, []

    for env_var, secret_suffix in _SECRET_MAP.items():
        if os.environ.get(env_var):
            logger.debug("Skipping %s — already present in environment", env_var)
            continue

        secret_id = f"{prefix}/{secret_suffix}"
        try:
            resp = client.get_secret_value(SecretId=secret_id)
            raw = resp.get("SecretString", "")
            # Support both plain-string secrets and single-key JSON objects
            # e.g. {"token": "glsa_..."} or just "glsa_..."
            try:
                parsed = json.loads(raw)
                if isinstance(parsed, dict) and len(parsed) == 1:
                    raw = next(iter(parsed.values()))
            except (json.JSONDecodeError, StopIteration):
                pass
            os.environ[env_var] = raw
            loaded += 1
        except botocore.exceptions.ClientError as exc:
            code = exc.response["Error"]["Code"]
            if code in ("ResourceNotFoundException", "SecretNotFoundException"):
                logger.warning("Secret not found: %s — %s will be empty", secret_id, env_var)
            else:
                logger.exception("Failed to fetch secret %s", secret_id)
            missing.append(secret_id)
        except Exception:
            logger.exception("Unexpected error fetching secret %s", secret_id)
            missing.append(secret_id)

    logger.info(
        "Secrets Manager: loaded %d/%d secrets (prefix=%s, region=%s)",
        loaded, len(_SECRET_MAP), prefix, region,
    )
    if missing:
        logger.warning("Missing/failed secrets: %s", missing)


def bootstrap_secrets() -> None:
    """Read SECRETS_MANAGER_PREFIX from os.environ and call load_secrets if set.

    Call this before get_settings() so pydantic-settings sees the Secrets Manager values.
    No-ops when SECRETS_MANAGER_PREFIX is empty (local dev / test).
    """
    prefix = os.environ.get("SECRETS_MANAGER_PREFIX", "").strip()
    if not prefix:
        return
    region = os.environ.get("AWS_SECRETS_REGION", "us-east-1")
    load_secrets(prefix, region)
