import {z} from "zod";

export const tacticalInstructionTypes=["taxi","hold_position","runway_crossing","line_up_wait","takeoff","landing","go_around","heading","altitude","speed","route","direct_to","hold","approach_assignment","range_entry","range_exit","operating_area","frequency_change","return_to_vatsim","squawk","advisory"] as const;
export const tacticalAcknowledgements=["wilco","roger","unable","standby","request_clarification"] as const;
export const tacticalOptInSchema=z.object({acarsSessionId:z.uuid(),safetyAccepted:z.literal(true)});
export const tacticalSuspendSchema=z.object({acarsSessionId:z.uuid(),reason:z.string().trim().max(300).optional()});
export const tacticalAckSchema=z.object({response:z.enum(tacticalAcknowledgements)});
export const jscopeSessionSchema=z.object({clientVersion:z.string().trim().min(1).max(40)});
export const positionClaimSchema=z.object({positionId:z.enum(["nellis_control","dreamland","groom_ground","groom_tower","tonopah_ground","tonopah_tower"]),safetyAccepted:z.literal(true)});
export const tacticalInstructionSchema=z.object({positionSessionId:z.uuid(),aircraftSessionId:z.uuid(),type:z.enum(tacticalInstructionTypes),parameters:z.record(z.string(),z.unknown()).default({}),text:z.string().trim().min(1).max(500),nonce:z.uuid()});
export const controllerAccessSchema=z.object({userId:z.uuid(),state:z.enum(["trainee","approved","instructor","suspended","revoked"]),callsign:z.string().trim().min(2).max(40),positionId:z.enum(["nellis_control","dreamland","groom_ground","groom_tower","tonopah_ground","tonopah_tower"]),level:z.enum(["observer","trainee","qualified","instructor"])});
