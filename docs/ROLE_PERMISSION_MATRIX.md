# Role and permission matrix

| Capability | Applicant | Pilot/Captain | Instructor/Chief Pilot | Dispatch/Ops | Maintenance/Fleet | Owner | Sysadmin |
|---|---:|---:|---:|---:|---:|---:|---:|
| Application/profile | Own | Own | Review | Read | Read | All | All |
| Assignments/PIREP/ACARS | — | Own | Manage crew | Manage | Read | All | All |
| Flights/schedules/routes | — | Eligible/read | Read | Manage | Read | All | All |
| Qualifications/training | — | Own | Manage | Validate | Validate | All | All |
| Aircraft/maintenance | — | Assigned/read | Read | Assign/read | Manage | All | All |
| Missions/personnel | — | Assigned tier | Permitted | Manage | Permitted | All | All |
| Audit logs | — | — | Relevant | Relevant | Relevant | Read | All |
| Secrets/auth/destructive DB | — | — | — | — | — | — | Manage |

RLS and database functions are authoritative. UI visibility does not grant access.
