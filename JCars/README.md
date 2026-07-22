# JCars

JCars is the lightweight JANET Virtual Airlines ACARS companion. It authenticates an employee, downloads website-authorized assignments, opens an ACARS session, samples a native simulator adapter, and uploads telemetry while tracking. All airline configuration and operational management remains in the website.

## Development

1. Install the Windows prerequisites from the official Tauri documentation: Microsoft C++ Build Tools, WebView2, and Rust 1.77.2 or newer.
2. Copy `.env.example` to `.env` and configure the public Supabase URL/key plus the JVA website URL.
3. Run `npm install`.
4. Run `npm run desktop` for the native app, or `npm run dev` for a browser-only UI preview.

Closing the main window hides it to the system tray. The tray menu can reopen or fully quit JCars. Autostart is opt-in.

## Scope and security

- Supabase handles employee authentication and refresh tokens.
- The website validates every assignment and ACARS session using the bearer token.
- JCars does not contain role, assignment, scoring, schedule, aircraft, or release-management controls.
- Telemetry is uploaded only while the user explicitly tracks a website assignment.
- Disconnected simulator adapters never upload synthetic position data.

`read_simulator_snapshot` is the native adapter boundary. It currently reports disconnected until the MSFS SimConnect adapter is added; X-Plane can later use a separate UDP adapter behind the same command.
