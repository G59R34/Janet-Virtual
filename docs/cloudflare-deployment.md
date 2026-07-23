# Cloudflare deployment

This is a full-stack Next.js application. It must be deployed as a Cloudflare
Worker via OpenNext, not as a static Pages export, because its authenticated
route handlers issue voice tokens and access Supabase server credentials.

## Middleware compatibility

The JCars CORS and Supabase session-refresh logic uses the legacy
`src/middleware.ts` convention because Cloudflare OpenNext supports Edge
middleware, while Next.js 16's newer Node-only `proxy.ts` convention is not
currently supported. Next.js emits a deprecation warning during the build; the
Cloudflare Worker bundle remains valid.

Cloudflare presents Workers and Pages from the same **Workers & Pages** area of
the dashboard. Create a Worker named `janet-virtual-airlines` or change the
`name` in `wrangler.jsonc` before the first deploy.

## Required dashboard secrets

In **Workers & Pages → janet-virtual-airlines → Settings → Variables and
Secrets**, add these as encrypted secrets:

- `SUPABASE_SERVICE_ROLE_KEY`
- `JVA_VOICE_API_SECRET`

Add these as normal text variables:

- `NEXT_PUBLIC_SITE_URL` — your final `https://` website URL
- `NEXT_PUBLIC_SUPABASE_URL`
- `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY`
- `NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN`
- `JVA_VOICE_URL` — the `wss://` URL for your self-hosted JVA voice server
- `JVA_VOICE_API_KEY`

The `NEXT_PUBLIC_*` values are intentionally visible to browsers. Never put a
Supabase service-role key or LiveKit API secret in one of them.

## Deploy from this computer

```bash
npm run deploy
```

The first command opens Cloudflare authentication if necessary. It builds the
OpenNext Worker and deploys it. To run the production-compatible local preview:

```bash
npm run preview
```

## Git-based deployment

Connect the repository under **Workers & Pages** and use `npm run deploy` as
the deploy command. Set the same variables and secrets listed above in the
project's build/deployment settings.
