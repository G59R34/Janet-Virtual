# Deployment guide

## Supported topology

Recommended production topology:

- Next.js 16 App Router deployed on Vercel or a Node.js 20+ compatible platform.
- Supabase hosted PostgreSQL/Auth/Storage in a nearby region.
- Protected CI environment for migrations.
- External observability and alerting configured with redaction.

Preview, staging, and production must use separate credentials and non-production deployments must not connect to production Supabase.

## Required environment variables

Configure values represented in `.env.example` in the deployment platform. At minimum the application will require public Supabase URL/publishable key and the canonical site URL. Configure the service role only for workloads that need it, ACARS/cron secrets only when enabled, and database URLs only in migration/backup jobs.

Environment variables prefixed `NEXT_PUBLIC_` are compiled into browser assets. Never use that prefix for a secret.

## Pre-production preparation

1. Configure canonical HTTPS domain and DNS.
2. Configure Supabase Auth Site URL and exact redirect allow-list.
3. Configure custom SMTP and verify SPF, DKIM, and DMARC.
4. Apply migrations to staging and run RLS/API/import tests.
5. Confirm Storage buckets and policies are private by default.
6. Set resource budgets, rate limits, log retention, and alerts.
7. Verify backups and complete a restore drill.
8. Ensure legal/public copy never implies real-world affiliation.

## CI pipeline

A protected pipeline should run:

```bash
npm ci
npm run lint
npm run build
```

Add unit, integration, RLS, and end-to-end commands when scripts are introduced. CI should fail on any gate. Do not run untrusted pull-request code with production secrets. Use immutable builds and lockfile installs. Enable dependency review, secret scanning, branch protection, and approvals for production deployment/migrations.

## Release procedure

1. Announce the release window for user-impacting changes.
2. Confirm backup/PITR health and record the recovery point.
3. Review migration dry-run and application/schema compatibility.
4. Apply backward-compatible database migrations.
5. Deploy the Next.js build with production environment variables.
6. Smoke test public/legal pages, sign-in/out, allowed and denied protected access, profile, operational board, and changed ACARS/import paths.
7. Monitor HTTP errors, latency, Auth failures, database load, RLS denials, Realtime connections, and jobs.
8. Record migration versions and manual actions in release notes.

## Vercel notes

- Select the repository root containing the top-level `package.json` (`JVA` in this workspace).
- Use `npm run build` and framework-detected Next.js output.
- Scope variables independently to Preview and Production.
- Pin a project-compatible Node.js major.
- Protect logs and never print environment values.
- Place functions near Supabase where platform support permits.
- Add a stable health endpoint before uptime checks depend on it.

## Self-hosted Node notes

```bash
npm ci
npm run build
npm run start
```

Terminate TLS at a maintained proxy/load balancer, set forwarded headers correctly, run as non-root, impose resource limits, and use rolling replacement. Do not use a shared writable application filesystem; store durable objects in Supabase Storage.

## Rollback

- **Application-only:** route traffic to the previous immutable build if schema-compatible.
- **Additive migration:** deploy a compensating migration, then redeploy.
- **Destructive/data issue:** stop writers, declare an incident, and follow [Backup and restore](backup-restore.md).
- **Secret exposure:** revoke/rotate first, update consumers, redeploy, and review logs.

Never reverse a shared migration by editing its SQL file. Expand/contract migrations should preserve at least one previous application version during observation.

## Production readiness checklist

- [ ] Protected routes enforce server authorization and database RLS.
- [ ] No service-role credential appears in browser bundles.
- [ ] MFA is required for privileged users/platform owners.
- [ ] Rate limits protect public forms, Auth-adjacent APIs, imports, exports, and ACARS.
- [ ] Correlation IDs and redacted structured logs are available.
- [ ] Alerts have owners and actionable runbooks.
- [ ] Restore has been tested against the current schema.
- [ ] Privacy/retention rules and account deletion are approved.
- [ ] Current limitations in `docs/README.md` reflect reality.
