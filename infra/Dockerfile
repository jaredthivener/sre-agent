# syntax=docker/dockerfile:1.7
# Single-platform build (linux/arm64 — Apple Silicon / ECS Graviton).
# For multi-arch CI, pass --build-arg TARGETARCH=amd64 and override the Go stage.
ARG TARGETARCH=arm64
ARG TARGETOS=linux

# ── Stage 1: Python 3.13 dependency builder ──────────────────────────────────
# Use wolfi-base (runs as root) so packages install to /install without
# permission errors, and to match the python-3.13 runtime in Stage 3.
FROM cgr.dev/chainguard/wolfi-base AS python-builder

RUN apk add --no-cache python-3.13 py3-pip build-base python-3.13-dev

WORKDIR /build
COPY pyproject.toml README.md ./
COPY src ./src

RUN pip install --no-cache-dir --prefix=/install ".[aws,otel]"

# ── Stage 2: mcp-grafana binary ───────────────────────────────────────────────
FROM cgr.dev/chainguard/go:latest AS grafana-mcp-builder

ARG TARGETARCH
ARG TARGETOS

# Binary goes to /root/go/bin/<goos>_<goarch>/mcp-grafana on cross-compile;
# native builds land at /root/go/bin/mcp-grafana. find covers both.
RUN GOOS=${TARGETOS} GOARCH=${TARGETARCH} \
    go install github.com/grafana/mcp-grafana/cmd/mcp-grafana@latest \
 && find /root/go/bin -name "mcp-grafana" -exec mv {} /mcp-grafana \;

# ── Stage 3: Zero-CVE runtime (Wolfi/Chainguard — daily CVE sweeps) ───────────
FROM cgr.dev/chainguard/wolfi-base

RUN apk add --no-cache \
    python-3.13 \
    nodejs-22 \
    npm \
    git \
    uv \
 && mkdir /tmp/undici-fix \
 && cd /tmp/undici-fix \
 && npm install undici@^6.27.0 --no-fund --no-audit \
 && U=/tmp/undici-fix/node_modules/undici \
 && rm -rf /usr/lib/node_modules/npm/node_modules/undici \
    /usr/lib/node_modules/node-gyp/node_modules/undici \
 && cp -r $U /usr/lib/node_modules/npm/node_modules/undici \
 && cp -r $U /usr/lib/node_modules/node-gyp/node_modules/undici \
 && rm -rf /tmp/undici-fix \
 && adduser -D -u 10001 -g sre sre

# Python packages — system-owned, matches python-3.13 in the runtime
COPY --from=python-builder /install /usr/local

# mcp-grafana binary
COPY --from=grafana-mcp-builder /mcp-grafana /usr/local/bin/mcp-grafana

# ── NOTE: GitHub MCP server ───────────────────────────────────────────────────
# .mcp.json currently uses: docker run ghcr.io/github/github-mcp-server
# Docker-in-Docker is unavailable in ECS Fargate. Update .mcp.json before
# production to: "command": "npx", "args": ["-y", "@github/github-mcp-server"]

WORKDIR /app

# --chown at copy-time avoids a separate chown layer and its wasted bytes.
COPY --chown=sre:sre pyproject.toml README.md ./
COPY --chown=sre:sre src ./src
COPY --chown=sre:sre AGENTS.md CLAUDE.md .mcp.json ./
COPY --chown=sre:sre .claude ./.claude

USER sre

ENV PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    DRY_RUN=1

CMD ["python", "-m", "src.sqs_consumer"]
