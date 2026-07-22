# JCars tactical control and JScope

## Boundaries

JCars remains the pilot telemetry client. JScope is a separate controller-only client under `JScope/`. Both authenticate with central Supabase identity and call the JVA Next.js backend. Postgres security-definer functions—not either client—decide controller approval, qualification, position ownership, aircraft participation, instruction authority, acknowledgement ownership, and suspension.

The tactical system never creates a VATSIM controller connection, integrates with AFV, changes simulator radios, or tunes xPilot. Channel IDs are private JCars identifiers; displayed frequencies are server-configured labels only.

## Authorization

Controller approval and position qualification are independent. Operational JScope login requires a controller profile in `trainee`, `approved`, or `instructor` state. A trainee also requires an active supervision record. Position acquisition rechecks a current qualification and uses a partial unique index as the authoritative primary-position lock. Administrative roles do not grant controller access.

JScope receives a random 256-bit, 30-minute session token. Only its SHA-256 digest is stored. Every operational command requires both a valid central identity token and the JScope token. Position commands additionally require an active position session. Command nonces reject replay.

Pilots appear only after explicitly opting in from an active, owned ACARS session and accepting the safety notice. Pilot reads and acknowledgements are ownership checked in the database. Suspension cancels pending instructions and handoffs but preserves mission and audit history.

## Versioned events

All tactical records carry an event version. Initial client updates use authenticated snapshots every three seconds; mutation responses are authoritative. Event categories are aircraft participation, controller presence, position ownership, instructions, acknowledgements, handoffs, safety suspension, and authorization failures. A later Realtime publication may broadcast sanitized row changes, but privileged commands must continue through validated RPCs.

## Handoffs

Handoffs use `requested → accepted|standby|unable|rejected|cancelled|expired`, followed by `contacting → completed`. Completion must be a backend transaction that updates the aircraft position and private channel only after pilot acceptance. Server configuration defines the allowed position graph; clients never infer display names from identifiers.

## Voice

The first slice models private channel authorization and independent device/PTT state but deliberately leaves transport disconnected. Production voice should use WebRTC with an SFU or equivalent service. The backend should mint short-lived room credentials only after validating the tactical aircraft or occupied controller position. Separate device selection, PTT, volume, mute, and channel membership remain local to JCars/JScope. No simulator, xPilot, VATSIM, or AFV APIs belong in the media path.

## Audit

Controller session creation/denial, position acquisition, opt-in, instructions, acknowledgements, handoffs, suspension, revocation, and administrative changes append immutable tactical activity records. Clients receive only the minimum data needed for their role.

## Incremental delivery

1. Secure vertical slice: approval/qualification checks, position lock, pilot opt-in, target snapshot, instruction, acknowledgement, suspension.
2. Server-controlled handoff transitions and receiving-position inbound queues.
3. Hardened realtime fanout and presence recovery.
4. Isolated WebRTC voice and device/PTT controls.
5. Controller applications, administration, supervision grace/takeover, and revocation tooling.
6. Range geometry, runways, fixes, alerts, history, coordination, and full authorization/safety test matrix.
