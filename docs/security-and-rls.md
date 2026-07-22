# Security and row-level security

## Security model

Authorization is deny-by-default and enforced in PostgreSQL. Next.js route protection, hidden navigation, and form validation are defense-in-depth, not substitutes for RLS.

Data classes:

| Class | Examples | Handling |
|---|---|---|
| Public | Sanitized station labels, approved fleet summaries, aggregates | Expose through allow-listed views/endpoints only |
| Member | Own profile, assignments, training status | Authenticated; owner and role policies |
| Operational | Schedules, aircraft status, dispatch releases | Active membership plus operational role |
| Restricted | Mission details, personnel administration, audit records | Explicit privileged roles; MFA; audited access |
| Secret | Service keys, HMAC secrets, database credentials | Secrets manager only; never stored in app tables/logs |

Do not put real government, classified, passenger, medical, identity-document, or sensitive real-world operational data into JVA.

## Identity and authorization

- `auth.users` is the identity source.
- `profiles` stores display-safe user attributes and references `auth.users.id`.
- `memberships` records lifecycle (`pending`, `active`, `suspended`, `retired`) and member number.
- `roles` and `membership_roles` grant capabilities. Roles are not user-editable.
- Authorization helpers read `auth.uid()` and database role assignments; never trust a role supplied in JWT user metadata or request payloads.
- Suspending a membership must immediately remove operational access even if the Auth session remains valid.

Privileged role changes require a second authorized actor where practical and always emit immutable audit records.

## RLS baseline

For every application table exposed through the Data API:

```sql
alter table public.example enable row level security;
alter table public.example force row level security;
revoke all on table public.example from anon, authenticated;
```

Then grant only required SQL operations and add explicit policies. `USING` controls rows visible/targetable; `WITH CHECK` controls rows that may be inserted or become the result of an update. Define both for updates.

Policy design guidelines:

- Use stable authorization helper functions such as `private.has_role('dispatcher')`.
- Put helper functions in a non-exposed schema, set `search_path = ''`, schema-qualify references, and control `EXECUTE` grants.
- Index `membership_id`, owner IDs, foreign keys, status fields, and columns used in policy predicates.
- Avoid recursive policies that query their own protected table.
- Public access should query sanitized views, not base operational tables.
- Views must use the intended invoker semantics; verify behavior against the deployed PostgreSQL/Supabase version.
- Storage policies must authorize both bucket and object-path ownership.

Example pattern (adapt table/role names in a migration and test it):

```sql
create policy "members read own profile"
on public.profiles
for select
to authenticated
using (user_id = (select auth.uid()));

create policy "personnel manage profiles"
on public.profiles
for update
to authenticated
using ((select private.has_role('personnel_admin')))
with check ((select private.has_role('personnel_admin')));
```

## Service role

The service role bypasses RLS. Restrict it to server-only imports, scheduled jobs, carefully reviewed administration, and recovery tooling.

- Never prefix it with `NEXT_PUBLIC_`.
- Never return it from a route, Server Action, error payload, or log.
- Keep privileged functions small and assert the business authorization separately.
- Prefer a user-scoped Supabase server client for normal browser requests.
- Rotate immediately after suspected disclosure.

## API and mutation controls

- Parse every input with strict schemas; reject unknown fields where possible.
- Enforce request size, pagination, time range, and upload limits.
- Require CSRF-resistant same-origin patterns for cookie-authenticated mutations.
- Authenticate ACARS independently and bind credentials to a member/client.
- Rate-limit login, application, recovery, import, report export, and ACARS endpoints.
- Use idempotency keys for retries.
- Return generic authentication errors; log structured reason codes without secrets.
- Validate state transitions in a transaction and lock contested assignment rows.

## Audit requirements

Append-only audit events should include actor user/membership, action, target type/ID, UTC timestamp, correlation ID, source (`web`, `acars`, `import`, `job`), and a redacted change summary. Audit:

- role and membership lifecycle changes;
- dispatch release and amendment;
- flight completion/correction;
- schedule publication and rollback;
- aircraft/maintenance status changes;
- mission access-control changes;
- export, backup, and restore operations;
- configuration and secret rotation events (metadata only).

Application roles may read only the subset specified in the role matrix and may never update/delete audit rows. Database owners must use tightly controlled break-glass procedures.

## Verification matrix

Every table/function change needs automated tests for:

1. anonymous user;
2. authenticated user without a membership;
3. suspended member;
4. active crew member accessing own and another member's data;
5. each privileged role;
6. service role where applicable;
7. inserts/updates that attempt to change ownership or privilege fields.

Test through the same Supabase API path the app uses, not only as database owner. An owner connection bypasses important controls.

## Operational controls

- Enforce MFA for privileged accounts and platform owners.
- Keep staging and production credentials separate.
- Set dependency and secret scanning in CI.
- Review Supabase Auth, database, and application logs with retention appropriate to the community policy.
- Alert on repeated denials, service-role use from unexpected workloads, mass exports, role escalation, and anomalous ACARS volume.
- Document a break-glass account, require approval, rotate after use, and audit the incident.
