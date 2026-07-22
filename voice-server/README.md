# JVA central voice server

This folder deploys the single JVA voice server that will replace the
controller-hosted voice path. It runs an audio SFU (LiveKit) on the Linux
laptop. JCars and JScope connect to this one service; the web backend will
later issue short-lived room tokens and remains the authority for who may use
each tactical frequency.

## What the laptop needs

- Linux with Docker Engine and the Docker Compose plugin.
- A DNS name and trusted TLS certificate for off-LAN clients. The signaling
  endpoint must be `wss://` in production; browsers will not accept a
  self-signed certificate.
- Firewall/router rules for TCP `443` (when using Caddy), TCP `7881`, and UDP
  `50000-50100` to the laptop. TURN is intentionally disabled.

The compose file uses host networking because WebRTC media works best when the
server directly owns its UDP ports. It is Linux-only by design.

The LiveKit configuration is passed through Docker Compose's `LIVEKIT_CONFIG`
environment variable. This lets Docker inject the key and secret from the
ignored `.env` file without ever copying real credentials into a tracked YAML
file.

## One-command Linux bring-up

Before starting, point the public DNS record for your hostname at the laptop's
public IP and forward the required ports from the router. Then copy this entire
folder to the laptop and run:

```bash
chmod +x bootstrap.sh verify-voice-server.sh
./bootstrap.sh voice.example.com admin@example.com
```

The script installs Docker if necessary (then asks you to sign out/in once),
generates the API secret, creates `.env` and `Caddyfile`, configures an active
UFW/firewalld host firewall, pulls the images, and starts Caddy plus LiveKit.
Caddy obtains and renews the trusted TLS certificate automatically.

## Manual bring-up

1. Copy this directory to the laptop.
2. Run `cp .env.example .env` and replace the API secret with
   `openssl rand -base64 48`.
3. Set `JVA_VOICE_HOST` to the laptop's public DNS name. Leave
   `LIVEKIT_USE_EXTERNAL_IP=true` when the laptop is behind NAT; use `false`
   only for a LAN-only test where the host IP is directly reachable.
4. Copy `Caddyfile.example` to `Caddyfile`. The DNS record must already point
   to the laptop so Caddy can obtain a trusted certificate.
5. Run `chmod +x verify-voice-server.sh && ./verify-voice-server.sh`.
6. From this directory run `docker compose up -d` and verify with
   `docker compose logs -f livekit`.

## Backend settings to add after the server exists

Set these only in the JVA web application's secret environment, never in a
browser or desktop-client configuration:

```env
JVA_VOICE_MODE=central
JVA_VOICE_URL=wss://voice.example.com
JVA_VOICE_API_KEY=JVA_voice_2026
JVA_VOICE_API_SECRET=<the same value as the laptop .env>
```

The API secret signs time-limited participant tokens. It must stay only on the
Linux service and the server-side JVA backend.

## Connectivity model

```
JCars / JScope -- authenticated token --> JVA backend
JCars / JScope -- WSS + WebRTC media --> Linux JVA voice server
```

There is no controller-hosted UDP socket and no public credential embedded in
either client. Without TURN, a restrictive client network may be unable to
join; that is an expected limitation of the requested direct-only policy.
