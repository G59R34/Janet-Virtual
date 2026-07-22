# Database migration instructions

## Source of truth

`supabase/migrations/*.sql` is the sole source of truth for database structure, functions, grants, RLS, views, and storage policies. Dashboard edits are prohibited except during incident response; any emergency edit must be captured immediately in a migration.

The directory is currently empty. Establish the baseline before implementing Supabase-dependent features.

## Naming and structure

Create migrations with the CLI:

```bash
npx supabase migration new create_identity_domain
```

This produces a UTC timestamped file. Use lowercase action-oriented names, for example:

```text
20260721150000_create_identity_domain.sql
20260721151500_create_operations_domain.sql
20260721153000_enable_rls.sql
```

Each migration should be focused, deterministic, and safe to run once in order. Include schema and security changes together when separating them would expose data.

## Authoring rules

- Qualify objects with their schema, normally `public` or a private application schema.
- Add tables with RLS enabled in the same migration; do not leave a deployment window without policies.
- Explicitly set `search_path` on `security definer` functions and revoke default execution.
- Add foreign keys, unique constraints, checks, and indexes intentionally.
- Store timestamps as `timestamptz`; avoid database-local time assumptions.
- Make data backfills bounded and restartable. Separate large backfills from lock-sensitive DDL.
- Never include production data, passwords, access tokens, personal email addresses, or generated dumps.
- Prefer additive, backward-compatible expand/migrate/contract changes.

## Local workflow

1. Start Supabase with `npx supabase start`.
2. Create/edit the migration.
3. Rebuild from zero:

   ```bash
   npx supabase db reset
   ```

4. Inspect the schema and policies in local Studio.
5. Run database tests when available, then `npm run lint` and `npm run build`.
6. Review generated SQL and the application compatibility window.

If prototyping through local Studio, capture changes with:

```bash
npx supabase db diff -f describe_change
```

Treat generated diffs as drafts. Remove ownership noise, inspect destructive statements, add RLS/grants, and reset from scratch before review.

## Review checklist

- What application versions are compatible before and after deployment?
- Does the migration lock or rewrite a large table?
- Are new columns nullable or safely defaulted during rollout?
- Are all exposed tables and views protected?
- Can `anon` or `authenticated` execute a new function unexpectedly?
- Do policy tests cover allowed and denied cases?
- Is an index needed for every policy predicate and frequent foreign-key lookup?
- Is rollback feasible, and is data loss explicit?
- Does the migration alter public/ACARS/import contracts?

## Deployment sequence

1. Create and validate a fresh backup; verify provider backup health.
2. Apply to an isolated local database from zero.
3. Apply to staging using `npx supabase db push`.
4. Run smoke, RLS, import, and API compatibility tests.
5. Review `npx supabase db push --dry-run` against production.
6. Pause risky writers if the migration requires it.
7. Apply from protected CI or an approved operator environment.
8. Deploy compatible application code.
9. Verify schema version, error rate, critical queries, RLS denials, and job health.

For expand/contract changes, deploy in this order:

1. **Expand:** add compatible structures.
2. **Migrate:** dual-read/write if needed and backfill in batches.
3. **Switch:** deploy code using the new structure.
4. **Contract:** remove old structures in a later release after verification.

## Rollback and recovery

Supabase migrations are forward-only operational records. Do not edit or delete a migration already applied to a shared environment.

- For a safe logical reversal, create a new compensating migration.
- For an incompatible application release, roll the application back only if the old schema remains compatible.
- For destructive corruption, stop writers and restore from backup/PITR according to [Backup and restore](backup-restore.md).
- Never run `db reset` against a hosted environment.

Every destructive migration must state its recovery point, expected data loss, maintenance window, and validation query in the pull request.

## Drift control

Periodically compare the linked remote schema with migrations using CLI schema diff tooling. Investigate drift; do not blindly apply a generated diff. The expected end state is that a clean local reset and the hosted database expose the same application schema and policy definitions.
