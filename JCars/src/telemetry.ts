import { invoke } from "@tauri-apps/api/core";
import type { Snapshot } from "./types";
const isTauri = () => "__TAURI_INTERNALS__" in window;
export async function readSnapshot(): Promise<Snapshot> {
  if (isTauri()) return invoke<Snapshot>("read_simulator_snapshot");
  return {
    connected: false,
    provider: "Browser preview",
    latitude: 0,
    longitude: 0,
    altitude: 0,
    heading: 0,
    groundSpeed: 0,
    verticalSpeed: 0,
    fuel: 0,
    onGround: true,
    engineState: false,
    parkingBrake: true,
    gear: 1,
    flaps: 0,
    paused: false,
    simulatorTime: new Date().toISOString(),
    com1Active: 0,
    com1Standby: 0,
    com2Active: 0,
    com2Standby: 0,
    transponderCode: 0,
  };
}

export function readTestSnapshot(): Snapshot {
  return {
    connected: true,
    provider: "JCars Test Mode · KXTA synthetic aircraft",
    latitude: 37.233022222,
    longitude: -115.792455556,
    altitude: 4494,
    heading: 320,
    groundSpeed: 0,
    verticalSpeed: 0,
    fuel: 1100,
    onGround: true,
    engineState: true,
    parkingBrake: true,
    gear: 1,
    flaps: 0,
    paused: false,
    simulatorTime: new Date().toISOString(),
    com1Active: 118.3,
    com1Standby: 121.5,
    com2Active: 118.3,
    com2Standby: 121.5,
    transponderCode: 2607,
  };
}
