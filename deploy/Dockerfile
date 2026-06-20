# Autonomous SRE Agent — webhook receiver + Claude Agent SDK runner.
FROM python:3.14-slim

# The agent shells out to read-only CLIs during investigation. Install the clients it needs.
# (Node + uv are needed for the npx/uvx-based MCP servers in .mcp.json.)
RUN apt-get update && apt-get install -y --no-install-recommends \
        git curl ca-certificates gnupg \
    && curl -fsSL https://deb.nodesource.com/setup_20.x | bash - \
    && apt-get install -y --no-install-recommends nodejs \
    && pip install --no-cache-dir uv \
    && rm -rf /var/lib/apt/lists/*

# kubectl (read-only use) and the AWS CLI are expected to be provided via the base image or a
# sidecar in your environment; add them here if you bake them in.

WORKDIR /app

COPY pyproject.toml README.md ./
COPY src ./src
COPY AGENTS.md CLAUDE.md .mcp.json ./
COPY .claude ./.claude

RUN pip install --no-cache-dir .

# Run as non-root.
RUN useradd --create-home --uid 10001 sre && chown -R sre:sre /app
USER sre

EXPOSE 8080
ENV SRE_AGENT_HOST=0.0.0.0 SRE_AGENT_PORT=8080 DRY_RUN=1

CMD ["python", "-m", "src.webhook_server"]
