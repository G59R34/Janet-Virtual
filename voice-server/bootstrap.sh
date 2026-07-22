#!/usr/bin/env bash
set -euo pipefail

if [[ "${EUID}" -eq 0 ]]; then
  echo "Run this as the normal Linux user, not root. It will request sudo when needed." >&2
  exit 1
fi

HOSTNAME_INPUT="${1:-}"
EMAIL_INPUT="${2:-}"
if [[ -z "${HOSTNAME_INPUT}" ]]; then
  read -r -p "Public voice hostname (for example voice.example.com): " HOSTNAME_INPUT
fi
if [[ -z "${EMAIL_INPUT}" ]]; then
  read -r -p "Email for TLS certificate notices: " EMAIL_INPUT
fi
if [[ -z "${HOSTNAME_INPUT}" || -z "${EMAIL_INPUT}" ]]; then
  echo "A hostname and email are required." >&2
  exit 1
fi

if ! command -v docker >/dev/null 2>&1; then
  echo "Installing Docker Engine and Compose plugin..."
  curl -fsSL https://get.docker.com -o /tmp/jva-get-docker.sh
  sudo sh /tmp/jva-get-docker.sh
  rm -f /tmp/jva-get-docker.sh
  sudo usermod -aG docker "$USER"
  echo "Docker was installed. Sign out and back in, then run this script again." >&2
  exit 0
fi

if ! docker compose version >/dev/null 2>&1; then
  echo "Docker Compose plugin is required." >&2
  exit 1
fi

if [[ ! -f .env ]]; then
  cp .env.example .env
  secret="$(openssl rand -base64 48 | tr -d '\n')"
  sed -i \
    -e "s|^LIVEKIT_API_SECRET=.*|LIVEKIT_API_SECRET=${secret}|" \
    -e "s|^JVA_VOICE_HOST=.*|JVA_VOICE_HOST=${HOSTNAME_INPUT}|" \
    -e "s|^JVA_VOICE_TLS_EMAIL=.*|JVA_VOICE_TLS_EMAIL=${EMAIL_INPUT}|" .env
fi

if [[ ! -f Caddyfile ]]; then
  cp Caddyfile.example Caddyfile
fi

# Apply the host firewall only when a common firewall manager is already in
# use. Router port-forwarding is still required for an internet-facing laptop.
if command -v ufw >/dev/null 2>&1 && sudo ufw status | grep -q "Status: active"; then
  sudo ufw allow 80/tcp
  sudo ufw allow 443/tcp
  sudo ufw allow 7881/tcp
  sudo ufw allow 50000:50100/udp
elif command -v firewall-cmd >/dev/null 2>&1 && sudo firewall-cmd --state >/dev/null 2>&1; then
  sudo firewall-cmd --permanent --add-service=http
  sudo firewall-cmd --permanent --add-service=https
  sudo firewall-cmd --permanent --add-port=7881/tcp
  sudo firewall-cmd --permanent --add-port=50000-50100/udp
  sudo firewall-cmd --reload
fi

docker compose pull
docker compose up -d
docker compose ps
echo
echo "JVA voice server started. Set the following values in the JVA WEB backend:"
grep -E '^(LIVEKIT_API_KEY|LIVEKIT_API_SECRET|JVA_VOICE_HOST)=' .env
echo "JVA_VOICE_URL=wss://${HOSTNAME_INPUT}"
echo "Confirm public DNS and router forwarding for TCP 80, 443, 7881 and UDP 50000-50100."
