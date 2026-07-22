import { AccessToken, type VideoGrant } from "livekit-server-sdk";

export type CentralVoiceGrant = {
  mode: "central";
  url: string;
  token: string;
  roomName: string;
  expiresIn: number;
};

type RadioGrant = {
  roomId: string;
  operationId: string;
  subjectId: string;
};

function configuredVoiceServer() {
  const url = process.env.JVA_VOICE_URL?.replace(/\/$/, "");
  const apiKey = process.env.JVA_VOICE_API_KEY;
  const apiSecret = process.env.JVA_VOICE_API_SECRET;
  if (!url || !apiKey || !apiSecret) return null;
  if (!/^wss:\/\//.test(url) && process.env.NODE_ENV === "production") return null;
  return { url, apiKey, apiSecret };
}

export function centralVoiceConfigured() {
  return configuredVoiceServer() !== null;
}

export async function createCentralVoiceGrant(
  radio: RadioGrant,
  role: "controller" | "pilot",
): Promise<CentralVoiceGrant> {
  const config = configuredVoiceServer();
  if (!config) throw new Error("Central JVA voice server is not configured");

  const roomName = `jva-${radio.operationId}`;
  const token = new AccessToken(config.apiKey, config.apiSecret, {
    identity: radio.subjectId,
    name: role === "controller" ? "JScope controller" : "JCars pilot",
    metadata: JSON.stringify({ roomId: radio.roomId, role }),
    ttl: 300,
  });
  const grant: VideoGrant = {
    room: roomName,
    roomJoin: true,
    canPublish: true,
    canSubscribe: true,
    canPublishData: false,
  };
  token.addGrant(grant);

  return {
    mode: "central",
    url: config.url,
    token: await token.toJwt(),
    roomName,
    expiresIn: 300,
  };
}
