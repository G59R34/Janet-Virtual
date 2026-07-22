import {authenticateApiRequest} from "@/lib/supabase/api";

export async function GET(request:Request){const {db,user}=await authenticateApiRequest(request);if(!user)return Response.json({error:"Unauthorized"},{status:401});const token=request.headers.get("x-jscope-session");if(!token)return Response.json({error:"JScope session required"},{status:401});const {data,error}=await db.rpc("get_jscope_snapshot",{p_token:token});return Response.json(error?{error:error.message}:data,{status:error?403:200,headers:{"Cache-Control":"no-store"}})}
