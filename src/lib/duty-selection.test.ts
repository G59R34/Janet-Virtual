import {describe,expect,it} from "vitest";
import {selectNextDuty} from "./duty-selection";

const flight=(callsign:string,departure:string,status="crew_assigned")=>({status:"assigned",flight:{tracking_callsign:callsign,scheduled_departure:departure,scheduled_arrival:new Date(new Date(departure).getTime()+90*60*1000).toISOString(),status,origin:{local_code:"STN9"},destination:{local_code:"STN7"}}});

describe("crew dashboard next duty",()=>{
 it("ignores terminal historical flights",()=>{const next=selectNextDuty([flight("JANET53","2026-07-22T15:15:00Z","pirep_pending"),flight("JANET570","2026-07-22T18:00:00Z")],new Date("2026-07-22T08:00:00Z"));expect(next?.tracking_callsign).toBe("JANET570")});
 it("chooses the earliest active duty",()=>{const next=selectNextDuty([flight("JANET22","2026-07-22T20:00:00Z"),flight("JANET11","2026-07-22T18:00:00Z")],new Date("2026-07-22T08:00:00Z"));expect(next?.tracking_callsign).toBe("JANET11")});
 it("returns no duty when only terminal flights remain",()=>{expect(selectNextDuty([flight("JANET53","2026-07-22T15:15:00Z","completed")],new Date("2026-07-22T08:00:00Z"))).toBeNull()});
});
