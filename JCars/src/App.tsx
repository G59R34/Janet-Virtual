import { useEffect, useRef, useState } from "react";
import {
  Activity,
  Cloud,
  LogOut,
  Minus,
  Plane,
  Radio,
  Headphones,
  Mic,
  RefreshCw,
  ShieldCheck,
} from "lucide-react";
import { getCurrentWindow } from "@tauri-apps/api/window";
import { isEnabled, enable, disable } from "@tauri-apps/plugin-autostart";
import { openUrl } from "@tauri-apps/plugin-opener";
import { jvaApi, supabase, type ClientConfig, type TripReport } from "./api";
import { readSnapshot } from "./telemetry";
import type {
  Assignment,
  Snapshot,
  TacticalState,
  TrackingState,
} from "./types";
const native = () => "__TAURI_INTERNALS__" in window;
export default function App() {
  const [session, setSession] =
    useState<
      Awaited<ReturnType<typeof supabase.auth.getSession>>["data"]["session"]
    >(null);
  const [assignments, setAssignments] = useState<Assignment[]>([]);
  const [selected, setSelected] = useState("");
  const [tracking, setTracking] = useState<TrackingState>("idle");
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [phase, setPhase] = useState("STANDBY");
  const [points, setPoints] = useState(0);
  const [report, setReport] = useState<TripReport>();
  const [message, setMessage] = useState("");
  const [autoStart, setAutoStart] = useState(false);
  const [config, setConfig] = useState<ClientConfig>();
  const [acarsSessionId, setAcarsSessionId] = useState<string>();
  const [tactical, setTactical] = useState<TacticalState | null>(null);
  const [tacticalBusy, setTacticalBusy] = useState(false);
  const [transmitting, setTransmitting] = useState(false);
  const [audioInputs, setAudioInputs] = useState<MediaDeviceInfo[]>([]);
  const [audioOutputs, setAudioOutputs] = useState<MediaDeviceInfo[]>([]);
  const [inputDevice, setInputDevice] = useState("default");
  const [outputDevice, setOutputDevice] = useState("default");
  const sessionId = useRef<string | undefined>(undefined);
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => setSession(data.session));
    const { data } = supabase.auth.onAuthStateChange((_e, s) => setSession(s));
    if (native())
      isEnabled()
        .then(setAutoStart)
        .catch(() => {});
    return () => data.subscription.unsubscribe();
  }, []);
  useEffect(() => {
    if (session) refresh();
    else setAssignments([]);
  }, [session]);
  useEffect(() => {
    navigator.mediaDevices
      ?.enumerateDevices()
      .then((devices) => {
        setAudioInputs(
          devices.filter((device) => device.kind === "audioinput"),
        );
        setAudioOutputs(
          devices.filter((device) => device.kind === "audiooutput"),
        );
      })
      .catch(() => {});
  }, []);
  useEffect(() => {
    if (!acarsSessionId) return;
    let active = true;
    let timeout: number | undefined;
    const poll = async () => {
      try {
        const result = await jvaApi.tacticalState(acarsSessionId);
        if (active) setTactical(result.state);
      } catch {
      } finally {
        if (active) timeout = window.setTimeout(poll, 3000);
      }
    };
    void poll();
    return () => {
      active = false;
      if (timeout) window.clearTimeout(timeout);
    };
  }, [acarsSessionId]);
  async function refresh() {
    try {
      setMessage("");
      const [data, remoteConfig] = await Promise.all([
        jvaApi.assignments(),
        jvaApi.config(),
      ]);
      setAssignments(data.assignments);
      setConfig(remoteConfig);
      if (!selected && data.assignments[0]) setSelected(data.assignments[0].id);
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Unable to load assignments");
    }
  }
  async function begin() {
    const assignment = assignments.find((x) => x.id === selected);
    if (!assignment?.flight.aircraft) {
      setMessage("Dispatch must assign an aircraft before tracking can begin.");
      return;
    }
    const first = await readSnapshot();
    setSnapshot(first);
    if (!first.connected) {
      setMessage(
        "Start MSFS or X-Plane and load into the assigned aircraft before tracking.",
      );
      return;
    }
    setTracking("starting");
    setMessage("");
    setReport(undefined);
    setPoints(0);
    try {
      const simulator = first.provider.startsWith("X-Plane")
        ? "X-Plane"
        : "Microsoft Flight Simulator";
      const opened = await jvaApi.startSession(
        assignment.flight.id,
        assignment.flight.aircraft.id,
        simulator,
      );
      sessionId.current = opened.id;
      setAcarsSessionId(opened.id);
      setTactical({ session: opened.tactical, instructions: [] });
      setTracking("tracking");
      await sample();
      timer.current = window.setInterval(
        sample,
        Math.max(2, config?.settings.telemetry?.interval_seconds ?? 5) * 1000,
      );
    } catch (e) {
      setTracking("error");
      setMessage(e instanceof Error ? e.message : "Unable to begin tracking");
    }
  }
  async function sample() {
    try {
      const next = await readSnapshot();
      setSnapshot(next);
      if (next.connected && sessionId.current) {
        const accepted = await jvaApi.telemetry(sessionId.current, next);
        setPhase(accepted.phase.replaceAll("_", " ").toUpperCase());
        setPoints((value) => value + 1);
      }
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Telemetry upload failed");
    }
  }
  async function stop() {
    if (!sessionId.current) return;
    const remarks =
      window.prompt("Optional trip report remarks:", "") ?? undefined;
    setTracking("stopping");
    if (timer.current) window.clearInterval(timer.current);
    timer.current = undefined;
    try {
      const compiled = await jvaApi.complete(sessionId.current, remarks);
      setReport(compiled);
      setMessage(
        `PIREP submitted · score ${compiled.score} · ${compiled.status.replaceAll("_", " ")}`,
      );
      sessionId.current = undefined;
      setAcarsSessionId(undefined);
      setTactical(null);
      setTracking("idle");
      setPhase("COMPLETE");
      await refresh();
    } catch (e) {
      setTracking("tracking");
      timer.current = window.setInterval(
        sample,
        Math.max(2, config?.settings.telemetry?.interval_seconds ?? 5) * 1000,
      );
      setMessage(
        e instanceof Error ? e.message : "Unable to compile trip report",
      );
    }
  }
  async function toggleAutoStart() {
    if (!native()) return;
    try {
      if (autoStart) {
        await disable();
        setAutoStart(false);
      } else {
        await enable();
        setAutoStart(true);
      }
    } catch (e) {
      setMessage(e instanceof Error ? e.message : "Autostart change failed");
    }
  }
  async function openSimBrief() {
    if (!assignment) return;
    try {
      setMessage("");
      if (native()) await openUrl(assignment.flight.simbrief_plan.dispatch_url);
      else
        window.open(
          assignment.flight.simbrief_plan.dispatch_url,
          "_blank",
          "noopener,noreferrer",
        );
    } catch (error) {
      setMessage(
        error instanceof Error
          ? `Unable to open SimBrief: ${error.message}`
          : "Unable to open SimBrief in the system browser.",
      );
    }
  }
  async function acknowledge(
    id: string,
    response:
      "wilco" | "roger" | "unable" | "standby" | "request_clarification",
  ) {
    setTacticalBusy(true);
    try {
      await jvaApi.acknowledgeInstruction(id, response);
      if (acarsSessionId)
        setTactical((await jvaApi.tacticalState(acarsSessionId)).state);
    } catch (error) {
      setMessage(
        error instanceof Error
          ? error.message
          : "Unable to acknowledge instruction",
      );
    } finally {
      setTacticalBusy(false);
    }
  }
  if (!session) return <Login onMessage={setMessage} message={message} />;
  const assignment = assignments.find((x) => x.id === selected);
  const requiredFrequency = Number(tactical?.session.displayFrequency ?? 0);
  const radioTuned = Boolean(
    snapshot &&
    requiredFrequency &&
    (Math.abs(snapshot.com1Active - requiredFrequency) < 0.006 ||
      Math.abs(snapshot.com2Active - requiredFrequency) < 0.006),
  );
  return (
    <main className="app">
      <header>
        <div className="brand">
          <b>JCARS</b>
          <span>JANET CREW ACARS</span>
        </div>
        <button
          className="icon"
          aria-label="Minimize to tray"
          onClick={() => native() && getCurrentWindow().hide()}
        >
          <Minus />
        </button>
      </header>
      <section className="identity">
        <div>
          <span>AUTHENTICATED EMPLOYEE</span>
          <strong>{session.user.email}</strong>
        </div>
        <ShieldCheck />
        <button onClick={() => supabase.auth.signOut()}>
          <LogOut /> Sign out
        </button>
      </section>
      <section className="assignment">
        <div className="section-title">
          <div>
            <span>WEBSITE ASSIGNMENT</span>
            <h1>{assignment?.flight.tracking_callsign ?? "No assignment"}</h1>
          </div>
          <button
            className="icon"
            onClick={refresh}
            title="Refresh from website"
          >
            <RefreshCw />
          </button>
        </div>
        {assignments.length ? (
          <select
            value={selected}
            onChange={(e) => setSelected(e.target.value)}
            disabled={tracking === "tracking"}
          >
            {assignments.map((x) => (
              <option value={x.id} key={x.id}>
                {x.flight.tracking_callsign} · {x.flight.origin.local_code}–
                {x.flight.destination.local_code}
              </option>
            ))}
          </select>
        ) : (
          <p className="empty">
            No eligible assigned flights. Assignments are managed in the
            employee portal.
          </p>
        )}
        {assignment && (
          <div className="route">
            <div>
              <span>ORIGIN</span>
              <b>{assignment.flight.origin.local_code}</b>
            </div>
            <Plane />
            <div>
              <span>DESTINATION</span>
              <b>{assignment.flight.destination.local_code}</b>
            </div>
            <div>
              <span>AIRCRAFT</span>
              <b>{assignment.flight.aircraft?.registration ?? "UNASSIGNED"}</b>
            </div>
          </div>
        )}
      </section>
      {assignment && (
        <section className="simbrief-plan">
          <div>
            <span>FLIGHT PLANNING</span>
            <strong>
              {assignment.flight.simbrief_plan.status === "generated"
                ? "SIMBRIEF OFP READY"
                : "SIMBRIEF PLAN REQUIRED"}
            </strong>
            <small>
              {assignment.flight.simbrief_plan.route ??
                "Route, fuel, weather, and performance will be generated by SimBrief."}
            </small>
          </div>
          <button onClick={openSimBrief}>OPEN SIMBRIEF</button>
        </section>
      )}
      <section className="telemetry">
        <div className="section-title">
          <div>
            <span>
              SIMULATOR LINK · {phase} · {points} POINTS
            </span>
            <h2>
              {snapshot?.connected
                ? snapshot.provider
                : "Waiting for simulator"}
            </h2>
          </div>
          <i className={snapshot?.connected ? "online" : "offline"}>
            <Radio />
          </i>
        </div>
        <div className="metrics">
          <Metric
            label="ALTITUDE"
            value={`${Math.round(snapshot?.altitude ?? 0)} FT`}
          />
          <Metric
            label="GROUND SPEED"
            value={`${Math.round(snapshot?.groundSpeed ?? 0)} KT`}
          />
          <Metric
            label="VERTICAL SPEED"
            value={`${Math.round(snapshot?.verticalSpeed ?? 0)} FPM`}
          />
          <Metric
            label="FUEL"
            value={`${Math.round(snapshot?.fuel ?? 0)} GAL`}
          />
        </div>
        {report && (
          <div className="report-line">
            <b>PIREP {report.status.replaceAll("_", " ")}</b>
            <span>
              {report.blockMinutes}m block · {report.flightMinutes}m flight ·
              score {report.score}
            </span>
          </div>
        )}
      </section>
      {tracking === "tracking" && (
        <section className="tactical-radio">
          <div className="tactical-safety">
            <ShieldCheck />
            <p>
              <b>PRIVATE TACTICAL SIMULATION</b> JCars is not VATSIM ATC. VATSIM
              controllers, network rules, TCAS alerts, and operational safety
              always take precedence.
            </p>
          </div>
          <div className="section-title">
            <div>
              <span>
                JCARS TACTICAL RADIO · SEPARATE FROM SIMULATOR / XPILOT RADIO
              </span>
              <h2>
                {tactical?.session.positionName ?? "Tactical control available"}
              </h2>
            </div>
            <i
              className={
                tactical?.session.status === "active" ? "online" : "offline"
              }
            >
              <Radio />
            </i>
          </div>
          {!tactical ? (
            <button
              className="tactical-opt-in"
              disabled={tacticalBusy}
              onClick={undefined}
            >
              {tacticalBusy ? "CONNECTING…" : "OPT IN TO TACTICAL CONTROL"}
            </button>
          ) : (
            <>
              <div className="tactical-grid">
                <Metric
                  label="CONTROLLER"
                  value={tactical.session.controllerCallsign}
                />
                <Metric
                  label="REQUIRED VHF"
                  value={tactical.session.displayFrequency}
                />
                <Metric
                  label="COM1 ACTIVE"
                  value={(snapshot?.com1Active ?? 0).toFixed(3)}
                />
                <Metric
                  label="COM2 ACTIVE"
                  value={(snapshot?.com2Active ?? 0).toFixed(3)}
                />
                <Metric
                  label="VOICE"
                  value={tactical.session.voiceState.toUpperCase()}
                />
                <Metric
                  label="STATUS"
                  value={tactical.session.status.toUpperCase()}
                />
              </div>
              {!radioTuned && (
                <div className="tactical-frequency-warning">
                  OFF FREQUENCY · TUNE COM1 OR COM2 TO{" "}
                  {tactical.session.displayFrequency}
                </div>
              )}
              <div className="audio-devices">
                <label>
                  <Mic /> INPUT
                  <select
                    value={inputDevice}
                    onChange={(event) => setInputDevice(event.target.value)}
                  >
                    <option value="default">System default</option>
                    {audioInputs.map((device) => (
                      <option key={device.deviceId} value={device.deviceId}>
                        {device.label || "Audio input"}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  <Headphones /> OUTPUT
                  <select
                    value={outputDevice}
                    onChange={(event) => setOutputDevice(event.target.value)}
                  >
                    <option value="default">System default</option>
                    {audioOutputs.map((device) => (
                      <option key={device.deviceId} value={device.deviceId}>
                        {device.label || "Audio output"}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              <button
                className={`tactical-ptt ${transmitting ? "transmitting" : ""}`}
                onMouseDown={() => setTransmitting(true)}
                onMouseUp={() => setTransmitting(false)}
                onMouseLeave={() => setTransmitting(false)}
                disabled={tactical.session.voiceState !== "connected"}
              >
                JCARS PTT · {transmitting ? "TRANSMITTING" : "HOLD TO TALK"}
              </button>
              {tactical.instructions[0] && (
                <div className="tactical-instruction">
                  <span>JCARS TACTICAL INSTRUCTION</span>
                  <strong>{tactical.instructions[0].text}</strong>
                  <small>
                    {tactical.instructions[0].type
                      .replaceAll("_", " ")
                      .toUpperCase()}{" "}
                    ·{" "}
                    {new Date(
                      tactical.instructions[0].issuedAt,
                    ).toLocaleTimeString()}
                  </small>
                  {!tactical.instructions[0].acknowledgement && (
                    <div>
                      {(
                        [
                          "wilco",
                          "roger",
                          "standby",
                          "unable",
                          "request_clarification",
                        ] as const
                      ).map((response) => (
                        <button
                          key={response}
                          disabled={tacticalBusy}
                          onClick={() =>
                            acknowledge(tactical.instructions[0].id, response)
                          }
                        >
                          {response.replaceAll("_", " ")}
                        </button>
                      ))}
                    </div>
                  )}
                </div>
              )}
              <button
                className="tactical-suspend"
                disabled={tacticalBusy || tactical.session.status !== "active"}
                onClick={undefined}
              >
                SUSPEND TACTICAL CONTROL
              </button>
            </>
          )}
        </section>
      )}
      {message && <div className="alert">{message}</div>}
      <button
        className={`track ${tracking}`}
        disabled={
          !assignment || tracking === "starting" || tracking === "stopping"
        }
        onClick={tracking === "tracking" ? stop : begin}
      >
        <Activity />
        {tracking === "tracking" ? "Complete & submit trip" : "Begin tracking"}
      </button>
      <footer>
        <label>
          <input
            type="checkbox"
            checked={autoStart}
            onChange={toggleAutoStart}
          />{" "}
          Start JCars with Windows
        </label>
        <span>
          <Cloud /> Website managed · v0.2.0
        </span>
      </footer>
    </main>
  );
}
function Metric({ label, value }: { label: string; value: string }) {
  return (
    <div>
      <span>{label}</span>
      <b>{value}</b>
    </div>
  );
}
function Login({
  message,
  onMessage,
}: {
  message: string;
  onMessage: (m: string) => void;
}) {
  const [busy, setBusy] = useState(false);
  async function login(data: FormData) {
    setBusy(true);
    onMessage("");
    const { error } = await supabase.auth.signInWithPassword({
      email: String(data.get("email")),
      password: String(data.get("password")),
    });
    setBusy(false);
    if (error) onMessage(error.message);
  }
  return (
    <main className="login">
      <div className="login-brand">
        <b>JCARS</b>
        <span>JANET CREW ACARS</span>
      </div>
      <Radio className="mark" />
      <h1>Flight data link</h1>
      <p>
        Sign in with your JANET Virtual Airlines employee account. Assignments
        and permissions are managed by the website.
      </p>
      <form action={login}>
        <label>
          EMPLOYEE EMAIL
          <input type="email" name="email" required autoComplete="email" />
        </label>
        <label>
          PASSWORD
          <input
            type="password"
            name="password"
            required
            autoComplete="current-password"
          />
        </label>
        {message && <div className="alert">{message}</div>}
        <button disabled={busy}>{busy ? "Authenticating…" : "Sign in"}</button>
      </form>
    </main>
  );
}
