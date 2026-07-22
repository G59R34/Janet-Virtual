# Local setup

## Prerequisites

- Node.js 20 LTS or newer compatible with Next.js 16
- npm (the repository commits `package-lock.json`)
- Docker Desktop or another Docker-compatible runtime for local Supabase
- Supabase CLI, invoked with `npx supabase`
- Git

## Web UI only

The current UI scaffold does not yet call Supabase.

```bash
npm ci
npm run dev
```

Open `http://localhost:3000`. Before submitting changes, run:

```bash
npm run lint
npm run build
```

The package currently has no `test` script despite test libraries being installed.

## Full local stack

1. Copy `.env.example` to `.env.local`. Never commit `.env.local`.
2. Initialize Supabase only if `supabase/config.toml` does not exist:

   ```bash
   npx supabase init
   ```

3. Start local services:

   ```bash
   npx supabase start
   ```

4. Copy the local API URL, publishable/anon key, service-role key, database URL, and Studio URL printed by the CLI into `.env.local`. Keep local values local.
5. Apply all migrations and seed data:

   ```bash
   npx supabase db reset
   ```

6. Start Next.js in a second terminal:

   ```bash
   npm run dev
   ```

`supabase/migrations/` is currently empty, so reset creates no JVA schema until migrations are added.

## Expected local endpoints

Supabase CLI defaults are usually:

- API: `http://127.0.0.1:54321`
- Database: `postgresql://postgres:postgres@127.0.0.1:54322/postgres`
- Studio: `http://127.0.0.1:54323`
- Inbucket: `http://127.0.0.1:54324`

Treat CLI output as authoritative because ports may be changed in `supabase/config.toml`.

## Environment handling

- `NEXT_PUBLIC_*` values are embedded into browser bundles. They are identifiers/public credentials, not secrets.
- `SUPABASE_SERVICE_ROLE_KEY`, database URLs, ACARS secrets, and cron secrets are server-only.
- In local development, use local Supabase credentials—not staging or production credentials.
- Restart `next dev` after changing environment variables.
- Do not place real values in screenshots, issues, fixture files, or logs.

## Development workflow

1. Create a migration for schema or policy changes.
2. Reset local Supabase from scratch.
3. Add SQL policy/constraint tests when the database test harness is introduced.
4. Implement server-side access with the user's Auth context.
5. Exercise at least one allowed and one denied path for every role affected.
6. Run lint and production build.

## Troubleshooting

### Local Supabase does not start

Confirm Docker is running, then inspect:

```bash
npx supabase status
```

Stop stale local containers with `npx supabase stop`, then start again. Avoid deleting volumes unless a reset is intended.

### Auth redirect or cookie failure

Confirm `NEXT_PUBLIC_SITE_URL` is `http://localhost:3000`, local Auth redirect URLs include the callback route implemented by the app, and server-side Supabase code writes refreshed cookies through the supported Next.js 16 request lifecycle.

### Database state differs between developers

Do not repair local state manually. Commit the missing migration and run `npx supabase db reset`. A clean reset is the reproducibility test.

### Browser access works but server access fails

Verify the server runtime receives `NEXT_PUBLIC_SUPABASE_URL` and a public key. Use the service role only where the operation explicitly requires bypassing RLS; do not use it as a general fix.
