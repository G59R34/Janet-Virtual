import fs from "node:fs";
import path from "node:path";
import readline from "node:readline";
const root = process.argv[2] || process.env.XPLANE_CUSTOM_DATA;
if (!root)
  throw new Error(
    "Pass the X-Plane Custom Data directory or set XPLANE_CUSTOM_DATA",
  );
const bounds = { west: -118.2, east: -114.6, south: 35.7, north: 38.5 };
const inside = (lat, lon, pad = 0) =>
  lat >= bounds.south - pad &&
  lat <= bounds.north + pad &&
  lon >= bounds.west - pad &&
  lon <= bounds.east + pad;
const lines = (file) =>
  fs.readFileSync(path.join(root, file), "utf8").split(/\r?\n/);
const points = new Map();
const put = (id, lat, lon, kind, extra = {}) => {
  if (id && Number.isFinite(lat) && Number.isFinite(lon) && inside(lat, lon, 2))
    points.set(id, { id, lat, lon, kind, ...extra });
};
for (const line of lines("earth_fix.dat")) {
  const v = line.trim().split(/\s+/);
  if (v.length >= 5) put(v[2], Number(v[0]), Number(v[1]), "fix");
}
const navaids = [];
for (const line of lines("earth_nav.dat")) {
  const v = line.trim().split(/\s+/);
  if (v.length < 9) continue;
  const lat = Number(v[1]),
    lon = Number(v[2]),
    type = Number(v[0]);
  if (!inside(lat, lon, 0.5)) continue;
  const item = {
    id: v[7],
    lat,
    lon,
    type,
    elevation: Number(v[3]),
    frequency: Number(v[4]),
    name: v.slice(10).join(" "),
  };
  navaids.push(item);
  put(item.id, lat, lon, "navaid", item);
}
const airports = [];
for (const line of lines("earth_aptmeta.dat")) {
  const v = line.trim().split(/\s+/);
  if (v.length < 6) continue;
  const lat = Number(v[2]),
    lon = Number(v[3]);
  if (inside(lat, lon))
    airports.push({
      id: v[0],
      lat,
      lon,
      elevation: Number(v[4]),
      runways: [],
      procedures: [],
      ground: { pavements: [], taxiNodes: [], taxiEdges: [] },
    });
}

