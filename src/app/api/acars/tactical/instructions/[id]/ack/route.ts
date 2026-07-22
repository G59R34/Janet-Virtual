import {authenticateApiRequest} from "@/lib/supabase/api";
import {tacticalAckSchema} from "@/lib/tactical-validation";

export async function POST(request:Request,{params}:{params:Promise<{id:string}>}){const [{id},{db,user}]=await Promise.all([params,authenticateApiRequest(request)]);if(!user)return Response.json({error:"Unauthorized"},{status:401});const parsed=tacticalAckSchema.safeParse(await request.json());if(!parsed.success)return Response.json({error:"Invalid acknowledgement"},{status:400});const {data,error}=await db.rpc("acknowledge_tactical_instruction",{p_instruction_id:id,p_response:parsed.data.response});return Response.json(error?{error:error.message}:data,{status:error?409:200})}
