$ErrorActionPreference = "Stop"
$projectRoot = Split-Path -Parent $PSScriptRoot
$sector = Join-Path $projectRoot "public\generated\nttr-sector.json"
if (-not (Test-Path -LiteralPath $sector)) {
  throw "Generate the local AIRAC sector first with: node scripts/import-xplane-navdata.mjs <X-Plane Custom Data>"
}
cargo build --manifest-path (Join-Path $projectRoot "Cargo.toml") --release
$release = Join-Path $projectRoot "target\release"
$data = Join-Path $release "data"
New-Item -ItemType Directory -Path $data -Force | Out-Null
Copy-Item -LiteralPath $sector -Destination (Join-Path $data "nttr-sector.json") -Force
Write-Host "JScope packaged at $release\jscope.exe"