// Custom Data contains navigation records, while detailed airport layouts are
// supplied by X-Plane's scenery apt.dat. Stream the large file and retain only
// airports already inside this sector.
const xplaneRoot = path.resolve(root, "..");
const aptCandidates = [
  path.join(xplaneRoot, "Global Scenery", "Global Airports", "Earth nav data", "apt.dat"),
];
const aptPath = aptCandidates.find(fs.existsSync);
if (aptPath) {
  const airportById = new Map(airports.map((airport) => [airport.id, airport]));
  let airport = null;
  let pavement = null;
  const input = fs.createReadStream(aptPath, { encoding: "utf8" });
  for await (const raw of readline.createInterface({ input, crlfDelay: Infinity })) {
    const line = raw.trim();
    if (!line) continue;
    const v = line.split(/\s+/);
    const code = Number(v[0]);
    if (code === 1 || code === 16 || code === 17) {
      airport = airportById.get(v[4]) || null;
      pavement = null;
      continue;
    }
    if (!airport) continue;
    if (code === 100 && v.length >= 20) {
      airport.runways.push({ id: v[8], lat: Number(v[9]), lon: Number(v[10]) });
      airport.runways.push({ id: v[17], lat: Number(v[18]), lon: Number(v[19]) });
    } else if (code === 110) {
      pavement = { name: v.slice(5).join(" ") || "PAVEMENT", points: [] };
      airport.ground.pavements.push(pavement);
    } else if (pavement && [111, 112, 113, 114].includes(code)) {
      const lat = Number(v[1]), lon = Number(v[2]);
      if (Number.isFinite(lat) && Number.isFinite(lon)) pavement.points.push([lon, lat]);
      if (code === 113 || code === 114) pavement = null;
    } else if (code === 1201 && v.length >= 5) {
      airport.ground.taxiNodes.push({ id: v[4], lat: Number(v[1]), lon: Number(v[2]) });
    } else if (code === 1202 && v.length >= 5) {
      airport.ground.taxiEdges.push({ from: v[1], to: v[2], name: v.slice(5).join(" ") || v[4] });
    }
  }
}
function compact(value) {
  const hemi = value[0],
    digits = value.slice(1),
    degLen = hemi === "E" || hemi === "W" ? 3 : 2;
  const deg = Number(digits.slice(0, degLen)),
    min = Number(digits.slice(degLen, degLen + 2)),
    sec = Number(digits.slice(degLen + 2)) / 100;
  const result = deg + min / 60 + sec / 3600;
  return hemi === "S" || hemi === "W" ? -result : result;
}
const procedureKinds = new Set(["SID", "STAR", "APPCH"]);
for (const airport of airports) {
  const file = path.join(root, "CIFP", `${airport.id}.dat`);
  if (!fs.existsSync(file)) continue;
  const groups = new Map();
  for (const line of fs.readFileSync(file, "utf8").split(/\r?\n/)) {
    if (line.startsWith("RWY:")) {
      const [left, right] = line.split(";");
      const id = left.split(",")[0].slice(4).trim();
      const c = right?.split(",");
      if (c?.length >= 2)
        airport.runways.push({ id, lat: compact(c[0]), lon: compact(c[1]) });
      continue;
    }
    const fields = line.split(";")[0].split(",");
    const kind = fields[0]?.split(":")[0];
    if (!procedureKinds.has(kind)) continue;
    const name = fields[2]?.trim(),
      transition = fields[3]?.trim() || "FINAL",
      fix = fields[4]?.trim();
    const point =
      points.get(fix) || airport.runways.find((runway) => runway.id === fix);
    if (!name || !point) continue;
    const key = `${kind}:${name}:${transition}`;
    if (!groups.has(key))
      groups.set(key, { kind, name, transition, points: [] });
    groups.get(key).points.push({ id: fix, lat: point.lat, lon: point.lon });
  }
  airport.procedures = [...groups.values()].filter(
    (item) => item.points.length > 1,
  );
}
const airways = [];
for (const line of lines("earth_awy.dat")) {
  const v = line.trim().split(/\s+/);
  if (v.length < 11) continue;
  const a = points.get(v[0]),
    b = points.get(v[3]);
  if (a && b && inside(a.lat, a.lon, 0.5) && inside(b.lat, b.lon, 0.5))
    airways.push({
      name: v[10],
      from: a.id,
      to: b.id,
      points: [
        [a.lon, a.lat],
        [b.lon, b.lat],
      ],
      base: Number(v[8]),
      top: Number(v[9]),
    });
}
function dms(text) {
  const match = text.match(
    /(\d+):(\d+):(\d+)\s+([NS])\s+(\d+):(\d+):(\d+)\s+([EW])/,
  );
  if (!match) return null;
  const lat =
      Number(match[1]) + Number(match[2]) / 60 + Number(match[3]) / 3600,
    lon = Number(match[5]) + Number(match[6]) / 60 + Number(match[7]) / 3600;
  return [match[8] === "W" ? -lon : lon, match[4] === "S" ? -lat : lat];
}
const airspaces = [];
let area = null;
for (const line of lines(path.join("airspaces", "airspace.txt"))) {
  if (line.startsWith("AC ")) {
    if (
      area?.points.length &&
      area.points.some(([lon, lat]) => inside(lat, lon))
    )
      airspaces.push(area);
    area = {
      class: line.slice(3).trim(),
      name: "",
      lower: "",
      upper: "",
      points: [],
    };
  } else if (area && line.startsWith("AN ")) area.name = line.slice(3).trim();
  else if (area && line.startsWith("AL ")) area.lower = line.slice(3).trim();
  else if (area && line.startsWith("AH ")) area.upper = line.slice(3).trim();
  else if (area && line.startsWith("DP ")) {
    const p = dms(line.slice(3));
    if (p) area.points.push(p);
  }
}
if (area?.points.length && area.points.some(([lon, lat]) => inside(lat, lon)))
  airspaces.push(area);
const fixes = [...points.values()].filter(
  (item) => item.kind === "fix" && inside(item.lat, item.lon),
);
const cycle = JSON.parse(
  fs.readFileSync(path.join(root, "cycle.json"), "utf8"),
);
const data = {
  metadata: {
    source: "Local X-Plane 12 Custom Data",
    cycle: cycle.cycle,
    revision: cycle.revision,
    generatedAt: new Date().toISOString(),
    bounds,
  },
  airports,
  fixes,
  navaids,
  airways,
  airspaces: airspaces.filter(
    (a) => a.class === "R" || /MOA|R-48/.test(a.name),
  ),
};
const out = path.resolve("public/generated/nttr-sector.json");
fs.mkdirSync(path.dirname(out), { recursive: true });
fs.writeFileSync(out, JSON.stringify(data));
console.log(
  JSON.stringify(
    {
      out,
      cycle: data.metadata.cycle,
      airports: airports.length,
      fixes: fixes.length,
      navaids: navaids.length,
      airways: airways.length,
      procedures: airports.reduce((n, a) => n + a.procedures.length, 0),
      taxiways: airports.reduce((n, a) => n + a.ground.taxiEdges.length, 0),
      pavements: airports.reduce((n, a) => n + a.ground.pavements.length, 0),
      airspaces: data.airspaces.length,
    },
    null,
    2,
  ),
);
