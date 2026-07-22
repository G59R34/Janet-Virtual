import {createClient} from "@supabase/supabase-js";

export type PublicMovement={id:string;callsign:string;origin:string;destination:string;departure:string;arrival:string|null;status:string;aircraft:string|null};
export type PublicPosition={flightId:string;callsign:string;latitude:number;longitude:number;altitude:number;heading:number;groundSpeed:number;recordedAt:string;origin:string;destination:string;aircraft:string|null};
export type PublicStation={id:string;code:string;label:string;latitude:number;longitude:number};
export type PublicRoute={id:string;origin:[number,number];destination:[number,number]};
export type PublicAircraft={id:string;registration:string;fleetNumber:string|null;typeCode:string;typeName:string;status:string;location:string;hours:number;cycles:number;capacity:number};
export type PublicStationActivity={id:string;code:string;label:string;departures:number;arrivals:number};
export type PublicOperationsSnapshot={generatedAt:string;feedAvailable:boolean;positionDelayMinutes:number;movements:PublicMovement[];positions:PublicPosition[];stations:PublicStation[];routes:PublicRoute[];fleet:PublicAircraft[];stationActivity:PublicStationActivity[];metrics:{activeFlights:number;pilotsOnline:number;todayMovements:number;fleetSize:number;stations:number;routes:number;completedFlights:number;flightHours:number;activePilots:number;onTimeRate:number}};

type RpcSnapshot={generated_at?:string;position_delay_minutes?:number;movements?:Record<string,unknown>[];positions?:Record<string,unknown>[];fleet?:Record<string,unknown>[];station_activity?:Record<string,unknown>[];metrics?:Record<string,unknown>};
type RpcNetworkMap={stations?:Record<string,unknown>[];routes?:Record<string,unknown>[]};

function publicClient(){
 const url=process.env.NEXT_PUBLIC_SUPABASE_URL;const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY??process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
 if(!url||!key)return null;
 return createClient(url,key,{auth:{persistSession:false,autoRefreshToken:false}});
}

const text=(value:unknown,fallback="—")=>typeof value==="string"&&value.length?value:fallback;
const number=(value:unknown,fallback=0)=>typeof value==="number"&&Number.isFinite(value)?value:fallback;

export async function getPublicOperations():Promise<PublicOperationsSnapshot>{
 const generatedAt=new Date().toISOString();const db=publicClient();
 const empty:PublicOperationsSnapshot={generatedAt,feedAvailable:false,positionDelayMinutes:0,movements:[],positions:[],stations:[],routes:[],fleet:[],stationActivity:[],metrics:{activeFlights:0,pilotsOnline:0,todayMovements:0,fleetSize:0,stations:0,routes:0,completedFlights:0,flightHours:0,activePilots:0,onTimeRate:0}};
 if(!db)return empty;
 const [{data:rpcData,error:rpcError},{data:networkData},{data:stationRows},{data:routeRows}]=await Promise.all([
  db.rpc("get_public_operations_snapshot"),
  db.rpc("get_public_network_map"),
  db.from("airports").select("id,icao,iata,local_code,display_label,name,latitude,longitude").eq("public_visibility",true).eq("active",true),
  db.from("routes").select("id,origin:airports!routes_origin_airport_id_fkey(latitude,longitude),destination:airports!routes_destination_airport_id_fkey(latitude,longitude)").eq("public_visibility",true).eq("active",true),
 ]);
 const raw=(rpcData??{}) as RpcSnapshot;
 const movements=(raw.movements??[]).map((row):PublicMovement=>({id:text(row.id),callsign:text(row.callsign,"JANET"),origin:text(row.origin),destination:text(row.destination),departure:text(row.departure,generatedAt),arrival:typeof row.arrival==="string"?row.arrival:null,status:text(row.status,"scheduled"),aircraft:typeof row.aircraft==="string"?row.aircraft:null}));
 const positions=(raw.positions??[]).map((row):PublicPosition=>({flightId:text(row.flight_id),callsign:text(row.callsign,"JANET"),latitude:number(row.latitude),longitude:number(row.longitude),altitude:number(row.altitude),heading:number(row.heading),groundSpeed:number(row.ground_speed),recordedAt:text(row.recorded_at,generatedAt),origin:text(row.origin),destination:text(row.destination),aircraft:typeof row.aircraft==="string"?row.aircraft:null})).filter(p=>Number.isFinite(p.latitude)&&Number.isFinite(p.longitude));
 const fleet=(raw.fleet??[]).map((row):PublicAircraft=>({id:text(row.id),registration:text(row.registration),fleetNumber:typeof row.fleet_number==="string"?row.fleet_number:null,typeCode:text(row.type_code),typeName:text(row.type_name),status:text(row.status),location:text(row.location),hours:number(row.hours),cycles:number(row.cycles),capacity:number(row.capacity)}));
 const stationActivity=(raw.station_activity??[]).map((row):PublicStationActivity=>({id:text(row.id),code:text(row.code),label:text(row.label),departures:number(row.departures),arrivals:number(row.arrivals)}));
 const network=(networkData??{}) as RpcNetworkMap;
 const stations=network.stations?.map((row):PublicStation=>({id:text(row.id),code:text(row.code,"STN"),label:text(row.label),latitude:number(row.latitude),longitude:number(row.longitude)}))??(stationRows??[]).map(row=>({id:row.id,code:row.local_code??row.iata??row.icao??"",label:row.display_label??row.name,latitude:Number(row.latitude),longitude:Number(row.longitude)}));
 const routes=network.routes?.map((row):PublicRoute=>({id:text(row.id),origin:[number(row.origin_longitude),number(row.origin_latitude)],destination:[number(row.destination_longitude),number(row.destination_latitude)]})).filter(route=>route.origin.every(Number.isFinite)&&route.destination.every(Number.isFinite))??(routeRows??[]).map(row=>{const origin=row.origin as unknown as {latitude:number;longitude:number}|null;const destination=row.destination as unknown as {latitude:number;longitude:number}|null;return {id:row.id,origin:[Number(origin?.longitude),Number(origin?.latitude)] as [number,number],destination:[Number(destination?.longitude),Number(destination?.latitude)] as [number,number]}}).filter(route=>route.origin.every(Number.isFinite)&&route.destination.every(Number.isFinite));
 const metrics=raw.metrics??{};
 return {generatedAt:text(raw.generated_at,generatedAt),feedAvailable:!rpcError,positionDelayMinutes:number(raw.position_delay_minutes,0),movements,positions,stations,routes,fleet,stationActivity,metrics:{activeFlights:number(metrics.active_flights),pilotsOnline:number(metrics.pilots_online),todayMovements:number(metrics.today_movements,movements.length),fleetSize:number(metrics.fleet_size),stations:number(metrics.stations,stations.length),routes:number(metrics.routes,routes.length),completedFlights:number(metrics.completed_flights),flightHours:number(metrics.flight_hours),activePilots:number(metrics.active_pilots),onTimeRate:number(metrics.on_time_rate)}};
}
