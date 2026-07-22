import {createClient} from "@supabase/supabase-js";
import type {Assignment,Snapshot} from "./types";
const supabaseUrl=(import.meta.env.VITE_SUPABASE_URL as string)||"https://invalid.local";
const publishableKey=(import.meta.env.VITE_SUPABASE_PUBLISHABLE_KEY as string)||"missing-public-key";
export const apiUrl=((import.meta.env.VITE_JVA_API_URL as string)||"http://localhost:3000").replace(/\/$/,"");
export const supabase=createClient(supabaseUrl,publishableKey,{auth:{persistSession:true,autoRefreshToken:true,detectSessionInUrl:false}});
async function token(){const {data}=await supabase.auth.getSession();if(!data.session)throw new Error("Not authenticated");return data.session.access_token}
async function request<T>(path:string,init?:RequestInit){let response:Response;try{response=await fetch(`${apiUrl}${path}`,{...init,headers:{"content-type":"application/json",authorization:`Bearer ${await token()}`,...init?.headers}})}catch{throw new Error(`Cannot reach the JVA website at ${apiUrl}. Make sure the website is running.`)}const body=await response.json();if(!response.ok)throw new Error(body.error??`Request failed (${response.status})`);return body as T}
export type ClientConfig={settings:{telemetry?:{interval_seconds?:number;offline_buffer_points?:number};behavior?:{assignment_refresh_seconds?:number;allow_autostart?:boolean};simulator?:{allowed?:string[];require_connection?:boolean}};versions:{version:string;minimum_supported:boolean;mandatory:boolean;download_url:string|null;release_notes:string|null}[]};
export type TripReport={pirepId:string;status:string;score:number;blockMinutes:number;flightMinutes:number;fuelUsed:number;landingRate:number|null;violations:string[]};
export const jvaApi={
 config:()=>request<ClientConfig>("/api/acars/config"),
 assignments:()=>request<{assignments:Assignment[]}>("/api/acars/assignments"),
 syncSimBrief:(flightId:string,pilotId:string)=>request<{plan:Assignment["flight"]["simbrief_plan"];dispatch_url:string}>("/api/acars/simbrief",{method:"POST",body:JSON.stringify({flightId,pilotId})}),
 startSession:(flightId:string,aircraftId:string,simulator:string)=>request<{id:string}>("/api/acars/sessions",{method:"POST",body:JSON.stringify({flightId,aircraftId,simulator,clientVersion:"0.3.1"})}),
 telemetry:(sessionId:string,s:Snapshot)=>request<{accepted:boolean;phase:string}>("/api/acars/telemetry",{method:"POST",body:JSON.stringify({sessionId,latitude:s.latitude,longitude:s.longitude,altitude:Math.round(s.altitude),heading:s.heading,groundSpeed:s.groundSpeed,verticalSpeed:s.verticalSpeed,fuel:s.fuel,onGround:s.onGround,payload:{provider:s.provider,engineState:s.engineState,parkingBrake:s.parkingBrake,gear:s.gear,flaps:s.flaps,paused:s.paused,simulatorTime:s.simulatorTime}})}),
 complete:(sessionId:string,remarks?:string)=>request<TripReport>(`/api/acars/sessions/${sessionId}/complete`,{method:"POST",body:JSON.stringify({remarks})}),
};
