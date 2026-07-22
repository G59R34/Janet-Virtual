/* eslint-disable @typescript-eslint/no-explicit-any */
import {createClient} from "@/lib/supabase/server";
import {MapboxNetworkMap} from "@/components/mapbox-network-map";

export async function NetworkMap(){
 const db=await createClient();
 const [{data:stations},{data:routes}]=await Promise.all([
  db.from("airports").select("id,icao,iata,local_code,display_label,name,latitude,longitude").eq("public_visibility",true).eq("active",true),
  db.from("routes").select("id,origin:airports!routes_origin_airport_id_fkey(latitude,longitude),destination:airports!routes_destination_airport_id_fkey(latitude,longitude)").eq("public_visibility",true).eq("active",true),
 ]);
 return <section className="map-panel"><MapboxNetworkMap token={process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN??""} stations={(stations??[]).map(s=>({id:s.id,code:s.icao??s.iata??s.local_code??"",label:s.display_label??s.name,latitude:Number(s.latitude),longitude:Number(s.longitude)}))} routes={(routes??[]).map((r:any)=>({id:r.id,origin:[Number(r.origin?.longitude),Number(r.origin?.latitude)] as [number,number],destination:[Number(r.destination?.longitude),Number(r.destination?.latitude)] as [number,number]})).filter(r=>r.origin.every(Number.isFinite)&&r.destination.every(Number.isFinite))}/><aside><span className="kicker">PUBLIC POSITION POLICY</span><h2>Geographic network view</h2><p>Airport markers use their actual database coordinates. Public route corridors are geographic; aircraft positions remain delayed or withheld according to operations policy.</p><div className="legend"><span><i className="dot station"/> Public airport</span><span><i className="dot route"/> Scheduled corridor</span></div></aside></section>
}
