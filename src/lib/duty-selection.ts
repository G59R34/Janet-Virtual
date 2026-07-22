export type DashboardFlight={tracking_callsign:string;scheduled_departure:string;scheduled_arrival:string;status:string;origin:{local_code:string}|null;destination:{local_code:string}|null};
export type DashboardAssignment={status:string;flight:DashboardFlight|null};
const terminalFlightStatuses=new Set(["cancelled","completed","pirep_pending"]);

export function selectNextDuty(assignments:DashboardAssignment[],now=new Date()){const recentCutoff=now.getTime()-6*60*60*1000;return assignments.map(item=>item.flight).filter((flight):flight is DashboardFlight=>Boolean(flight)&&!terminalFlightStatuses.has(flight.status)&&new Date(flight.scheduled_arrival).getTime()>=recentCutoff).sort((a,b)=>new Date(a.scheduled_departure).getTime()-new Date(b.scheduled_departure).getTime())[0]??null}
