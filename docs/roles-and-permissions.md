# Role and permission matrix

## Principles

Roles are additive but high-risk operations require explicit capability checks, not assumptions based on route names. All roles require an active membership unless noted. `platform_admin` is an exceptional technical role, not a normal operations role.

Suggested application roles:

- `applicant`: identity with a submitted application; not an active member.
- `crew`: active pilot/member.
- `instructor`: crew training and qualification evaluator.
- `dispatcher`: flight planning, assignment, and release.
- `operations_manager`: schedule, route, mission, and irregular-operations management.
- `fleet_manager`: fleet and maintenance records.
- `personnel_admin`: applications, memberships, and non-technical role administration.
- `auditor`: read-only operational and audit review.
- `platform_admin`: technical configuration and emergency administration.

## Matrix

Legend: **O** own records, **R** read, **W** create/update, **A** approve/publish, **—** denied. Deletion of operational records should generally be replaced by cancellation/archival.

| Capability | Applicant | Crew | Instructor | Dispatcher | Ops manager | Fleet manager | Personnel admin | Auditor | Platform admin |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| Public information | R | R | R | R | R | R | R | R | R |
| Own profile/contact settings | O | O | O | O | O | O | O | O | O |
| Application status | O | — | — | — | — | — | R/W | R | R |
| Membership directory (limited) | — | R | R | R | R | R | R/W | R | R/W |
| Assign non-technical roles | — | — | — | — | — | — | A | R | A |
| Assign `platform_admin` | — | — | — | — | — | — | — | R | A¹ |
| Own assignments/logbook | — | O | O | R | R | R | R | R | R |
| All crew records | — | — | R² | R² | R | R² | R/W | R | R/W |
| Record training checks | — | — | W | — | — | — | — | R | W |
| Approve qualifications | — | — | A | — | — | — | — | R | A |
| View schedules/routes | — | R | R | R | R | R | R | R | R |
| Draft schedules/routes | — | — | — | W | W | — | — | R | W |
| Publish/retire schedules | — | — | — | — | A | — | — | R | A |
| Import schedules | — | — | — | W | W | — | — | R | W |
| Assign crew/aircraft | — | — | — | W | W | R | — | R | W |
| Issue dispatch release | — | — | — | A | A | — | — | R | A |
| Submit own ACARS/PIREP | — | O | O | — | — | — | — | R | O |
| Amend completed flight | — | — | — | W | A | — | — | R | A |
| Manage missions | — | — | — | R² | R/W | — | — | R² | R/W |
| View aircraft status | — | R | R | R | R | R | R | R | R |
| Change aircraft status | — | — | — | — | W | W | — | R | W |
| Manage maintenance | — | — | — | — | R | W/A | — | R | W/A |
| Operational reports | — | O | R² | R | R | R | R | R | R |
| Audit log | — | — | — | R² | R | R | R | R | R |
| System settings | — | — | — | — | — | — | — | R | W/A |
| Backup/restore | — | — | — | — | — | — | — | R³ | A³ |

1. Require a second platform owner/approved break-glass process.
2. Limited to scope necessary for the role; sensitive personnel and mission fields remain masked.
3. Performed at the hosting/database platform, not by normal application table access.

## Separation of duties

- A dispatcher may draft and release a flight, but schedule publication belongs to operations management.
- An instructor may record/check training; qualification approval should be attributable and may require a different approver by policy.
- Personnel administrators manage memberships but cannot grant platform administration.
- Fleet managers control maintenance release; dispatchers consume aircraft availability but cannot clear maintenance restrictions.
- Auditors are read-only.
- Platform administrators should not perform routine operations under the technical role.

## Lifecycle behavior

- **Pending:** applicant-only access.
- **Active:** capabilities derived from current role grants.
- **Suspended:** all member/operational access denied; public and account-recovery access remain.
- **Retired:** historical attribution retained; new operational actions denied.

Role grants should have `granted_by`, `granted_at`, optional `expires_at`, and revocation metadata. Time-bound instructor/dispatcher privileges are preferred where practical.

## Implementation guidance

Store normalized role grants in database tables and expose helpers such as `has_role()` or `has_any_role()`. Do not authorize from URL area, client state, email domain, display name, or mutable JWT user metadata. High-risk functions should check a specific capability and active membership inside the same transaction as the mutation.
