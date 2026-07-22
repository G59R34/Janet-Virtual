import {authenticateApiRequest} from "@/lib/supabase/api";
import {centralVoiceConfigured,createCentralVoiceGrant} from "@/lib/voice-central";
import {voiceRequestSchema} from "@/lib/voice-validation";

export const runtime="nodejs";

export async function POST(request:Request){
  const {db,user}=await authenticateApiRequest(request);
  if(!user)return Response.json({error:"Unauthorized"},{status:401});
  const parsed=voiceRequestSchema.safeParse(await request.json());
  if(!parsed.success)return Response.json({error:parsed.error.flatten()},{status:400});
  const input=parsed.data;
  if((input.action==="host"||input.action==="join")&&!centralVoiceConfigured()){
    return Response.json({error:"Central JVA voice server is not configured"},{status:503});
  }
  let result:{data:unknown;error:{message:string}|null};
  if(input.action==="host"){
    const token=request.headers.get("x-jscope-session");
    if(!token)return Response.json({error:"JScope session required"},{status:401});
    result=await db.rpc("open_voice_room",{p_token:token,p_position_session_id:input.positionSessionId,p_transport_mode:input.transportMode});
  }else if(input.action==="join"){
    result=await db.rpc("join_voice_room",{p_acars_session_id:input.acarsSessionId,p_transport_mode:input.transportMode});
  }else if(input.action==="signal"){
    result=await db.rpc("voice_command",{p_credential:input.credential,p_room_id:input.roomId,p_sequence:input.sequence,p_event_type:input.type,p_recipient_id:input.recipientId,p_payload:input.payload});
  }else if(input.action==="poll"){
    result=await db.rpc("poll_voice_events",{p_credential:input.credential,p_room_id:input.roomId,p_after:input.after});
  }else{
    const token=request.headers.get("x-jscope-session");
    if(!token)return Response.json({error:"JScope session required"},{status:401});
    result=await db.rpc("close_voice_room",{p_token:token,p_position_session_id:input.positionSessionId});
  }
  if(result.error)return Response.json({error:result.error.message},{status:409});
  const addIce=input.action==="host"||input.action==="join";
  if(addIce){
    const radio=result.data as {roomId:string;operationId:string;subjectId:string};
    const central=await createCentralVoiceGrant(radio,input.action==="host"?"controller":"pilot");
    return Response.json({radio,central},{status:201});
  }
  return Response.json(result.data,{status:200});
}
