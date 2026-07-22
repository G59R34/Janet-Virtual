import {authenticateApiRequest} from "@/lib/supabase/api";
import {jscopeSessionSchema} from "@/lib/tactical-validation";

export async function POST(request:Request){const {db,user}=await authenticateApiRequest(request);if(!user)return Response.json({error:"Unauthorized"},{status:401});const parsed=jscopeSessionSchema.safeParse(await request.json());if(!parsed.success)return Response.json({error:"Invalid JScope client version"},{status:400});const {data,error}=await db.rpc("open_jscope_session",{p_client_version:parsed.data.clientVersion});return Response.json(error?{error:error.message}:data,{status:error?403:201,headers:{"Cache-Control":"no-store"}})}
