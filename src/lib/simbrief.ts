/* eslint-disable @typescript-eslint/no-explicit-any */
type FlightForSimBrief = {
  id: string;
  tracking_callsign: string;
  flight_number: string | null;
  planned_altitude_ft: number | null;
  route_string: string | null;
  origin: {icao: string | null; iata: string | null; local_code: string | null};
  destination: {icao: string | null; iata: string | null; local_code: string | null};
  aircraft: {registration: string} | null;
};

export function airportCode(airport: FlightForSimBrief["origin"]) {
  return airport.icao ?? airport.iata ?? airport.local_code ?? "";
}

export function simbriefStaticId(flightId: string) {
  return `jva_${flightId.replaceAll("-", "")}`;
}

export function simbriefDispatchUrl(flight: FlightForSimBrief) {
  const query = new URLSearchParams({
    orig: airportCode(flight.origin),
    dest: airportCode(flight.destination),
    type: "B736",
    basetype: "B736",
    airline: "WWW",
    fltnum: (flight.flight_number ?? flight.tracking_callsign).replace(/\D/g, "") || "1",
    callsign: flight.tracking_callsign,
    static_id: simbriefStaticId(flight.id),
    planformat: "lido",
    pounds: "1",
    maps: "1",
    navlog: "1",
    notams: "1",
    firnot: "1",
    stepclimbs: "1",
    flightrules: "i",
    flighttype: "s",
    pax: "AUTO",
    cargo: "AUTO",
  });
  if (flight.aircraft?.registration) query.set("reg", flight.aircraft.registration);
  if (flight.route_string) query.set("route", flight.route_string);
  if (flight.planned_altitude_ft) query.set("fl", String(Math.round(flight.planned_altitude_ft / 100)));
  return `https://dispatch.simbrief.com/options/custom?${query}`;
}

export function readSimBriefPayload(payload: Record<string, any>) {
  const minutes = Number(payload.times?.est_block ?? payload.times?.sched_block ?? 0) / 60;
  const directory = payload.links?.directory;
  const pdf = payload.files?.pdf?.link ?? payload.links?.pdf;
  return {
    route: payload.general?.route ?? null,
    cruise_altitude_ft: Number(payload.general?.initial_altitude ?? 0) || null,
    airac: payload.params?.airac ?? null,
    block_fuel: Number(payload.fuel?.plan_ramp ?? payload.fuel?.plan_block ?? 0) || null,
    trip_fuel: Number(payload.fuel?.enroute_burn ?? 0) || null,
    estimated_block_minutes: Number.isFinite(minutes) && minutes > 0 ? Math.round(minutes) : null,
    ofp_url: pdf ? `${directory ?? ""}${pdf}` : null,
  };
}
