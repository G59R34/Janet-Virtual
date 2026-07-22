import Link from "next/link";
import {createClient} from "@/lib/supabase/server";
import {CalendarClock,Mail,ShieldCheck} from "lucide-react";
import {selectNextDuty,type DashboardAssignment} from "@/lib/duty-selection";
import {ProgressionOverview} from "@/components/progression-overview";

const activeAssignmentStatuses=["assigned","accepted"];

export async function CrewDashboard({userId}:{userId:string}){
 const db=await createClient();
 const [{count:assignments},{count:qualifications},{count:messages},{data:dutyRows}]=await Promise.all([
  db.from("crew_assignments").select("*",{count:"exact",head:true}).eq("user_id",userId).in("status",activeAssignmentStatuses),
  db.from("user_qualifications").select("*",{count:"exact",head:true}).eq("user_id",userId).eq("status","active"),
  db.from("notifications").select("*",{count:"exact",head:true}).eq("user_id",userId).is("read_at",null),
  db.from("crew_assignments").select("status,flight:flights!inner(tracking_callsign,scheduled_departure,scheduled_arrival,status,origin:airports!flights_origin_airport_id_fkey(local_code),destination:airports!flights_destination_airport_id_fkey(local_code))").eq("user_id",userId).in("status",activeAssignmentStatuses).limit(25),
 ]);
 const flight=selectNextDuty((dutyRows??[]) as unknown as DashboardAssignment[]);
 return <><section className="crew-hero"><div><span className="kicker">NEXT DUTY ASSIGNMENT</span>{flight?<><h2>{flight.tracking_callsign}</h2><p>{flight.origin?.local_code} → {flight.destination?.local_code} · {new Date(flight.scheduled_departure).toLocaleString()}</p><span className="badge enabled">{flight.status.toUpperCase()}</span></>:<><h2>No assignment scheduled</h2><p>Dispatch has not assigned your next operation.</p><Link href="/crew/flights" className="button">View available flights</Link></>}</div><div className="crew-report"><span>REPORT STATUS</span><b>{flight?"PENDING":"CLEAR"}</b><small>{flight?"Check release and briefing before duty.":"No active duty assignment."}</small></div></section><div className="crew-cards"><Link href="/crew/assignments"><CalendarClock/><span>ACTIVE ASSIGNMENTS</span><b>{assignments??0}</b><small>View duty schedule</small></Link><Link href="/crew/qualifications"><ShieldCheck/><span>QUALIFICATIONS</span><b>{qualifications??0}</b><small>Review currency</small></Link><Link href="/crew/messages"><Mail/><span>UNREAD MESSAGES</span><b>{messages??0}</b><small>Open communications</small></Link></div><ProgressionOverview userId={userId}/></>
}
