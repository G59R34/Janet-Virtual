# Backup and restore

## Objectives

Initial production objectives:

- **RPO:** no more than 24 hours of database changes lost.
- **RTO:** service restored within 4 hours.

These are targets, not guarantees. Confirm the selected Supabase plan's backup/PITR features and complete timed restore drills before publishing an SLA. Critical operations may require a tighter PITR-backed RPO.

## What must be protected

| Asset | Backup mechanism | Notes |
|---|---|---|
| PostgreSQL schema/data | Provider backups/PITR plus periodic logical backup | Includes Auth-linked application data and policies |
| Auth configuration | Configuration inventory and documented templates | Password hashes/users are database/provider-managed |
| Storage objects | Independent object copy/inventory where required | Database rows alone do not restore object bytes |
| Application | Git plus immutable deployment artifacts | Secrets excluded |
| Environment/secrets | Approved secrets manager with recovery access | Never in database dump or Git |
| DNS, SMTP, platform config | Infrastructure/config inventory | Record owners and recovery process |

Supabase database backups may not include Storage object contents. Verify provider behavior; protect object bytes separately.

## Backup policy

- Enable the strongest provider-managed backup/PITR option justified by the production plan.
- Keep automated backups in a separate failure domain/account where feasible.
- Produce encrypted logical backups on an approved schedule for portability and long-term checkpoints.
- Retain at least: 7 daily, 4 weekly, and 3 monthly recovery points unless legal/privacy policy requires otherwise.
- Encrypt in transit and at rest; restrict backup operators; audit access and deletion.
- Monitor backup completion, age, size anomalies, and restore eligibility.
- Never use production data in development. Restore to an isolated restricted environment and sanitize before broader use.

## Logical backup

Use a current PostgreSQL client compatible with the hosted database. Obtain a short-lived direct connection credential from the secrets manager. Example pattern:

```bash
pg_dump --format=custom --no-owner --no-acl --file=jva.dump "POSTGRES_DIRECT_URL"
```

The quoted value above is a placeholder; inject the real URL securely rather than committing it or exposing it in shell history. Also preserve migration files from Git. Test the resulting archive with `pg_restore --list` and record its checksum, timestamp, source environment, PostgreSQL version, and encryption/key reference.

A logical dump can contain personal and restricted data. Handle it at the highest data classification present.

## Restore drill procedure

Run at least quarterly and after major schema/platform changes:

1. Open an incident/change record and define the recovery point.
2. Provision a new isolated Supabase/PostgreSQL target; do not overwrite production for a drill.
3. Restrict network and operator access.
4. Restore database backup/PITR to the target.
5. For logical archives, use a compatible client:

   ```bash
   pg_restore --clean --if-exists --no-owner --no-acl --dbname="RESTORE_DATABASE_URL" jva.dump
   ```

6. Restore Storage objects and reconcile `storage.objects` metadata with object bytes using provider-supported tooling.
7. Apply only migrations newer than the recovery point when required and proven compatible.
8. Configure temporary non-production Auth URLs and disable outbound email/webhooks/jobs.
9. Validate the checklist below.
10. Record actual RPO/RTO, missing assets, errors, and corrective actions.
11. Securely destroy the drill environment and temporary credentials after approval.

## Validation checklist

- Migration/schema versions are expected.
- RLS is enabled and forced where designed; anonymous/member/privileged deny tests pass.
- Auth identities map to profiles/memberships.
- Active schedule version and generated flights are internally consistent.
- Aircraft location/status and maintenance restrictions are consistent.
- Completed flights/PIREP totals and audit chains reconcile.
- Private Storage objects are present and access policies deny unauthorized reads.
- Counts/checksums match the backup manifest within expected point-in-time differences.
- Application smoke tests pass without enabling real email, ACARS callbacks, or scheduled jobs.

## Production disaster recovery

1. Declare incident command and freeze deployments.
2. If corruption is ongoing, disable writers, scheduled jobs, importers, ACARS ingestion, and service-role workloads.
3. Preserve logs and identify the last known good point.
4. Choose PITR, provider snapshot, or logical restore based on scope and RPO.
5. Restore to a new target where possible; validate before cutover.
6. Rotate database/service credentials if compromise is possible.
7. Update application secrets/endpoints and deploy.
8. Re-enable reads, then controlled writes, then asynchronous integrations.
9. Reconcile events received during the outage using idempotency keys.
10. Communicate impact and complete a blameless post-incident review.

## Accidental logical deletion

Do not immediately restore all production. Stop the responsible workflow, determine affected rows and dependencies, restore the relevant recovery point to an isolated database, extract only verified records, and reintroduce them through a reviewed compensating script/migration with audit evidence.

## Ownership

Assign named primary and backup operators in the private runbook. Backup operators must have platform access, MFA, secrets-manager recovery access, and permission to perform drills. Application roles such as dispatcher or operations manager do not receive database backup credentials.
