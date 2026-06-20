"""Configuration for the SRE agent webhook service.

All values come from the environment (see .env.example). Loaded once and reused.
"""
from __future__ import annotations

from functools import lru_cache

from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    # Anthropic / agent — two-tier model split:
    #   orchestrator: synthesises findings from all subagents → needs deep reasoning → Opus
    #   subagents   : focused domain investigation (metrics/logs/traces/k8s/aws/deploy/scribe)
    #                 → structured tasks, shorter context → Sonnet is sufficient and cheaper
    # Changing subagent_model also requires updating the `model:` field in .claude/agents/*.md
    # (the Agent SDK reads model from frontmatter; there is no runtime override).
    anthropic_api_key: str = ""
    orchestrator_model: str = "claude-opus-4-8"
    subagent_model: str = "claude-sonnet-4-6"

    # Webhook server
    sre_agent_host: str = "0.0.0.0"
    sre_agent_port: int = 8080

    # When True, the agent investigates but the scribe logs the report instead of posting it.
    dry_run: bool = True

    # PagerDuty webhook signature verification (V3 subscriptions).
    pagerduty_webhook_secret: str = ""

    # Where the working directory / project root for the agent run lives (so it picks up
    # .claude/, AGENTS.md, CLAUDE.md, .mcp.json). Defaults to the repo root (cwd).
    project_root: str = "."

    # Slack channel for the stakeholder update (passed into the agent prompt).
    slack_incident_channel: str = "#incidents"

    # Investigation queue settings.
    investigation_queue_size: int = 50
    investigation_max_concurrency: int = 4
    investigation_timeout_seconds: float = 300.0
    investigation_dedupe_db: str = "./audit/incident_claims.sqlite3"

    # AWS Secrets Manager — OIDC/IRSA auth (no static keys). Empty = disabled (local dev).
    # Set SECRETS_MANAGER_PREFIX=sre-agent in production; see deploy/iam-permissions-policy.json.
    secrets_manager_prefix: str = ""
    aws_secrets_region: str = "us-east-1"


@lru_cache
def get_settings() -> Settings:
    return Settings()
