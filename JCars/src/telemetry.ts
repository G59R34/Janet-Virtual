import {invoke} from "@tauri-apps/api/core";import type {Snapshot} from "./types";
const isTauri=()=>"__TAURI_INTERNALS__" in window;
export async function readSnapshot():Promise<Snapshot>{if(isTauri())return invoke<Snapshot>("read_simulator_snapshot");return {connected:false,provider:"Browser preview",latitude:0,longitude:0,altitude:0,heading:0,groundSpeed:0,verticalSpeed:0,fuel:0,onGround:true,engineState:false,parkingBrake:true,gear:1,flaps:0,paused:false,simulatorTime:new Date().toISOString()}}
