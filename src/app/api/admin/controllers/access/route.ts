import { requireApiRoles } from "@/lib/authorization";
import { controllerAccessSchema } from "@/lib/tactical-validation";

export async function POST(request: Request) {
  const auth = await requireApiRoles(["owner", "system_administrator"]);
  if (auth.error) return auth.error;
  const parsed = controllerAccessSchema.safeParse(await request.json());
  if (!parsed.success)
    return Response.json({ error: parsed.error.flatten() }, { status: 400 });
  const input = parsed.data;
  const { data, error } = await auth.db.rpc("admin_set_controller_access", {
    p_user_id: input.userId,
    p_state: input.state,
    p_callsign: input.callsign,
    p_position_id: input.positionId,
    p_level: input.level,
  });
  if (error) {
    const missingRpc =
      error.code === "PGRST202" || error.message.includes("schema cache");
    return Response.json(
      {
        error: missingRpc
          ? "The controller-access database update is not installed. Apply migration 033, then try again."
          : error.message,
      },
      { status: missingRpc ? 503 : 409 },
    );
  }
  return Response.json(data);
}
