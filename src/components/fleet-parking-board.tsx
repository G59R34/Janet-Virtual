import {MapPin,Plane} from "lucide-react";
import {createClient} from "@/lib/supabase/server";

type ParkedAircraft={
 id:string;registration:string;fleet_number:string|null;status:string;
 airport:{local_code:string;display_label:string|null}|null;
 stand:{code:string;name:string;data_source:string}|null;
};

export async function FleetParkingBoard(){
 const db=await createClient();
 const {data,error}=await db.from("aircraft").select("id,registration,fleet_number,status,airport:airports!aircraft_current_airport_id_fkey(local_code,display_label),stand:airport_stands!aircraft_current_stand_id_fkey(code,name,data_source)").eq("active",true).order("fleet_number");
 const aircraft=(data??[]) as unknown as ParkedAircraft[];
 const parked=aircraft.filter(item=>item.stand).length;
 return <div className="module-view"><section className="module-intro"><div className="module-icon"><MapPin size={22}/></div><div><span className="kicker">GROUND OPERATIONS</span><h2>Fleet parking</h2><p>Authoritative airfield and stand position for every active aircraft. A blank stand means the aircraft is off-block or airborne.</p></div></section><div className="cards"><div className="card"><span>ACTIVE AIRCRAFT</span><b>{aircraft.length.toString().padStart(2,"0")}</b><small>fleet registry</small></div><div className="card"><span>ON STAND</span><b>{parked.toString().padStart(2,"0")}</b><small>exact ground position</small></div><div className="card"><span>IN TRANSIT</span><b>{(aircraft.length-parked).toString().padStart(2,"0")}</b><small>off-block or airborne</small></div><div className="card"><span>DATA STATUS</span><b>{error?"ERR":"LIVE"}</b><small>{error?"query unavailable":"stand tracking active"}</small></div></div><section className="panel"><h2><Plane size={17}/> Aircraft positions</h2>{error?<div className="notice"><strong>Fleet parking unavailable.</strong><p>{error.message}</p></div>:<div className="flight-table"><div className="tr th"><span>TAIL</span><span>AIRFIELD</span><span>PARKING STAND</span><span>SOURCE</span><span>STATUS</span></div>{aircraft.map(item=><div className="tr" key={item.id}><strong>{item.registration}</strong><span>{item.airport?.local_code??"IN TRANSIT"}</span><span>{item.stand?`${item.stand.code} · ${item.stand.name}`:"OFF STAND"}</span><span>{item.stand?.data_source.replaceAll("_"," ").toUpperCase()??"TELEMETRY"}</span><span className={`status ${item.status}`}>{item.status.replaceAll("_"," ").toUpperCase()}</span></div>)}</div>}</section></div>;
}
