# RLS design

Every browser-accessible table has RLS enabled. Policies use `auth.uid()` plus narrowly scoped `SECURITY DEFINER` helpers with an empty search path. Public data is exposed only through visibility flags and a sanitized view. Operational writes require an active authorized role. Crew access is relationship-based through `crew_assignments`. Audit records are append-only and have no client insert/update/delete policy.

Before production, test every table as `anon`, each role, an unrelated authenticated user, and a suspended user. Add policies alongside new tables in the same migration; never grant broad schema access as a substitute.
