import {getPublicOperations} from "@/lib/public-operations";

export const dynamic="force-dynamic";
export async function GET(){return Response.json(await getPublicOperations(),{headers:{"Cache-Control":"no-store, max-age=0"}})}
