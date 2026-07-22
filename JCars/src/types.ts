export type SimBriefPlan = {
  status: string;
  route: string | null;
  cruise_altitude_ft: number | null;
  block_fuel: number | null;
  trip_fuel: number | null;
  estimated_block_minutes: number | null;
  ofp_url: string | null;
  dispatch_url: string;
};
export type Assignment = {
  id: string;
  position: string;
  flight: {
    id: string;
    tracking_callsign: string;
    flight_number: string;
    scheduled_departure: string;
    scheduled_arrival: string;
    status: string;
    origin: { local_code: string; display_label: string };
    destination: { local_code: string; display_label: string };
    aircraft: { id: string; registration: string } | null;
    simbrief_plan: SimBriefPlan;
  };
};
export type Snapshot = {
  connected: boolean;
  provider: string;
  latitude: number;
  longitude: number;
  altitude: number;
  heading: number;
  groundSpeed: number;
  verticalSpeed: number;
  fuel: number;
  onGround: boolean;
  engineState: boolean;
  parkingBrake: boolean;
  gear: number;
  flaps: number;
  paused: boolean;
  simulatorTime: string;
  com1Active: number;
  com1Standby: number;
  com2Active: number;
  com2Standby: number;
  transponderCode: number;
};
export type TrackingState =
  "idle" | "starting" | "tracking" | "stopping" | "error";
export type TacticalInstruction = {
  id: string;
  type: string;
  text: string;
  parameters: Record<string, unknown>;
  issuedAt: string;
  status: string;
  acknowledgement: string | null;
};
export type TacticalState = {
  session: {
    id: string;
    status: string;
    positionId: string;
    positionName: string;
    controllerCallsign: string;
    displayFrequency: string;
    channelId: string;
    voiceState: string;
    suspensionReason: string | null;
  };
  instructions: TacticalInstruction[];
};
