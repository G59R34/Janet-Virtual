import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { requireApiRoles } from "@/lib/authorization";

function serviceClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;

  if (!url || !serviceRoleKey) {
    throw new Error("Supabase service-role credentials are not configured");
  }

  return createSupabaseClient(url, serviceRoleKey, {
    auth: { autoRefreshToken: false, persistSession: false },
  });
}

export async function DELETE(
  _request: Request,
  { params }: { params: Promise<{ userId: string }> },
) {
  const { user, error } = await requireApiRoles([
    "owner",
    "system_administrator",
  ]);
  if (error) return error;

  const { userId } = await params;
  if (!/^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i.test(userId)) {
    return Response.json({ error: "Invalid user identifier" }, { status: 400 });
  }
  if (user?.id === userId) {
    return Response.json(
      { error: "You cannot delete the account currently signed in" },
      { status: 400 },
    );
  }

  try {
    const { error: deleteError } = await serviceClient().auth.admin.deleteUser(
      userId,
    );
    if (deleteError) {
      console.error("Unable to delete Supabase auth user", deleteError);
      return Response.json(
        {
          error:
            "Unable to delete this account. Apply the account-deletion migration in Supabase, then try again.",
        },
        { status: 409 },
      );
    }
  } catch (deleteError) {
    console.error("Unable to initialize Supabase admin deletion", deleteError);
    return Response.json(
      { error: "Account deletion is not configured on this deployment" },
      { status: 503 },
    );
  }

  return Response.json({ deleted: true });
}
