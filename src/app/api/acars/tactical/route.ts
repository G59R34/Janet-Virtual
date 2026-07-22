import { authenticateApiRequest } from "@/lib/supabase/api";
import { tacticalOptInSchema } from "@/lib/tactical-validation";

export async function GET(request: Request) {
  const { db, user } = await authenticateApiRequest(request);
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const sessionId = new URL(request.url).searchParams.get("acarsSessionId");
  if (!sessionId)
    return Response.json(
      { error: "acarsSessionId is required" },
      { status: 400 },
    );
  const { data, error } = await db.rpc("get_pilot_tactical_state", {
    p_acars_session_id: sessionId,
  });
  return Response.json(error ? { error: error.message } : { state: data }, {
    status: error ? 400 : 200,
    headers: { "Cache-Control": "no-store" },
  });
}
export async function POST(request: Request) {
  const { db, user } = await authenticateApiRequest(request);
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 });
  const parsed = tacticalOptInSchema.safeParse(await request.json());
  if (!parsed.success)
    return Response.json(
      { error: "Active JCars session and safety acceptance are required" },
      { status: 400 },
    );
  const { data, error } = await db.rpc("opt_in_tactical_control", {
    p_acars_session_id: parsed.data.acarsSessionId,
    p_safety_accepted: true,
  });
  return Response.json(error ? { error: error.message } : data, {
    status: error ? 409 : 201,
  });
}
export async function DELETE(request: Request) {
  const { user } = await authenticateApiRequest(request);
  if (!user) return Response.json({ error: "Unauthorized" }, { status: 401 });
  return Response.json(
    { error: "ATC participation is mandatory while JCars tracking is active" },
    { status: 403 },
  );
}
