/* eslint-disable @typescript-eslint/no-explicit-any */
import {authenticateApiRequest} from "@/lib/supabase/api";
import {simbriefDispatchUrl} from "@/lib/simbrief";
export async function GET(request:Request){
 const {db,user}=await authenticateApiRequest(request);if(!user)return Response.json({error:"Unauthorized"},{status:401});
 const {data,error}=await db.from("crew_assignments").select("id,position,flight:flights!inner(id,tracking_callsign,flight_number,scheduled_departure,scheduled_arrival,status,planned_altitude_ft,route_string,origin:airports!flights_origin_airport_id_fkey(icao,iata,local_code,display_label),destination:airports!flights_destination_airport_id_fkey(icao,iata,local_code,display_label),departure_stand:airport_stands!flights_departure_stand_id_fkey(code,name),arrival_stand:airport_stands!flights_arrival_stand_id_fkey(code,name),aircraft(id,registration),simbrief_plans(status,route,cruise_altitude_ft,block_fuel,trip_fuel,estimated_block_minutes,ofp_url,payload))").eq("user_id",user.id).in("status",["assigned","accepted"]).gte("flight.scheduled_arrival",new Date(Date.now()-6*60*60*1000).toISOString()).order("assigned_at");
 if(error)return Response.json({error:error.message},{status:400});
 const assignments=(data??[]).map((assignment:any)=>{const flight=assignment.flight;const plan=flight.simbrief_plans?.[0]??null;delete flight.simbrief_plans;const blank={status:"planning",route:null,cruise_altitude_ft:null,block_fuel:null,trip_fuel:null,estimated_block_minutes:null,ofp_url:null};return {...assignment,flight:{...flight,simbrief_plan:{...(plan??blank),dispatch_url:simbriefDispatchUrl(flight)}}}});
 return Response.json({assignments});
}
