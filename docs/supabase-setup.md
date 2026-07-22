# Supabase setup

## Environment model

Use separate Supabase projects for **staging** and **production**, plus Supabase CLI locally. Never connect preview deployments to production. Recommended mapping:

| Application environment | Supabase | Data |
|---|---|---|
| Local | CLI containers | Synthetic seed data |
| Preview | Dedicated preview/staging project or branch | Synthetic data |
| Staging | Staging project | Sanitized test data |
| Production | Production project | Live community data |

Select a region close to the application runtime. Record project reference, region, owner group, backup capability, and support plan in the private operations inventory—not in Git.

## Create a hosted project

1. Create the project under an organization with at least two owners and enforced MFA.
2. Save recovery information in the approved secrets manager.
3. Set spending controls and budget alerts.
4. Record the project URL and publishable key in the deployment platform.
5. Store the service-role key and direct/pooler database URLs as encrypted server-only secrets.
6. Configure Auth and Storage before applying application migrations.

## Authentication configuration

- Set the canonical Site URL to the production HTTPS origin.
- Allow only explicit local, preview, and staging redirect URL patterns.
- Configure a custom SMTP provider before production; do not rely on development mail limits.
- Customize verification, recovery, invitation, and address-change templates without leaking internal data.
- Require verified email before membership activation.
- Enable CAPTCHA/rate limiting for public application and recovery flows.
- Require MFA for command, dispatch, personnel, auditor, and administrator roles.
- Disable unused identity providers and anonymous sign-ins.

Auth identity and application authorization are distinct. `auth.users` proves identity; active membership and role tables grant JVA capabilities.

## Database configuration

Apply schema exclusively through reviewed files in `supabase/migrations/`; see [Database migrations](database-migrations.md). The initial migration set should establish:

1. Extensions required by the application.
2. Enums/domains and utility functions.
3. Identity and membership tables.
4. Network, fleet, crew, scheduling, and operations tables.
5. Audit/outbox tables and immutable audit triggers.
6. RLS enablement, grants, and policies.
7. Restricted and public views.
8. Storage buckets and `storage.objects` policies.

Use the least-privileged `authenticated`/`anon` grants. Revoke broad function execution and table privileges before explicitly granting required access. All exposed tables must have RLS enabled.

## Storage

Recommended private buckets:

| Bucket | Purpose | Retention |
|---|---|---|
| `schedule-imports` | Original import files and validation reports | 90 days or policy requirement |
| `flight-attachments` | Optional PIREP/flight evidence | Community retention policy |
| `generated-reports` | Short-lived exports | Automatic expiry |

Use UUID-based object paths such as `<membership_id>/<object_id>/<filename>`. Validate MIME type and size server-side. Signed URLs should be short-lived and issued only after authorization.

## Realtime

Add only the minimum operational tables to the Realtime publication. RLS still applies, but high-change telemetry tables can overwhelm clients; publish summarized flight state rather than raw position reports where possible. Clients must recover by querying current state after reconnect.

## Secrets and keys

- Browser: `NEXT_PUBLIC_SUPABASE_URL` and `NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY` only.
- Server with user context: the same URL/public key plus request cookies.
- Privileged server jobs: `SUPABASE_SERVICE_ROLE_KEY`, imported only from server-only code.
- Database administration: direct URL for migrations; transaction pooler for compatible serverless workloads.
- Rotate keys after suspected exposure and on the organization schedule. Redeploy all consumers atomically.

## Link and apply

Authenticate the CLI through an approved operator account, then:

```bash
npx supabase link --project-ref YOUR_PROJECT_REF
npx supabase db push --dry-run
npx supabase db push
```

Do not put the project reference or database password into shell history in shared environments. CI should inject them from protected secrets and apply production migrations only from a protected branch/environment with approval.

## Post-setup verification

- A clean local `db reset` succeeds.
- Staging schema matches migrations.
- An anonymous user can access only documented public views/endpoints.
- A normal crew member cannot access other members' private records.
- Privileged actions are audited.
- Storage objects cannot be listed or downloaded without policy approval.
- Auth redirect and recovery flows use approved origins.
- Backup status and a restore drill are documented.
