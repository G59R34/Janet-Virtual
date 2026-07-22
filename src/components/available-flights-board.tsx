import {createClient} from "@/lib/supabase/server";
import {AvailableFlightsTable,AvailableFlight} from "@/components/available-flights-table";

export async function AvailableFlightsBoard({userId,roles}:{userId:string;roles:string[]}){
 const db=await createClient();
 const [{data,error},{data:assignments}]=await Promise.all([
  db.from("flights").select("id,tracking_callsign,flight_number,scheduled_departure,scheduled_arrival,planned_altitude_ft,status,passenger_count,origin:airports!flights_origin_airport_id_fkey(local_code,display_label),destination:airports!flights_destination_airport_id_fkey(local_code,display_label),aircraft(registration),schedule_template:schedule_templates(name,aircraft_category)").in("status",["generated","awaiting_dispatch","released"]).order("scheduled_departure").limit(500),
  db.from("crew_assignments").select("flight_id,position,status").eq("user_id",userId).in("status",["assigned","accepted"])
 ]);
 const captainEligible=roles.some(role=>["captain","instructor","chief_pilot","owner","system_administrator"].includes(role));
 const canDeleteFlights=roles.some(role=>["operations_manager","owner","system_administrator"].includes(role));
 return <div className="pickup-board"><section className="pickup-hero"><div><span className="kicker">LIVE CREW MARKETPLACE</span><h2>Flight pickup board</h2><p>Generated JANET operations appear here automatically. Claim an open seat and the flight moves directly into your assignments and JCars.</p></div><div className="pickup-count"><b>{data?.length??0}</b><span>OPEN FLIGHTS</span></div></section>{error?<div className="notice"><strong>Flight board unavailable.</strong><p>{error.message}</p></div>:<AvailableFlightsTable flights={(data??[]) as unknown as AvailableFlight[]} assigned={(assignments??[]).map(a=>a.flight_id)} captainEligible={captainEligible} canDeleteFlights={canDeleteFlights}/>}</div>
}
