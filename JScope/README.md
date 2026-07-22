# JScope Native Controller Client

JScope is a native Rust Windows controller workstation. It does not use React, Vite, a browser, or a webview.

## Development

```powershell
cargo run --manifest-path JScope/Cargo.toml
```

The client defaults to `http://localhost:3000` and the configured JCars Supabase project. Override these when needed:

```powershell
$env:JSCOPE_API_URL = "https://example.invalid"
$env:JSCOPE_SUPABASE_URL = "https://project.supabase.co"
$env:JSCOPE_SUPABASE_KEY = "sb_publishable_..."
```

## AIRAC sector

The licensed X-Plane/Navigraph derivative remains local and git-ignored:

```powershell
node JScope/scripts/import-xplane-navdata.mjs "F:\SteamLibrary\steamapps\common\X-Plane 12\Custom Data"
```

Set `JSCOPE_SECTOR_PATH` to override the generated sector location.

## Windows release

```powershell
powershell -ExecutionPolicy Bypass -File JScope/scripts/build-windows.ps1
```

The packaged executable and its local sector file are written to `JScope/target/release`.
