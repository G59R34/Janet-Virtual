use serde::Serialize;
use simconnect_sdk::{Notification, SimConnect, SimConnectObject};
use std::{
    net::UdpSocket,
    sync::{Arc, Mutex},
    thread,
    time::Duration,
};
use tauri::{
    image::Image,
    menu::{Menu, MenuItem},
    tray::{MouseButton, MouseButtonState, TrayIconBuilder, TrayIconEvent},
    Manager, State,
};

#[derive(Debug, Clone, SimConnectObject)]
#[simconnect(period = "visual-frame", interval = 30)]
struct AircraftData {
    #[simconnect(name = "TITLE")]
    title: String,
    #[simconnect(name = "PLANE LATITUDE", unit = "degrees")]
    latitude: f64,
    #[simconnect(name = "PLANE LONGITUDE", unit = "degrees")]
    longitude: f64,
    #[simconnect(name = "PLANE ALTITUDE", unit = "feet")]
    altitude: f64,
    #[simconnect(name = "PLANE HEADING DEGREES TRUE", unit = "degrees")]
    heading: f64,
    #[simconnect(name = "GROUND VELOCITY", unit = "knots")]
    ground_speed: f64,
    #[simconnect(name = "VERTICAL SPEED", unit = "feet per minute")]
    vertical_speed: f64,
    #[simconnect(name = "FUEL TOTAL QUANTITY", unit = "gallons")]
    fuel: f64,
    #[simconnect(name = "SIM ON GROUND")]
    on_ground: bool,
    #[simconnect(name = "GENERAL ENG COMBUSTION:1")]
    engine_state: bool,
    #[simconnect(name = "BRAKE PARKING POSITION")]
    parking_brake: bool,
    #[simconnect(name = "GEAR HANDLE POSITION")]
    gear: bool,
    #[simconnect(name = "FLAPS HANDLE PERCENT", unit = "percent")]
    flaps: f64,
    #[simconnect(name = "IS SLEW ACTIVE")]
    paused: bool,
    #[simconnect(name = "COM ACTIVE FREQUENCY:1", unit = "MHz")]
    com1_active: f64,
    #[simconnect(name = "COM STANDBY FREQUENCY:1", unit = "MHz")]
    com1_standby: f64,
    #[simconnect(name = "COM ACTIVE FREQUENCY:2", unit = "MHz")]
    com2_active: f64,
    #[simconnect(name = "COM STANDBY FREQUENCY:2", unit = "MHz")]
    com2_standby: f64,
    #[simconnect(name = "TRANSPONDER CODE:1", unit = "number")]
    transponder_code: f64,
}

#[derive(Serialize, Clone)]
#[serde(rename_all = "camelCase")]
struct SimulatorSnapshot {
    connected: bool,
    provider: String,
    latitude: f64,
    longitude: f64,
    altitude: f64,
    heading: f64,
    ground_speed: f64,
    vertical_speed: f64,
    fuel: f64,
    on_ground: bool,
    engine_state: bool,
    parking_brake: bool,
    gear: f64,
    flaps: f64,
    paused: bool,
    simulator_time: String,
    com1_active: f64,
    com1_standby: f64,
    com2_active: f64,
    com2_standby: f64,
    transponder_code: f64,
}
impl Default for SimulatorSnapshot {
    fn default() -> Self {
        Self {
            connected: false,
            provider: "No supported simulator detected".into(),
            latitude: 0.0,
            longitude: 0.0,
            altitude: 0.0,
            heading: 0.0,
            ground_speed: 0.0,
            vertical_speed: 0.0,
            fuel: 0.0,
            on_ground: true,
            engine_state: false,
            parking_brake: true,
            gear: 1.0,
            flaps: 0.0,
            paused: false,
            simulator_time: chrono::Utc::now().to_rfc3339(),
            com1_active: 0.0,
            com1_standby: 0.0,
            com2_active: 0.0,
            com2_standby: 0.0,
            transponder_code: 0.0,
        }
    }
}
struct SimulatorState(Arc<Mutex<SimulatorSnapshot>>);

