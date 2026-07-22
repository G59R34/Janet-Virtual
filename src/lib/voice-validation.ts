import {z} from "zod";

export const iceTransportMode=z.literal("direct-preferred");
const signalType=z.enum(["radio.signal.offer","radio.signal.answer","radio.signal.ice_candidate","radio.connection.state","radio.ptt.start","radio.ptt.stop","radio.member.leave"]);
export const voiceRequestSchema=z.discriminatedUnion("action",[
  z.object({action:z.literal("host"),positionSessionId:z.uuid(),transportMode:iceTransportMode.default("direct-preferred")}),
  z.object({action:z.literal("join"),acarsSessionId:z.uuid(),transportMode:iceTransportMode.default("direct-preferred")}),
  z.object({action:z.literal("signal"),roomId:z.uuid(),credential:z.string().min(32).max(256),sequence:z.number().int().positive(),type:signalType,recipientId:z.uuid().nullable().default(null),payload:z.record(z.string(),z.unknown()).default({})}),
  z.object({action:z.literal("poll"),roomId:z.uuid(),credential:z.string().min(32).max(256),after:z.number().int().nonnegative().default(0)}),
  z.object({action:z.literal("close"),positionSessionId:z.uuid()}),
]);
