import { authenticateApiRequest } from "@/lib/supabase/api";
import { acarsStartSchema } from "@/lib/validation";
export async function POST(req: Request) {
  const { db, user } = await authenticateApiRequest(req);
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const parsed = acarsStartSchema.safeParse(await req.json());
  if (!parsed.success)
    return Response.json({ error: parsed.error.flatten() }, { status: 400 });
  const { flightId, aircraftId, simulator, clientVersion } = parsed.data;
  const { data, error } = await db.rpc("start_mandatory_acars_session", {
    p_flight_id: flightId,
    p_aircraft_id: aircraftId,
    p_simulator: simulator,
    p_client_version: clientVersion,
  });
  return Response.json(error ? { error: error.message } : data, {
    status: error ? 409 : 201,
  });
}