fn run_simconnect(snapshot: Arc<Mutex<SimulatorSnapshot>>) {
    thread::spawn(move || loop {
        match SimConnect::new("JCars ACARS") {
            Ok(mut client) => {
                let mut registered = false;
                loop {
                    match client.get_next_dispatch() {
                        Ok(Some(Notification::Open)) => {
                            if client.register_object::<AircraftData>().is_ok() {
                                registered = true;
                            }
                        }
                        Ok(Some(Notification::Object(data))) if registered => {
                            if let Ok(v) = AircraftData::try_from(&data) {
                                if let Ok(mut s) = snapshot.lock() {
                                    *s = SimulatorSnapshot {
                                        connected: true,
                                        provider: format!("MSFS SimConnect · {}", v.title),
                                        latitude: v.latitude,
                                        longitude: v.longitude,
                                        altitude: v.altitude,
                                        heading: v.heading,
                                        ground_speed: v.ground_speed,
                                        vertical_speed: v.vertical_speed,
                                        fuel: v.fuel,
                                        on_ground: v.on_ground,
                                        engine_state: v.engine_state,
                                        parking_brake: v.parking_brake,
                                        gear: if v.gear { 1.0 } else { 0.0 },
                                        flaps: v.flaps,
                                        paused: v.paused,
                                        simulator_time: chrono::Utc::now().to_rfc3339(),
                                        com1_active: v.com1_active,
                                        com1_standby: v.com1_standby,
                                        com2_active: v.com2_active,
                                        com2_standby: v.com2_standby,
                                        transponder_code: v.transponder_code,
                                    };
                                }
                            }
                        }
                        Ok(_) => {}
                        Err(_) => break,
                    }
                    thread::sleep(Duration::from_millis(16));
                }
                if let Ok(mut s) = snapshot.lock() {
                    if s.provider.starts_with("MSFS") {
                        *s = SimulatorSnapshot::default();
                    }
                }
            }
            Err(_) => thread::sleep(Duration::from_secs(3)),
        }
    });
}

const XPLANE_REFS: [&str; 17] = [
    "sim/flightmodel/position/latitude",
    "sim/flightmodel/position/longitude",
    "sim/flightmodel/position/elevation",
    "sim/flightmodel/position/true_psi",
    "sim/flightmodel/position/groundspeed",
    "sim/flightmodel/position/vh_ind_fpm",
    "sim/flightmodel/weight/m_fuel_total",
    "sim/flightmodel/failures/onground_any",
    "sim/flightmodel/engine/ENGN_running[0]",
    "sim/cockpit2/controls/parking_brake_ratio",
    "sim/cockpit2/controls/gear_handle_down",
    "sim/cockpit2/controls/flap_ratio",
    "sim/cockpit2/radios/actuators/com1_frequency_hz_833",
    "sim/cockpit2/radios/actuators/com1_standby_frequency_hz_833",
    "sim/cockpit2/radios/actuators/com2_frequency_hz_833",
    "sim/cockpit2/radios/actuators/com2_standby_frequency_hz_833",
    "sim/cockpit/radios/transponder_code",
];
fn subscribe_xplane(socket: &UdpSocket) {
    for (index, path) in XPLANE_REFS.iter().enumerate() {
        let mut packet = [0u8; 413];
        packet[..5].copy_from_slice(b"RREF\0");
        packet[5..9].copy_from_slice(&2i32.to_le_bytes());
        packet[9..13].copy_from_slice(&(index as i32).to_le_bytes());
        let bytes = path.as_bytes();
        packet[13..13 + bytes.len()].copy_from_slice(bytes);
        let _ = socket.send_to(&packet, "127.0.0.1:49000");
    }
}
fn run_xplane(snapshot: Arc<Mutex<SimulatorSnapshot>>) {
    thread::spawn(move || loop {
        let socket = match UdpSocket::bind("127.0.0.1:0") {
            Ok(v) => v,
            Err(_) => {
                thread::sleep(Duration::from_secs(3));
                continue;
            }
        };
        let _ = socket.set_read_timeout(Some(Duration::from_secs(4)));
        subscribe_xplane(&socket);
        let mut values = [None::<f32>; 17];
        let mut buffer = [0u8; 2048];
        loop {
            match socket.recv_from(&mut buffer) {
                Ok((size, _)) if size >= 13 && &buffer[..5] == b"RREF," => {
                    for item in buffer[5..size].chunks_exact(8) {
                        let index = i32::from_le_bytes(item[..4].try_into().unwrap_or_default());
                        let value = f32::from_le_bytes(item[4..8].try_into().unwrap_or_default());
                        if index >= 0 && (index as usize) < values.len() {
                            values[index as usize] = Some(value);
                        }
                    }
                    if values[..8].iter().all(Option::is_some) {
                        if let Ok(mut s) = snapshot.lock() {
                            *s = SimulatorSnapshot {
                                connected: true,
                                provider: "X-Plane UDP · local simulator".into(),
                                latitude: values[0].unwrap_or_default() as f64,
                                longitude: values[1].unwrap_or_default() as f64,
                                altitude: values[2].unwrap_or_default() as f64 * 3.28084,
                                heading: values[3].unwrap_or_default() as f64,
                                ground_speed: values[4].unwrap_or_default() as f64 * 1.94384,
                                vertical_speed: values[5].unwrap_or_default() as f64,
                                fuel: values[6].unwrap_or_default() as f64 / 3.039,
                                on_ground: values[7].unwrap_or_default() > 0.5,
                                engine_state: values[8].unwrap_or_default() > 0.5,
                                parking_brake: values[9].unwrap_or_default() > 0.5,
                                gear: values[10].unwrap_or(1.0) as f64,
                                flaps: values[11].unwrap_or_default() as f64 * 100.0,
                                paused: false,
                                simulator_time: chrono::Utc::now().to_rfc3339(),
                                com1_active: values[12].unwrap_or_default() as f64 / 1000.0,
                                com1_standby: values[13].unwrap_or_default() as f64 / 1000.0,
                                com2_active: values[14].unwrap_or_default() as f64 / 1000.0,
                                com2_standby: values[15].unwrap_or_default() as f64 / 1000.0,
                                transponder_code: values[16].unwrap_or_default() as f64,
                            };
                        }
                    }
                }
                Err(_) => {
                    if let Ok(mut s) = snapshot.lock() {
                        if s.provider.starts_with("X-Plane") {
                            *s = SimulatorSnapshot::default();
                        }
                    }
                    break;
                }
                _ => {}
            }
        }
        thread::sleep(Duration::from_secs(2));
    });
}

