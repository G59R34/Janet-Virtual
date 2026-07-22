import {z} from "zod";
export const acarsStartSchema=z.object({flightId:z.uuid(),aircraftId:z.uuid(),simulator:z.string().min(2).max(80),clientVersion:z.string().max(30)});
export const telemetrySchema=z.object({sessionId:z.uuid(),latitude:z.number().gte(-90).lte(90),longitude:z.number().gte(-180).lte(180),altitude:z.number().int(),heading:z.number().gte(0).lt(360),groundSpeed:z.number().nonnegative(),verticalSpeed:z.number(),fuel:z.number().nonnegative(),onGround:z.boolean(),payload:z.record(z.string(),z.unknown()).optional()});
export const acarsCompleteSchema=z.object({remarks:z.string().trim().max(2000).optional()});
export const pirepSchema=z.object({flightId:z.uuid(),aircraftId:z.uuid(),simulator:z.string(),addon:z.string().optional(),blockMinutes:z.number().int().positive(),flightMinutes:z.number().int().positive(),fuelUsed:z.number().nonnegative(),landingRate:z.number().int().optional(),routeFlown:z.string(),remarks:z.string().max(2000).optional(),detectedViolations:z.array(z.string()).default([])});
export const scheduleTemplateUpdateSchema=z.object({id:z.uuid(),active:z.boolean().optional(),operationProbability:z.number().min(0).max(1).optional(),variabilityMinutes:z.number().int().min(0).max(180).optional()}).refine(v=>v.active!==undefined||v.operationProbability!==undefined||v.variabilityMinutes!==undefined,"No update supplied");
export const flightCreateSchema=z.object({originCode:z.string().trim().toUpperCase().regex(/^[A-Z0-9]{2,8}$/),destinationCode:z.string().trim().toUpperCase().regex(/^[A-Z0-9]{2,8}$/)}).refine(v=>v.originCode!==v.destinationCode,{message:"Origin and destination must differ",path:["destinationCode"]});
export const flightReservationSchema=z.object({flightId:z.uuid(),position:z.enum(["captain","first_officer"])});
export const assignmentDropSchema=z.object({assignmentId:z.uuid(),reason:z.string().trim().min(3).max(300)});
export const profileUpdateSchema=z.object({displayName:z.string().trim().min(2).max(80),timezone:z.string().trim().min(1).max(80),homeBaseId:z.uuid().nullable(),vatsimCid:z.union([z.string().trim().regex(/^\d{1,12}$/),z.literal("")]).transform(value=>value||null),ivaoId:z.union([z.string().trim().regex(/^\d{1,12}$/),z.literal("")]).transform(value=>value||null),simbriefPilotId:z.union([z.string().trim().regex(/^\d{1,12}$/),z.literal("")]).transform(value=>value||null),bio:z.string().trim().max(600).transform(value=>value||null),publicProfile:z.boolean()});
export const flightBoardDeleteSchema=z.object({flightId:z.uuid(),reason:z.string().trim().min(3).max(300).default("Removed from flight board by administrator")});
export const adminActionSchema=z.discriminatedUnion("action",[
 z.object({action:z.literal("review_application"),applicationId:z.uuid(),status:z.enum(["approved","rejected","waitlisted"]),notes:z.string().max(2000).optional()}),
 z.object({action:z.literal("review_pirep"),pirepId:z.uuid(),status:z.enum(["accepted","rejected"]),notes:z.string().min(3).max(2000)}),
 z.object({action:z.literal("set_status"),userId:z.uuid(),status:z.enum(["active","suspended","leave","terminated"]),reason:z.string().min(3).max(500)}),
 z.object({action:z.literal("grant_role"),userId:z.uuid(),role:z.enum(["applicant","pilot","captain","instructor","dispatcher","maintenance_controller","fleet_manager","chief_pilot","operations_manager","owner","system_administrator"]),expiresAt:z.iso.datetime().nullable().optional()}),
 z.object({action:z.literal("issue_qualification"),userId:z.uuid(),qualificationId:z.uuid(),expiresAt:z.iso.datetime().nullable().optional()}),
 z.object({action:z.literal("assign_crew"),flightId:z.uuid(),userId:z.uuid(),position:z.enum(["captain","first_officer","observer","instructor"])})
]);
