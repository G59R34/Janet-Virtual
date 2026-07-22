import {describe,expect,it} from "vitest";
import {voiceRequestSchema} from "./voice-validation";

describe("tactical voice protocol validation",()=>{
  it("accepts versioned signaling commands with replay sequence context",()=>{
    expect(voiceRequestSchema.safeParse({action:"signal",roomId:"9f7d5dd6-8e92-4ec7-a65d-f5a981849e75",credential:"a".repeat(64),sequence:1,type:"radio.signal.offer",recipientId:"706a6c32-72d6-4ef2-a73e-649373ace69e",payload:{sdp:"offer"}}).success).toBe(true);
  });
  it("rejects unsupported messages and stale sequence zero",()=>{
    expect(voiceRequestSchema.safeParse({action:"signal",roomId:"9f7d5dd6-8e92-4ec7-a65d-f5a981849e75",credential:"a".repeat(64),sequence:0,type:"radio.room.create",payload:{}}).success).toBe(false);
  });
  it("does not resolve membership from displayed frequency",()=>{
    expect(voiceRequestSchema.safeParse({action:"join",frequency:"343.700",transportMode:"automatic"}).success).toBe(false);
  });
  it("rejects relay modes and accepts direct-only operation",()=>{
    expect(voiceRequestSchema.safeParse({action:"join",acarsSessionId:"9f7d5dd6-8e92-4ec7-a65d-f5a981849e75",transportMode:"relay-only"}).success).toBe(false);
    expect(voiceRequestSchema.safeParse({action:"join",acarsSessionId:"9f7d5dd6-8e92-4ec7-a65d-f5a981849e75",transportMode:"direct-preferred"}).success).toBe(true);
  });
});
