# ACARS API specification

## Status and scope

This is the target external contract for JVA ACARS clients; no ACARS route handlers are currently implemented. Serve it under `/api/v1/acars`. Breaking changes require a new major path. All requests and responses use UTF-8 JSON over HTTPS.

The API supports flight initialization, ordered telemetry/events, heartbeat, and final PIREP submission. It is not a bulk public tracking API.

## Authentication

Recommended production mechanism: a per-client opaque API token issued after member authentication and device registration. Store only a hash of the token. Bind it to a member, client ID, allowed scopes, expiry, and revocation state.

```http
Authorization: Bearer <opaque-token>
X-ACARS-Client: janet-acars-desktop/1.4.0
X-Request-Id: <uuid>
```

For managed clients, requests may additionally use an HMAC signature over timestamp, method, path, and raw body with `ACARS_HMAC_SECRET`. Reject timestamps outside a five-minute window. An HMAC shared across all clients is defense-in-depth, not member identity.

Required scopes:

- `acars:flight:start`
- `acars:telemetry:write`
- `acars:pirep:submit`

Never accept a member ID, pilot identity, or role from the payload as authorization.

## Common behavior

- Timestamps are RFC 3339 UTC strings.
- IDs are UUIDs unless noted.
- Coordinates use WGS84 decimal degrees.
- Altitude is feet MSL; speed is knots; heading is degrees true; fuel is kilograms.
- Unknown properties are rejected for signed event schemas.
- Maximum JSON body: 256 KiB; event batches: 100 events; telemetry frequency: no faster than one report per five seconds unless negotiated.
- Mutating requests require `Idempotency-Key: <uuid>`, retained for at least 24 hours.
- Responses include `X-Request-Id` and should include rate-limit headers.

Error shape:

```json
{
  "error": {
    "code": "invalid_state",
    "message": "Flight is not eligible for this operation",
    "requestId": "018f5f9d-1111-7000-8000-111111111111",
    "details": []
  }
}
```

Do not expose policy names, SQL errors, stack traces, or whether another member's flight exists.

## Endpoints

### `GET /api/v1/acars/health`

Unauthenticated liveness/version response. It must not query private flight data.

```json
{
  "status": "ok",
  "apiVersion": "1",
  "time": "2026-07-21T23:41:00Z"
}
```

### `POST /api/v1/acars/flights`

Starts an ACARS session for an existing assignment/dispatch release.

Request:

```json
{
  "assignmentId": "018f5f9d-1111-7000-8000-111111111111",
  "dispatchReleaseId": "018f5f9d-2222-7000-8000-222222222222",
  "simulator": "msfs",
  "simulatorVersion": "1.0.0",
  "aircraftRegistration": "N731JV",
  "clientFlightId": "4e3deabb-f3d7-4fd7-bc04-ead786cdf75d"
}
```

Server verifies the authenticated member is assigned, release is current, aircraft matches, no conflicting active session exists, and client ID has not already been used. Response `201` (or replayed `200`):

```json
{
  "flightId": "018f5f9d-3333-7000-8000-333333333333",
  "sessionId": "018f5f9d-4444-7000-8000-444444444444",
  "status": "released",
  "acceptedAt": "2026-07-21T23:41:00Z",
  "nextSequence": 1
}
```

### `POST /api/v1/acars/flights/{flightId}/events`

Appends an ordered batch. The authenticated session must own the flight. `(session_id, sequence)` and `eventId` are unique.

```json
{
  "sessionId": "018f5f9d-4444-7000-8000-444444444444",
  "events": [
    {
      "eventId": "8fd7002c-0d89-4cf1-a63e-419d2f0c72e5",
      "sequence": 1,
      "type": "position",
      "occurredAt": "2026-07-21T23:42:00Z",
      "position": {
        "latitude": 36.0801,
        "longitude": -115.1522,
        "altitudeFt": 2180,
        "groundSpeedKt": 12,
        "verticalSpeedFpm": 0,
        "headingDeg": 190,
        "onGround": true
      },
      "aircraft": {
        "fuelKg": 8420.5,
        "grossWeightKg": 56400.0
      }
    }
  ]
}
```

Supported event types initially:

- `position`
- `block_off`
- `takeoff`
- `landing`
- `block_on`
- `pause`
- `resume`
- `disconnect`
- `reconnect`

Response `202`:

```json
{
  "acceptedThrough": 1,
  "nextSequence": 2,
  "duplicates": [],
  "warnings": []
}
```

A sequence gap returns `409 sequence_gap` with the expected sequence. A duplicate event with identical content is acknowledged; a duplicate key with different content returns `409 idempotency_conflict`.

### `POST /api/v1/acars/flights/{flightId}/heartbeat`

Signals connectivity without creating a durable high-volume position event. Limit to once per 30 seconds.

```json
{
  "sessionId": "018f5f9d-4444-7000-8000-444444444444",
  "sequence": 2,
  "occurredAt": "2026-07-21T23:42:30Z"
}
```

Response: `204 No Content`.

### `POST /api/v1/acars/flights/{flightId}/pirep`

Submits the final report. The server derives metrics from accepted events and treats client totals as assertions to compare, not authoritative facts.

```json
{
  "sessionId": "018f5f9d-4444-7000-8000-444444444444",
  "finalSequence": 428,
  "blockOffAt": "2026-07-21T23:50:00Z",
  "takeoffAt": "2026-07-22T00:03:00Z",
  "landedAt": "2026-07-22T00:48:00Z",
  "blockOnAt": "2026-07-22T00:53:00Z",
  "landingRateFpm": -184,
  "fuelUsedKg": 2338.4,
  "remarks": "Routine simulation flight"
}
```

Response `202`:

```json
{
  "pirepId": "018f5f9d-5555-7000-8000-555555555555",
  "status": "pending_review",
  "warnings": []
}
```

Submission is idempotent and does not silently overwrite a completed PIREP. Corrections use an authenticated staff workflow with audit history.

## Status codes

| Code | Meaning |
|---:|---|
| 200/201/202/204 | Success, creation, queued/accepted, or empty success |
| 400 | Malformed JSON or schema violation |
| 401 | Missing/invalid/expired credential |
| 403 | Credential lacks scope or member/session is ineligible |
| 404 | Resource unavailable to this principal |
| 409 | State, sequence, or idempotency conflict |
| 413 | Request exceeds size/batch limit |
| 422 | Semantically impossible values |
| 429 | Rate limit exceeded; honor `Retry-After` |
| 500/503 | Transient server failure; retry with backoff |

## Retry and offline behavior

Clients persist unsent events locally, retain sequence order, and retry `408`, `429`, and `5xx` with exponential backoff plus jitter. Do not retry other `4xx` without correcting the request. A client reconnect first resends the last unacknowledged batch; server idempotency prevents duplication.

## Validation and retention

Reject impossible coordinates, speeds, time travel beyond tolerance, mismatched registrations, and transitions inconsistent with flight state. Flag suspicious values for review rather than trusting them. Retain raw telemetry only as long as operationally necessary; preserve derived flight summaries and audit evidence according to the approved retention policy.
