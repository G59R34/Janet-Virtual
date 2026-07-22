import {getPublicOperations} from "@/lib/public-operations";

export const dynamic="force-dynamic";
export async function GET(){return Response.json(await getPublicOperations(),{headers:{"Cache-Control":"public, max-age=15, stale-while-revalidate=30"}})}