#[tauri::command]
fn read_simulator_snapshot(state: State<'_, SimulatorState>) -> SimulatorSnapshot {
    state.0.lock().map(|s| s.clone()).unwrap_or_default()
}
fn tray_icon() -> Image<'static> {
    let mut rgba = vec![0u8; 32 * 32 * 4];
    for y in 0..32 {
        for x in 0..32 {
            let i = (y * 32 + x) * 4;
            let red = x > 4 && x < 27 && y > 4 && y < 27;
            rgba[i] = if red { 164 } else { 32 };
            rgba[i + 1] = if red { 22 } else { 35 };
            rgba[i + 2] = if red { 26 } else { 38 };
            rgba[i + 3] = 255;
        }
    }
    Image::new_owned(rgba, 32, 32)
}

#[cfg_attr(mobile, tauri::mobile_entry_point)]
pub fn run() {
    let snapshot = Arc::new(Mutex::new(SimulatorSnapshot::default()));
    run_simconnect(snapshot.clone());
    run_xplane(snapshot.clone());
    tauri::Builder::default()
        .manage(SimulatorState(snapshot))
        .plugin(tauri_plugin_opener::init())
        .plugin(tauri_plugin_store::Builder::new().build())
        .plugin(
            tauri_plugin_log::Builder::new()
                .level(log::LevelFilter::Info)
                .build(),
        )
        .setup(|app| {
            #[cfg(desktop)]
            app.handle().plugin(tauri_plugin_autostart::init(
                tauri_plugin_autostart::MacosLauncher::LaunchAgent,
                None,
            ))?;
            let show = MenuItem::with_id(app, "show", "Open JCars", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quit", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&show, &quit])?;
            TrayIconBuilder::with_id("jcars-tray")
                .icon(tray_icon())
                .tooltip("JCars · ACARS")
                .menu(&menu)
                .show_menu_on_left_click(false)
                .on_menu_event(|app, event| match event.id.as_ref() {
                    "show" => {
                        if let Some(w) = app.get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                    "quit" => app.exit(0),
                    _ => {}
                })
                .on_tray_icon_event(|tray, event| {
                    if let TrayIconEvent::Click {
                        button: MouseButton::Left,
                        button_state: MouseButtonState::Up,
                        ..
                    } = event
                    {
                        if let Some(w) = tray.app_handle().get_webview_window("main") {
                            let _ = w.show();
                            let _ = w.set_focus();
                        }
                    }
                })
                .build(app)?;
            Ok(())
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                api.prevent_close();
                let _ = window.hide();
            }
        })
        .invoke_handler(tauri::generate_handler![read_simulator_snapshot])
        .run(tauri::generate_context!())
        .expect("JCars failed to start")
}
