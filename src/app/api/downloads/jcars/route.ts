import { createClient as createSupabaseClient } from "@supabase/supabase-js";
import { getViewer } from "@/lib/auth";
import { isJCarsArtifact, jcarsDownload } from "@/lib/crew-downloads";

function storageAdminClient() {
  const url = process.env.NEXT_PUBLIC_SUPABASE_URL;
  const serviceRoleKey = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !serviceRoleKey) throw new Error("Supabase download storage is not configured");
  return createSupabaseClient(url, serviceRoleKey, { auth: { autoRefreshToken: false, persistSession: false } });
}

export async function GET(request: Request) {
  const viewer = await getViewer();
  if (!viewer) return Response.json({ error: "Sign in to download JCars" }, { status: 401 });
  const format = new URL(request.url).searchParams.get("format") ?? "exe";
  if (!isJCarsArtifact(format)) return Response.json({ error: "Unknown JCars installer format" }, { status: 400 });
  try {
    const artifact = jcarsDownload.artifacts[format];
    const { data, error } = await storageAdminClient().storage.from("crew-downloads").createSignedUrl(artifact.path, 300, { download: artifact.name });
    if (error || !data?.signedUrl) {
      console.error("Unable to create JCars download URL", error);
      return Response.json({ error: "JCars is not available for download yet" }, { status: 503 });
    }
    return Response.redirect(data.signedUrl, 302);
  } catch (error) {
    console.error("Unable to initialize JCars download storage", error);
    return Response.json({ error: "JCars download storage is not configured" }, { status: 503 });
  }
}
