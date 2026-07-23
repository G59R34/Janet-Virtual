import { createClient } from "@/lib/supabase/server";
import { AdminAction } from "@/components/admin-action";
import { ControllerAccessAdmin } from "@/components/controller-access-admin";
import { DeleteUserAction } from "@/components/delete-user-action";
type Application = {
  id: string;
  status: string;
  submitted_at: string;
  applicant: {
    employee_number: string;
    display_name: string;
    email: string;
  } | null;
};
type Profile = {
  id: string;
  employee_number: string;
  display_name: string;
  email: string;
  status: string;
  role: string;
};
type Review = {
  id: string;
  score: number;
  block_minutes: number;
  flight_minutes: number;
  fuel_used: number;
  landing_rate: number | null;
  detected_violations: string[];
  remarks: string | null;
  pilot: { employee_number: string; display_name: string } | null;
  flight: {
    tracking_callsign: string;
    origin: { local_code: string };
    destination: { local_code: string };
    aircraft: { registration: string } | null;
  } | null;
};
export async function CrewAdmin({
  canManageAtc = false,
  canDeleteUsers = false,
}: {
  canManageAtc?: boolean;
  canDeleteUsers?: boolean;
}) {
  const db = await createClient();
  const [
    { data: applications, error },
    { data: profiles },
    { data: qualifications },
    { data: flights },
    { data: pireps },
  ] = await Promise.all([
    db
      .from("applications")
      .select(
        "id,status,submitted_at,applicant:profiles!applications_applicant_user_id_fkey(employee_number,display_name,email)",
      )
      .order("submitted_at", { ascending: false })
      .limit(30),
    db
      .from("profiles")
      .select("id,employee_number,display_name,email,status,role")
      .order("created_at", { ascending: false })
      .limit(100),
    db
      .from("qualifications")
      .select("id,code,name")
      .eq("active", true)
      .order("name"),
    db
      .from("flights")
      .select("id")
      .in("status", ["generated", "awaiting_dispatch", "released"]),
    db
      .from("pireps")
      .select(
        "id,score,block_minutes,flight_minutes,fuel_used,landing_rate,detected_violations,remarks,pilot:profiles!pireps_pilot_id_fkey(employee_number,display_name),flight:flights!pireps_flight_id_fkey(tracking_callsign,origin:airports!flights_origin_airport_id_fkey(local_code),destination:airports!flights_destination_airport_id_fkey(local_code),aircraft(registration))",
      )
      .eq("status", "manual_review")
      .order("submitted_at")
      .limit(50),
  ]);
  const apps = (applications ?? []) as unknown as Application[];
  const crew = (profiles ?? []) as Profile[];
  const reviews = (pireps ?? []) as unknown as Review[];
  return (
    <div className="admin-console">
      <section className="admin-summary">
        <div>
          <span>PENDING APPLICATIONS</span>
          <b>{apps.filter((a) => a.status === "submitted").length}</b>
        </div>
        <div>
          <span>PIREP REVIEWS</span>
          <b>{reviews.length}</b>
        </div>
        <div>
          <span>ACTIVE EMPLOYEES</span>
          <b>{crew.filter((p) => p.status === "active").length}</b>
        </div>
        <div>
          <span>OPEN FLIGHTS</span>
          <b>{flights?.length ?? 0}</b>
        </div>
      </section>
      {canManageAtc && <ControllerAccessAdmin people={crew} />}
      <section className="panel pirep-review">
        <div className="panel-title">
          <div>
            <span className="kicker">FLIGHT REPORT QUALITY CONTROL</span>
            <h2>Manual PIREP reviews</h2>
          </div>
        </div>
        {reviews.length ? (
          <div className="review-list">
            {reviews.map((report) => (
              <article key={report.id}>
                <header>
                  <div>
                    <strong>
                      {report.flight?.tracking_callsign ?? "UNKNOWN FLIGHT"}
                    </strong>
                    <small>
                      {report.flight?.origin.local_code} →{" "}
                      {report.flight?.destination.local_code} ·{" "}
                      {report.flight?.aircraft?.registration ?? "UNASSIGNED"}
                    </small>
                  </div>
                  <div>
                    <b>{report.score}</b>
                    <span>ACARS SCORE</span>
                  </div>
                </header>
                <div className="review-evidence">
                  <span>
                    PILOT
                    <b>
                      {report.pilot?.employee_number} ·{" "}
                      {report.pilot?.display_name}
                    </b>
                  </span>
                  <span>
                    BLOCK / FLIGHT
                    <b>
                      {report.block_minutes} / {report.flight_minutes} MIN
                    </b>
                  </span>
                  <span>
                    FUEL USED<b>{Math.round(report.fuel_used)} GAL</b>
                  </span>
                  <span>
                    LANDING
                    <b>
                      {report.landing_rate === null
                        ? "NOT DETECTED"
                        : `${report.landing_rate} FPM`}
                    </b>
                  </span>
                </div>
                {report.detected_violations?.length > 0 && (
                  <p className="review-flags">
                    REVIEW FLAGS · {report.detected_violations.join(" · ")}
                  </p>
                )}
                {report.remarks && (
                  <p className="review-remarks">
                    PILOT REMARKS · {report.remarks}
                  </p>
                )}
                <footer>
                  <AdminAction
                    body={{
                      action: "review_pirep",
                      pirepId: report.id,
                      status: "accepted",
                      notes:
                        "Telemetry and calculated flight report approved by administrator",
                    }}
                    label="Approve report"
                    tone="primary"
                  />
                  <AdminAction
                    body={{
                      action: "review_pirep",
                      pirepId: report.id,
                      status: "rejected",
                      notes:
                        "Flight report rejected after administrative telemetry review",
                    }}
                    label="Deny report"
                    tone="danger"
                    prompt={`Deny ${report.flight?.tracking_callsign ?? "this report"}?`}
                  />
                </footer>
              </article>
            ))}
          </div>
        ) : (
          <div className="empty-state">
            <strong>No PIREPs require manual review.</strong>
            <p>
              Reports below the acceptance threshold appear here and notify
              administrators.
            </p>
          </div>
        )}
      </section>
      <section className="panel">
        <div className="panel-title">
          <div>
            <span className="kicker">RECRUITMENT QUEUE</span>
            <h2>Applications</h2>
          </div>
        </div>
        {error ? (
          <p className="form-message error">{error.message}</p>
        ) : (
          <div className="admin-table">
            <div className="admin-row head">
              <span>APPLICANT</span>
              <span>SUBMITTED</span>
              <span>STATUS</span>
              <span>ACTIONS</span>
            </div>
            {apps.map((app) => (
              <div className="admin-row" key={app.id}>
                <span>
                  <strong>{app.applicant?.display_name ?? "Unknown"}</strong>
                  <small>
                    {app.applicant?.employee_number} · {app.applicant?.email}
                  </small>
                </span>
                <span>{new Date(app.submitted_at).toLocaleDateString()}</span>
                <span>
                  <i
                    className={`badge ${app.status === "approved" ? "enabled" : "disabled"}`}
                  >
                    {app.status.toUpperCase()}
                  </i>
                </span>
                <span className="row-actions">
                  {app.status === "submitted" && (
                    <>
                      <AdminAction
                        body={{
                          action: "review_application",
                          applicationId: app.id,
                          status: "approved",
                          notes: "Approved by Crew Administration",
                        }}
                        label="Approve"
                        tone="primary"
                      />
                      <AdminAction
                        body={{
                          action: "review_application",
                          applicationId: app.id,
                          status: "waitlisted",
                          notes: "Pending additional review",
                        }}
                        label="Waitlist"
                      />
                      <AdminAction
                        body={{
                          action: "review_application",
                          applicationId: app.id,
                          status: "rejected",
                          notes: "Application not accepted",
                        }}
                        label="Reject"
                        tone="danger"
                        prompt="Reject this application?"
                      />
                    </>
                  )}
                </span>
              </div>
            ))}
          </div>
        )}
      </section>
      <section className="panel">
        <div className="panel-title">
          <div>
            <span className="kicker">EMPLOYEE DIRECTORY</span>
            <h2>Crew access administration</h2>
          </div>
        </div>
        <div className="admin-table crew">
          <div className="admin-row head">
            <span>EMPLOYEE</span>
            <span>PRIMARY ROLE</span>
            <span>STATUS</span>
            <span>ADMINISTRATIVE ACTIONS</span>
          </div>
          {crew.map((person) => (
            <div className="admin-row" key={person.id}>
              <span>
                <strong>{person.display_name}</strong>
                <small>
                  {person.employee_number} · {person.email}
                </small>
              </span>
              <span>{person.role.replaceAll("_", " ")}</span>
              <span>
                <i
                  className={`badge ${person.status === "active" ? "enabled" : "disabled"}`}
                >
                  {person.status}
                </i>
              </span>
              <span className="row-actions">
                <AdminAction
                  body={{
                    action: "grant_role",
                    userId: person.id,
                    role: "pilot",
                  }}
                  label="Pilot"
                />
                <AdminAction
                  body={{
                    action: "grant_role",
                    userId: person.id,
                    role: "captain",
                  }}
                  label="Captain"
                />
                <AdminAction
                  body={{
                    action: "grant_role",
                    userId: person.id,
                    role: "dispatcher",
                  }}
                  label="Dispatcher"
                />
                {qualifications?.[0] && (
                  <AdminAction
                    body={{
                      action: "issue_qualification",
                      userId: person.id,
                      qualificationId: qualifications[0].id,
                    }}
                    label={`Issue ${qualifications[0].code}`}
                  />
                )}{" "}
                {person.status === "active" ? (
                  <AdminAction
                    body={{
                      action: "set_status",
                      userId: person.id,
                      status: "suspended",
                      reason: "Administrative suspension",
                    }}
                    label="Suspend"
                    tone="danger"
                    prompt="Suspend this employee's operational privileges?"
                  />
                ) : (
                  <AdminAction
                    body={{
                      action: "set_status",
                      userId: person.id,
                      status: "active",
                      reason: "Administrative reinstatement",
                    }}
                    label="Reactivate"
                    tone="primary"
                  />
                )}
                {canDeleteUsers && <DeleteUserAction person={person} />}
              </span>
            </div>
          ))}
        </div>
      </section>
    </div>
  );
}
