# JANET Virtual Airline Ecosystem

A production-oriented virtual-airline platform for persistent commuter, dispatch, fleet, maintenance, mission, personnel, and ACARS workflows. It is an independent flight-simulation community and is not affiliated with JANET or any real government, military, intelligence, or contractor organization.

## Architecture

- Next.js 16 App Router and TypeScript provide the public site, role-oriented portals, and ACARS route handlers.
- Supabase Auth establishes identity; PostgreSQL RLS is the primary authorization boundary.
- PostgreSQL stores all persistent operational records. `flight_status_events` and append-only `audit_logs` preserve history.
- Supabase Realtime should subscribe only to a user, flight, airport, or active date window.
- Storage buckets are private by default: `avatars`, `aircraft-liveries`, `aircraft-documents`, `training-documents`, `dispatch-releases`, `pirep-attachments`, and `system-branding`.

## Local setup

1. Copy `.env.example` to `.env.local` and add a Supabase project URL and keys.
2. Run `supabase db reset` with the Supabase CLI to apply migrations and seeds.
3. Run `npm install`, then `npm run dev`.
4. Open `http://localhost:3000`.

Never expose `SUPABASE_SERVICE_ROLE_KEY` to browser code. Authentication configuration and destructive database actions are system-administrator-only operations.

## Migrations and deployment

Migrations live in `supabase/migrations` and are applied in lexical order. Test a reset locally, then run `supabase db push` against the target project. Deploy the Next.js app after configuring the same public environment values. Schedule idempotent database/Edge Function jobs for generation, qualification expiry, maintenance checks, telemetry downsampling, and notifications.

## Authorization summary

Applicants see their application. Pilots see their assignments, own PIREPs, qualifications, and notifications. Dispatch and operations roles manage flights and releases. Maintenance roles manage aircraft technical state. Chief pilots administer crew privileges. Owners have broad operational access; only system administrators control secrets and destructive technical settings. Client controls are convenience only—RLS and server authorization remain authoritative.

## ACARS API

All endpoints require a valid Supabase session cookie and JSON bodies.

- `POST /api/acars/sessions`: `{ flightId, aircraftId, simulator, clientVersion }`. Validates a crew assignment and creates a session.
- `POST /api/acars/telemetry`: `{ sessionId, latitude, longitude, altitude, heading, groundSpeed, verticalSpeed, fuel, onGround, payload? }`. Accepts telemetry only for the pilot's active session.
- `POST /api/acars/pireps`: accepts flight, aircraft, simulator, time, fuel, route, remarks, and detected violations; calculates a multi-factor initial score and routes the report to automatic acceptance or review.

Production clients should use short-lived sessions, idempotency keys, version checks, request size/rate limits, and batched telemetry. Recent high-resolution telemetry should be downsampled before retention expiry.

## Schedule importer

Normalize pasted tables or CSV into template rows, map station and simulator codes, validate callsigns and local times, select weekdays/timezone/probability/variability, detect `(template, departure)` conflicts, preview every row, then insert approved rows. Attribution is stored in `source_reference`; the reference site is never queried at runtime.

## Backup and restore

Use scheduled Supabase/PostgreSQL backups plus periodic `pg_dump` exports of schema and data. Restore into a new project first, verify Auth mappings, RLS policies, object bucket policies, counts, flight history, and audit immutability, then rotate application credentials and cut traffic over.
