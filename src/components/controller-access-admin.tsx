"use client";
import { FormEvent, useMemo, useState } from "react";
type Person = {
  id: string;
  employee_number: string;
  display_name: string;
  email: string;
  status: string;
};
const positions = [
  ["nellis_control", "Nellis Control"],
  ["dreamland", "Dreamland"],
  ["groom_ground", "Groom Ground"],
  ["groom_tower", "Groom Tower"],
  ["tonopah_ground", "Tonopah Ground"],
  ["tonopah_tower", "Tonopah Tower"],
] as const;
export function ControllerAccessAdmin({ people }: { people: Person[] }) {
  const activePeople = useMemo(
    () => people.filter((person) => person.status === "active"),
    [people],
  );
  const [userId, setUserId] = useState(activePeople[0]?.id ?? "");
  const selected = activePeople.find((person) => person.id === userId);
  const [callsign, setCallsign] = useState("");
  const [state, setState] = useState("approved");
  const [positionId, setPositionId] = useState("nellis_control");
  const [level, setLevel] = useState("qualified");
  const [pending, setPending] = useState(false);
  const [message, setMessage] = useState<{
    tone: "success" | "error";
    text: string;
  } | null>(null);
  async function submit(event: FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setPending(true);
    setMessage(null);
    try {
      const response = await fetch("/api/admin/controllers/access", {
        method: "POST",
        headers: { "content-type": "application/json" },
        body: JSON.stringify({
          userId,
          state,
          callsign:
            callsign.trim() || selected?.employee_number || "CONTROLLER",
          positionId,
          level,
        }),
      });
      const result = await response.json();
      if (!response.ok)
        throw new Error(
          typeof result.error === "string"
            ? result.error
            : "Unable to update ATC access",
        );
      setMessage({
        tone: "success",
        text: `${selected?.display_name ?? "Employee"} now has ${state} ${level} access for ${positions.find(([id]) => id === positionId)?.[1]}.`,
      });
    } catch (error) {
      setMessage({
        tone: "error",
        text:
          error instanceof Error
            ? error.message
            : "Unable to update ATC access",
      });
    } finally {
      setPending(false);
    }
  }
  return (
    <section className="panel controller-access-panel">
      <div className="panel-title">
        <div>
          <span className="kicker">JSCOPE CONTROLLER ACCESS</span>
          <h2>ATC authorization</h2>
        </div>
      </div>
      <p className="controller-access-intro">
        Approve a crew member for JScope and assign the tactical position and
        qualification they may claim.
      </p>
      <form className="controller-access-form" onSubmit={submit}>
        <label>
          <span>Employee</span>
          <select
            value={userId}
            onChange={(event) => {
              setUserId(event.target.value);
              setCallsign("");
            }}
            required
          >
            {activePeople.map((person) => (
              <option value={person.id} key={person.id}>
                {person.employee_number} · {person.display_name}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>Controller callsign</span>
          <input
            value={callsign}
            onChange={(event) => setCallsign(event.target.value.toUpperCase())}
            placeholder={selected?.employee_number ?? "JANET_ATC"}
            maxLength={32}
          />
        </label>
        <label>
          <span>Access state</span>
          <select
            value={state}
            onChange={(event) => setState(event.target.value)}
          >
            <option value="approved">Approved</option>
            <option value="trainee">Trainee</option>
            <option value="instructor">Instructor</option>
            <option value="suspended">Suspended</option>
            <option value="revoked">Revoked</option>
          </select>
        </label>
        <label>
          <span>Position</span>
          <select
            value={positionId}
            onChange={(event) => setPositionId(event.target.value)}
          >
            {positions.map(([id, name]) => (
              <option value={id} key={id}>
                {name}
              </option>
            ))}
          </select>
        </label>
        <label>
          <span>Qualification</span>
          <select
            value={level}
            onChange={(event) => setLevel(event.target.value)}
          >
            <option value="observer">Observer</option>
            <option value="trainee">Trainee</option>
            <option value="qualified">Qualified</option>
            <option value="instructor">Instructor</option>
          </select>
        </label>
        <button className="mini-button primary" disabled={pending || !userId}>
          {pending ? "Saving…" : "Save ATC access"}
        </button>
      </form>
      {message && (
        <p className={`form-message ${message.tone}`} role="status">
          {message.text}
        </p>
      )}
    </section>
  );
}
