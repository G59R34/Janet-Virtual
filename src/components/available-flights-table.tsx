"use client";
import { useMemo, useState } from "react";
import { useRouter } from "next/navigation";
import { Plane, Search, Trash2 } from "lucide-react";

export type AvailableFlight = {
  id: string;
  tracking_callsign: string;
  flight_number: string | null;
  scheduled_departure: string;
  scheduled_arrival: string;
  planned_altitude_ft: number | null;
  status: string;
  passenger_count: number;
  origin: { local_code: string; display_label: string | null } | null;
  destination: { local_code: string; display_label: string | null } | null;
  aircraft: { registration: string } | null;
  schedule_template: { name: string; aircraft_category: string | null } | null;
};
const time = new Intl.DateTimeFormat("en-US", {
  month: "short",
  day: "2-digit",
  hour: "2-digit",
  minute: "2-digit",
  timeZoneName: "short",
});
export function AvailableFlightsTable({
  flights,
  assigned,
  captainEligible,
  canDeleteFlights,
}: {
  flights: AvailableFlight[];
  assigned: string[];
  captainEligible: boolean;
  canDeleteFlights: boolean;
}) {
  const router = useRouter();
  const [query, setQuery] = useState("");
  const [pending, setPending] = useState("");
  const [message, setMessage] = useState("");
  const visible = useMemo(() => {
    const needle = query.trim().toLowerCase();
    return needle
      ? flights.filter((f) =>
          [
            f.tracking_callsign,
            f.flight_number,
            f.origin?.local_code,
            f.destination?.local_code,
            f.schedule_template?.name,
          ].some((value) => value?.toLowerCase().includes(needle)),
        )
      : flights;
  }, [flights, query]);
  async function reserve(
    flightId: string,
    position: "captain" | "first_officer",
  ) {
    setPending(flightId + position);
    setMessage("");
    const response = await fetch("/api/crew/flights/reserve", {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({ flightId, position }),
    });
    const result = await response.json();
    setPending("");
    if (!response.ok) {
      setMessage(
        typeof result.error === "string"
          ? result.error
          : "Unable to reserve this flight",
      );
      return;
    }
    setMessage(`${result.callsign} added to your assignments.`);
    router.refresh();
  }
  async function remove(flight: AvailableFlight) {
    if (!window.confirm(`Remove ${flight.tracking_callsign} from the board? Current crew assignments will be cancelled.`)) return;
    setPending(flight.id + "delete"); setMessage("");
    const response = await fetch("/api/admin/flights", { method: "DELETE", headers: { "content-type": "application/json" }, body: JSON.stringify({ flightId: flight.id, reason: "Removed from flight board by administrator" }) });
    const result = await response.json(); setPending("");
    if (!response.ok) { setMessage(typeof result.error === "string" ? result.error : "Unable to remove flight"); return; }
    setMessage(`${result.callsign} removed from the board.`); router.refresh();
  }
  return (
    <section className="pickup-panel">
      <div className="pickup-toolbar">
        <label>
          <Search size={15} />
          <input
            value={query}
            onChange={(event) => setQuery(event.target.value)}
            placeholder="Search callsign, station, or flight"
            aria-label="Search available flights"
          />
        </label>
        <span>
          {visible.length} of {flights.length} operations
        </span>
      </div>
      {message && (
        <p className="pickup-message" role="status">
          {message}
        </p>
      )}
      {visible.length ? (
        <div className="pickup-table">
          <div className="pickup-row head">
            <span>OPERATION</span>
            <span>ROUTE</span>
            <span>DEPARTURE / BLOCK</span>
            <span>AIRCRAFT</span>
            <span>FLIGHT PLAN</span>
            <span>PICK UP</span>
          </div>
          {visible.map((f) => {
            const claimed = assigned.includes(f.id);
            const block = Math.round(
              (new Date(f.scheduled_arrival).getTime() -
                new Date(f.scheduled_departure).getTime()) /
                60000,
            );
            return (
              <div className="pickup-row" key={f.id}>
                <span>
                  <strong>{f.tracking_callsign}</strong>
                  <small>
                    {f.flight_number ?? "SCHEDULED"} ·{" "}
                    {f.status.replaceAll("_", " ")}
                  </small>
                </span>
                <span className="route">
                  <b>{f.origin?.local_code ?? "—"}</b>
                  <i>→</i>
                  <b>{f.destination?.local_code ?? "—"}</b>
                </span>
                <span>
                  <strong>
                    {time.format(new Date(f.scheduled_departure))}
                  </strong>
                  <small>{block} min block</small>
                </span>
                <span>
                  <strong>
                    {f.aircraft?.registration ?? "DISPATCH PENDING"}
                  </strong>
                  <small>
                    {f.schedule_template?.aircraft_category ?? "COMMUTER"}
                  </small>
                </span>
                <span>
                  <strong>
                    {f.planned_altitude_ft
                      ? `FL${Math.round(f.planned_altitude_ft / 100)}`
                      : "TBD"}
                  </strong>
                  <small>{f.passenger_count ?? 0} passengers</small>
                </span>
                <span className="pickup-actions">
                  {claimed ? (
                    <em>IN YOUR ASSIGNMENTS</em>
                  ) : (
                    <>
                      <button
                        disabled={pending !== ""}
                        onClick={() => reserve(f.id, "first_officer")}
                      >
                        {pending === f.id + "first_officer"
                          ? "CLAIMING…"
                          : "FIRST OFFICER"}
                      </button>
                      {captainEligible && (
                        <button
                          className="primary"
                          disabled={pending !== ""}
                          onClick={() => reserve(f.id, "captain")}
                        >
                          {pending === f.id + "captain"
                            ? "CLAIMING…"
                            : "CAPTAIN"}
                        </button>
                      )}
                    </>
                  )}
                  {canDeleteFlights && (
                    <button className="danger" disabled={pending !== ""} onClick={() => remove(f)} title={`Remove ${f.tracking_callsign} from board`}>
                      <Trash2 size={12} /> {pending === f.id + "delete" ? "REMOVING…" : "DELETE"}
                    </button>
                  )}
                </span>
              </div>
            );
          })}
        </div>
      ) : (
        <div className="empty-state">
          <Plane size={25} />
          <strong>No flights match this search.</strong>
          <p>Clear the filter to see every generated operation.</p>
        </div>
      )}
    </section>
  );
}
