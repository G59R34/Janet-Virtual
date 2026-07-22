import {createClient} from "@/lib/supabase/server";

export async function GET(){
 const db=await createClient();
 const {data:{user}}=await db.auth.getUser();
 if(!user)return Response.json({error:"Unauthorized"},{status:401});
 const {data,error}=await db.from("flights").select("id,tracking_callsign,flight_number,scheduled_departure,scheduled_arrival,planned_altitude_ft,status,passenger_count,origin:airports!flights_origin_airport_id_fkey(local_code,display_label),destination:airports!flights_destination_airport_id_fkey(local_code,display_label),departure_stand:airport_stands!flights_departure_stand_id_fkey(code),arrival_stand:airport_stands!flights_arrival_stand_id_fkey(code),aircraft(registration),schedule_template:schedule_templates(name,aircraft_category)").in("status",["generated","awaiting_dispatch","released"]).not("aircraft_id","is",null).gt("scheduled_arrival",new Date().toISOString()).order("scheduled_departure").limit(100);
 return Response.json(error?{error:error.message}:{flights:data??[]},{status:error?400:200,headers:{"Cache-Control":"no-store"}});
}
