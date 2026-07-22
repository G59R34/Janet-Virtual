import Link from "next/link";
import {createClient} from "@/lib/supabase/server";
import {AssignmentRoster,FlightAssignment} from "@/components/assignment-roster";

export async function FlightAssignments({userId}:{userId:string}){
 const db=await createClient();
 const {data,error}=await db.from("crew_assignments").select("id,position,status,assigned_at,flight:flights!inner(id,tracking_callsign,flight_number,scheduled_departure,scheduled_arrival,planned_altitude_ft,route_string,status,passenger_count,origin:airports!flights_origin_airport_id_fkey(local_code,display_label),destination:airports!flights_destination_airport_id_fkey(local_code,display_label),departure_stand:airport_stands!flights_departure_stand_id_fkey(code,name),arrival_stand:airport_stands!flights_arrival_stand_id_fkey(code,name),aircraft(id,registration))").eq("user_id",userId).in("status",["assigned","accepted"]).order("assigned_at",{ascending:false});
 return <div className="assignment-board"><section className="assignment-hero"><div><span className="kicker">CREW DUTY ROSTER</span><h2>Your assigned flights</h2><p>Trips claimed from the pickup board appear here and sync automatically to JCars.</p></div><Link className="button primary" href="/crew/flights">PICK UP ANOTHER FLIGHT</Link></section>{error?<div className="notice"><strong>Assignments unavailable.</strong><p>{error.message}</p></div>:<AssignmentRoster assignments={(data??[]) as unknown as FlightAssignment[]}/>}</div>
}
