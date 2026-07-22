import {createClient} from "@/lib/supabase/server";
import {FlightCreateForm} from "@/components/flight-create-form";
import {CrewAssignmentPanel} from "@/components/crew-assignment-panel";
import {OperationsDashboard} from "@/components/operations-dashboard";
import {ScheduleAutomationPanel} from "@/components/schedule-automation-panel";

export async function FlightManager(){
 const db=await createClient();
 const [{data:airports},{data:aircraft},{data:flights},{data:crew}]=await Promise.all([
  db.from("airports").select("id,icao,iata,local_code,name").eq("active",true).order("local_code"),
  db.from("aircraft").select("id,registration,status").eq("active",true).in("status",["available","assigned"]),
  db.from("flights").select("id,tracking_callsign,scheduled_departure").in("status",["generated","awaiting_dispatch","released","crew_assigned"]).order("scheduled_departure").limit(50),
  db.from("profiles").select("id,employee_number,display_name").eq("status","active").order("display_name"),
 ]);
 return <><ScheduleAutomationPanel/><section className="panel"><h2>Assign qualified crew</h2>{flights?.length&&crew?.length?<CrewAssignmentPanel flights={flights.map(x=>({id:x.id,label:`${x.tracking_callsign} · ${new Date(x.scheduled_departure).toLocaleString()}`}))} crew={crew.map(x=>({id:x.id,label:`${x.employee_number} · ${x.display_name}`}))}/>:<div className="empty-state"><strong>No assignable flight or active crew records.</strong><p>Run schedule generation and approve at least one employee first.</p></div>}</section><details className="manual-flight"><summary>Create exceptional or special flight</summary><div><p>Use any ICAO, IATA, FAA, or simulator airport code. SimBrief will recommend a route when the route field is blank.</p><FlightCreateForm airports={(airports??[]).map(x=>({id:x.id,code:x.icao??x.iata??x.local_code??"",label:`${x.icao??x.iata??x.local_code} · ${x.name}`}))} aircraft={(aircraft??[]).map(x=>({id:x.id,label:`${x.registration} · ${x.status}`}))}/></div></details><OperationsDashboard/></>;
}
