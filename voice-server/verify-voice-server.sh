#!/usr/bin/env bash
set -euo pipefail

if [[ ! -f .env ]]; then
  echo "Missing .env. Copy .env.example to .env and set the API secret." >&2
  exit 1
fi

# shellcheck disable=SC1091
source .env

for required in LIVEKIT_API_KEY LIVEKIT_API_SECRET JVA_VOICE_HOST JVA_VOICE_TLS_EMAIL LIVEKIT_USE_EXTERNAL_IP; do
  if [[ -z "${!required:-}" || "${!required}" == REPLACE_* ]]; then
    echo "Missing or placeholder value: ${required}" >&2
    exit 1
  fi
done

if ! command -v docker >/dev/null 2>&1; then
  echo "Docker Engine with Docker Compose is required." >&2
  exit 1
fi

docker compose config >/dev/null
echo "JVA voice server configuration is valid."
echo "Expected public signaling endpoint: wss://${JVA_VOICE_HOST}"
echo "Open TCP 443 (with Caddy), TCP 7881, and UDP 50000-50100."
