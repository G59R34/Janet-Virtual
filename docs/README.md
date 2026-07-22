# JANET Virtual Airline Ecosystem documentation

This directory is the operating documentation for the JANET Virtual Airline Ecosystem (JVA): a fictional flight-simulation community built with Next.js App Router and Supabase.

> **Implementation status:** the repository currently contains a Next.js 16 UI scaffold. Supabase clients, authentication, route handlers, database objects, migrations, ACARS endpoints, and importer jobs described here are the production target and are not yet implemented. Do not treat a documented contract as a deployed capability. `supabase/migrations/` is currently empty.

## Documentation map

| Document | Audience | Purpose |
|---|---|---|
| [Architecture](architecture.md) | Engineers, operators | Components, trust boundaries, modules, and data ownership |
| [Local setup](local-setup.md) | Engineers | Run the web app and local Supabase safely |
| [Supabase setup](supabase-setup.md) | Platform engineers | Create and configure local/staging/production projects |
| [Database migrations](database-migrations.md) | Engineers, DBAs | Author, review, apply, and recover migrations |
| [Security and RLS](security-and-rls.md) | Engineers, security reviewers | Authentication, authorization, RLS, secrets, and audit controls |
| [Roles and permissions](roles-and-permissions.md) | Product owners, engineers | Role capabilities and approval boundaries |
| [Deployment](deployment.md) | Release engineers | Production release and rollback procedure |
| [ACARS API](acars-api.md) | Client and API engineers | Versioned flight telemetry and PIREP contract |
| [Schedule importer](schedule-importer.md) | Operations, engineers | CSV format, validation, staging, and publication |
| [Backup and restore](backup-restore.md) | Platform engineers | Backup policy, restore drills, and disaster recovery |

## Documentation conventions

- **Current** means verifiable in this repository.
- **Target** means the production design to implement.
- Database object names use `snake_case`; TypeScript identifiers use `camelCase`.
- Times are stored as `timestamptz` in UTC. Schedule-local times include an IANA time zone.
- Public station labels and internal operational details are separate data classifications.
- JANET VA is fictional and must not store real classified, government, passenger, or sensitive operational information.

## Required release gates

A production capability is complete only when its migration, RLS policy, tests, audit behavior, runbook update, and rollback path have been reviewed together. UI visibility is never an authorization control.
