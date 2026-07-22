use crate::{
    api_native::Api,
    models::*,
    voice_native::{VoiceEngine, VoiceEngineState},
};
use eframe::egui::{self, Color32, FontId, Pos2, Sense, Shape, Stroke, Vec2};
use std::{
    fs,
    path::PathBuf,
    sync::mpsc::{self, Receiver, Sender},
    thread,
    time::{Duration, Instant},
};
const BG: Color32 = Color32::from_rgb(8, 13, 16);
const PANEL: Color32 = Color32::from_rgb(20, 27, 31);
const LINE: Color32 = Color32::from_rgb(55, 78, 82);
const TEXT: Color32 = Color32::from_rgb(190, 210, 202);
const GREEN: Color32 = Color32::from_rgb(100, 205, 143);
const CYAN: Color32 = Color32::from_rgb(85, 190, 214);
const AMBER: Color32 = Color32::from_rgb(236, 190, 80);
enum Event {
    Logged(Result<AuthSession, String>),
    Refreshed(Result<AuthSession, String>, RetryAction),
    Opened(Result<ControllerSession, String>),
    Claimed(Result<String, String>),
    Snapshot(Result<Snapshot, String>),
    Issued(Result<String, String>),
    VoiceHosted(Result<VoiceHostResponse, String>),
    VoicePolled(Result<VoicePoll, String>),
    VoiceClosed(Result<String, String>),
    Vatsim(Result<Vec<VatsimController>, String>),
}
#[derive(Clone, Copy)]
enum RetryAction {
    Open,
    Claim,
    Snapshot,
    HostVoice,
}
#[derive(Default)]
struct Layers {
    airspace: bool,
    airways: bool,
    fixes: bool,
    navaids: bool,
    procedures: bool,
    ground: bool,
}
#[derive(Clone)]
struct RadarVector {
    start: [f64; 2],
    end: [f64; 2],
    aircraft_id: String,
}

fn vatsim_position_matches(callsign: &str, prefixes: &[&str], suffix: &str) -> bool {
    let callsign = callsign.to_ascii_uppercase();
    callsign.ends_with(suffix) && prefixes.iter().any(|prefix| callsign.starts_with(prefix))
}

fn is_unauthorized(error: &str) -> bool {
    error.trim().eq_ignore_ascii_case("unauthorized")
        || error.to_ascii_lowercase().contains("jwt expired")
}

pub struct JScopeApp {
    api: Api,
    tx: Sender<Event>,
    rx: Receiver<Event>,
    auth: Option<AuthSession>,
    controller: Option<ControllerSession>,
    position_session: String,
    resume_position: bool,
    refresh_auth_on_start: bool,
    selected_position: String,
    safety: bool,
    email: String,
    password: String,
    message: String,
    busy: bool,
    snapshot: Snapshot,
    last_poll: Instant,
    sector: Sector,
    layers: Layers,
    zoom: f32,
    pan: Vec2,
    selected_aircraft: String,
    instruction_type: String,
    instruction_text: String,
    selected_procedure: usize,
    vector_mode: bool,
    vector_start: Option<[f64; 2]>,
    vector_preview: Option<[f64; 2]>,
    radar_vectors: Vec<RadarVector>,
    squawk_code: String,
    voice: Option<VoiceGrant>,
    voice_participants: Vec<VoiceParticipant>,
    last_voice_poll: Instant,
    voice_after: i64,
    voice_mode: String,
    voice_engine: VoiceEngine,
    voice_engine_state: VoiceEngineState,
    controller_transmitting: bool,
    vatsim_controllers: Vec<VatsimController>,
    vatsim_error: String,
    vatsim_received: bool,
    last_vatsim_poll: Instant,
}
impl JScopeApp {
    pub fn new(cc: &eframe::CreationContext<'_>) -> Self {
        let mut visuals = egui::Visuals::dark();
        visuals.panel_fill = BG;
        visuals.window_fill = PANEL;
        visuals.override_text_color = Some(TEXT);
        visuals.widgets.inactive.bg_fill = PANEL;
        visuals.widgets.inactive.bg_stroke = Stroke::new(1.0, LINE);
        visuals.widgets.hovered.bg_stroke = Stroke::new(1.0, GREEN);
        cc.egui_ctx.set_visuals(visuals);
        let (tx, rx) = mpsc::channel();
        let persisted = load_session();
        let resume_position = persisted
            .as_ref()
            .is_some_and(|session| !session.position_session.is_empty());
        let refresh_auth_on_start = persisted
            .as_ref()
            .is_some_and(|session| session.auth.expires_at <= chrono::Utc::now().timestamp() + 60);
        Self {
            api: Api::new(),
            tx,
            rx,
            auth: persisted.as_ref().map(|p| p.auth.clone()),
            controller: persisted.as_ref().and_then(|p| p.controller.clone()),
            position_session: persisted
                .as_ref()
                .map(|p| p.position_session.clone())
                .unwrap_or_default(),
            resume_position,
            refresh_auth_on_start,
            selected_position: persisted
                .as_ref()
                .map(|p| p.selected_position.clone())
                .unwrap_or_default(),
            safety: false,
            email: String::new(),
            password: String::new(),
            message: String::new(),
            busy: false,
            snapshot: Snapshot::default(),
            last_poll: Instant::now() - Duration::from_secs(10),
            sector: load_sector(),
            layers: Layers {
                airspace: true,
                airways: true,
                fixes: true,
                navaids: true,
                procedures: true,
                ground: true,
            },
            zoom: 1.0,
            pan: Vec2::ZERO,
            selected_aircraft: String::new(),
            instruction_type: "heading".into(),
            instruction_text: String::new(),
            selected_procedure: 0,
            vector_mode: false,
            vector_start: None,
            vector_preview: None,
            radar_vectors: Vec::new(),
            squawk_code: String::new(),
            voice: None,
            voice_participants: Vec::new(),
            last_voice_poll: Instant::now() - Duration::from_secs(10),
            voice_after: 0,
            voice_mode: "direct-preferred".into(),
            voice_engine: VoiceEngine::new(),
            voice_engine_state: VoiceEngineState::Offline,
            controller_transmitting: false,
            vatsim_controllers: Vec::new(),
            vatsim_error: String::new(),
            vatsim_received: false,
            last_vatsim_poll: Instant::now() - Duration::from_secs(30),
        }
    }
    fn spawn<F: FnOnce() -> Event + Send + 'static>(&mut self, f: F) {
        self.busy = true;
        let tx = self.tx.clone();
        thread::spawn(move || {
            let _ = tx.send(f());
        });
    }
    fn login(&mut self) {
        let api = self.api.clone();
        let email = self.email.clone();
        let password = self.password.clone();
        self.spawn(move || Event::Logged(api.login(&email, &password).map_err(|e| e.to_string())))
    }
    fn refresh_auth(&mut self, retry: RetryAction) {
        let Some(auth) = self.auth.clone() else {
            return;
        };
        let api = self.api.clone();
        self.spawn(move || {
            Event::Refreshed(api.refresh_auth(&auth).map_err(|e| e.to_string()), retry)
        });
    }
    fn retry_after_refresh(&mut self, retry: RetryAction) {
        match retry {
            RetryAction::Open => self.open(),
            RetryAction::Claim => self.claim(),
            RetryAction::Snapshot => self.poll(),
            RetryAction::HostVoice => self.host_voice(),
        }
    }
    fn open(&mut self) {
        let (api, auth) = (self.api.clone(), self.auth.clone().unwrap());
        self.spawn(move || Event::Opened(api.open(&auth).map_err(|e| e.to_string())))
    }
    fn claim(&mut self) {
        let (api, auth, c, p) = (
            self.api.clone(),
            self.auth.clone().unwrap(),
            self.controller.clone().unwrap(),
            self.selected_position.clone(),
        );
        self.spawn(move || Event::Claimed(api.claim(&auth, &c, &p).map_err(|e| e.to_string())))
    }
    fn host_voice(&mut self) {
        let (api, auth, c, p, mode) = (
            self.api.clone(),
            self.auth.clone().unwrap(),
            self.controller.clone().unwrap(),
            self.position_session.clone(),
            self.voice_mode.clone(),
        );
        self.spawn(move || {
            Event::VoiceHosted(
                api.host_voice(&auth, &c, &p, &mode)
                    .map_err(|e| e.to_string()),
            )
        })
    }
    fn poll_voice(&mut self) {
        if self.busy
            || self.last_voice_poll.elapsed() < Duration::from_secs(1)
            || self.voice.is_none()
        {
            return;
        }
        self.last_voice_poll = Instant::now();
        let (api, auth, voice, after) = (
            self.api.clone(),
            self.auth.clone().unwrap(),
            self.voice.clone().unwrap(),
            self.voice_after,
        );
        self.spawn(move || {
            Event::VoicePolled(
                api.poll_voice(&auth, &voice, after)
                    .map_err(|e| e.to_string()),
            )
        })
    }
    fn close_voice(&mut self) {
        let (api, auth, c, p) = (
            self.api.clone(),
            self.auth.clone().unwrap(),
            self.controller.clone().unwrap(),
            self.position_session.clone(),
        );
        self.spawn(move || {
            Event::VoiceClosed(
                api.close_voice(&auth, &c, &p)
                    .map(|_| "RADIO CLOSED".into())
                    .map_err(|e| e.to_string()),
            )
        })
    }
    fn poll(&mut self) {
        if self.busy
            || self.controller.is_none()
            || self.position_session.is_empty()
            || self.last_poll.elapsed() < Duration::from_secs(3)
        {
            return;
        }
        self.last_poll = Instant::now();
        let (api, auth, c) = (
            self.api.clone(),
            self.auth.clone().unwrap(),
            self.controller.clone().unwrap(),
        );
        self.spawn(move || Event::Snapshot(api.snapshot(&auth, &c).map_err(|e| e.to_string())))
    }
    fn poll_vatsim(&mut self) {
        if self.last_vatsim_poll.elapsed() < Duration::from_secs(15) {
            return;
        }
        self.last_vatsim_poll = Instant::now();
        let api = self.api.clone();
        let tx = self.tx.clone();
        thread::spawn(move || {
            let _ = tx.send(Event::Vatsim(
                api.vatsim_controllers().map_err(|error| error.to_string()),
            ));
        });
    }
    fn issue(&mut self) {
        let (api, auth, c, p, a, k, t) = (
            self.api.clone(),
            self.auth.clone().unwrap(),
            self.controller.clone().unwrap(),
            self.position_session.clone(),
            self.selected_aircraft.clone(),
            self.instruction_type.clone(),
            self.instruction_text.clone(),
        );
        self.spawn(move || {
            Event::Issued(
                api.instruction(&auth, &c, &p, &a, &k, &t, serde_json::json!({}))
                    .map(|_| "INSTRUCTION ISSUED / AUDITED".into())
                    .map_err(|e| e.to_string()),
            )
        })
    }
    fn assign_squawk(&mut self) {
        let code = self.squawk_code.trim().to_owned();
        if code.len() != 4 || !code.chars().all(|c| matches!(c, '0'..='7')) {
            self.message = "SQUAWK MUST BE FOUR OCTAL DIGITS (0000-7777)".into();
            return;
        }
        let (api, auth, c, p, a) = (
            self.api.clone(),
            self.auth.clone().unwrap(),
            self.controller.clone().unwrap(),
            self.position_session.clone(),
            self.selected_aircraft.clone(),
        );
        self.spawn(move || {
            Event::Issued(
                api.instruction(
                    &auth,
                    &c,
                    &p,
                    &a,
                    "squawk",
                    &format!("SQUAWK {code}"),
                    serde_json::json!({"code": code}),
                )
                .map(|_| "SQUAWK ASSIGNED / AUDITED".into())
                .map_err(|e| e.to_string()),
            )
        });
    }
    fn events(&mut self) {
        while let Ok(event) = self.rx.try_recv() {
            if !matches!(&event, Event::Vatsim(_)) {
                self.busy = false;
            }
            match event {
                Event::Logged(r) => match r {
                    Ok(a) => {
                        self.auth = Some(a);
                        self.password.clear();
                        self.open()
                    }
                    Err(e) => self.message = e,
                },
                Event::Refreshed(r, retry) => match r {
                    Ok(auth) => {
                        self.auth = Some(auth);
                        self.refresh_auth_on_start = false;
                        self.save();
                        self.retry_after_refresh(retry);
                    }
                    Err(error) => {
                        self.auth = None;
                        self.controller = None;
                        self.position_session.clear();
                        self.message = format!("SESSION EXPIRED · SIGN IN AGAIN · {error}");
                        if let Some(path) = session_path() {
                            let _ = fs::remove_file(path);
                        }
                    }
                },
                Event::Opened(r) => match r {
                    Ok(c) => {
                        if self.selected_position.is_empty() {
                            self.selected_position = c
                                .positions
                                .first()
                                .map(|p| p.id.clone())
                                .unwrap_or_default()
                        }
                        self.controller = Some(c);
                        self.save()
                    }
                    Err(e) => {
                        if is_unauthorized(&e) {
                            self.refresh_auth(RetryAction::Open)
                        } else {
                            self.message = e
                        }
                    }
                },
                Event::Claimed(r) => match r {
                    Ok(p) => {
                        self.resume_position = false;
                        self.position_session = p;
                        self.message = "POSITION ACQUIRED".into();
                        self.save();
                        self.host_voice()
                    }
                    Err(e) => {
                        if is_unauthorized(&e) {
                            self.refresh_auth(RetryAction::Claim);
                            continue;
                        }
                        self.resume_position = false;
                        self.position_session.clear();
                        self.voice = None;
                        self.message = e;
                        self.save();
                    }
                },
                Event::Snapshot(r) => match r {
                    Ok(s) => self.snapshot = s,
                    Err(e) => {
                        if is_unauthorized(&e) {
                            self.refresh_auth(RetryAction::Snapshot);
                            continue;
                        }
                        self.message = e.clone();
                        if e.to_lowercase().contains("expired") {
                            self.controller = None;
                            self.position_session.clear();
                            self.save()
                        }
                    }
                },
                Event::Issued(r) => match r {
                    Ok(m) => {
                        self.message = m;
                        self.instruction_text.clear()
                    }
                    Err(e) => self.message = e,
                },
                Event::VoiceHosted(r) => match r {
                    Ok(v) => {
                        self.message = "CONNECTING TO CENTRAL JVA VOICE".into();
                        self.voice_engine.start_central(v.central);
                        self.voice = Some(v.radio)
                    }
                    Err(e) => {
                        if is_unauthorized(&e) {
                            self.refresh_auth(RetryAction::HostVoice);
                            continue;
                        }
                        if e.to_ascii_lowercase()
                            .contains("authoritative position lock required")
                        {
                            self.position_session.clear();
                            self.voice = None;
                            self.message = "REVALIDATING CONTROLLER POSITION LOCK".into();
                            self.claim();
                        } else {
                            self.message = e;
                        }
                    }
                },
                Event::VoicePolled(r) => match r {
                    Ok(v) => {
                        self.voice_engine.events(v.events.clone());
                        for event in &v.events {
                            if let Some(id) = event.get("id").and_then(|v| v.as_i64()) {
                                self.voice_after = self.voice_after.max(id)
                            }
                        }
                        self.voice_participants = v.participants
                    }
                    Err(e) => {
                        self.message = e;
                        self.voice = None
                    }
                },
                Event::VoiceClosed(r) => match r {
                    Ok(m) => {
                        self.message = m;
                        self.voice = None;
                        self.voice_participants.clear()
                    }
                    Err(e) => self.message = e,
                },
                Event::Vatsim(r) => match r {
                    Ok(controllers) => {
                        self.vatsim_controllers = controllers;
                        self.vatsim_error.clear();
                        self.vatsim_received = true;
                    }
                    Err(error) => self.vatsim_error = error,
                },
            }
        }
    }
    fn save(&self) {
        if let Some(auth) = &self.auth {
            let p = PersistedSession {
                auth: auth.clone(),
                controller: self.controller.clone(),
                position_session: self.position_session.clone(),
                selected_position: self.selected_position.clone(),
            };
            if let Some(path) = session_path() {
                let _ = fs::create_dir_all(path.parent().unwrap());
                let _ = fs::write(path, serde_json::to_vec(&p).unwrap_or_default());
            }
        }
    }
    fn logout(&mut self) {
        self.auth = None;
        self.controller = None;
        self.position_session.clear();
        self.voice = None;
        self.voice_engine.stop();
        if let Some(p) = session_path() {
            let _ = fs::remove_file(p);
        }
        self.message = "SIGNED OUT".into()
    }
    fn gate(&mut self, ctx: &mut egui::Ui) {
        egui::CentralPanel::default().show(ctx,|ui|{ui.vertical_centered(|ui|{ui.add_space(90.0);egui::Frame::new().fill(PANEL).stroke(Stroke::new(1.0,LINE)).inner_margin(30.0).show(ui,|ui|{ui.set_width(520.0);ui.heading(egui::RichText::new(if self.auth.is_none(){"JSCOPE CONTROLLER LOGIN"}else if self.controller.is_none(){"CONTROLLER AUTHORIZATION"}else{"ACQUIRE TACTICAL POSITION"}).color(GREEN).size(28.0));ui.add_space(14.0);if self.auth.is_none(){ui.label("Central JCars identity");ui.text_edit_singleline(&mut self.email);ui.add(egui::TextEdit::singleline(&mut self.password).password(true).hint_text("Password"));if ui.add_enabled(!self.busy,egui::Button::new("SIGN IN").min_size(Vec2::new(520.0,38.0))).clicked(){self.login()}}else if self.controller.is_none(){ui.label("Validate controller profile and current qualifications.");if ui.add_enabled(!self.busy,egui::Button::new("VALIDATE ACCESS").min_size(Vec2::new(520.0,38.0))).clicked(){self.open()}}else{let positions=self.controller.as_ref().unwrap().positions.clone();egui::ComboBox::from_label("POSITION").selected_text(positions.iter().find(|p|p.id==self.selected_position).map(|p|format!("{}  {}",p.display_name,p.display_frequency)).unwrap_or_default()).show_ui(ui,|ui|for p in positions{ui.selectable_value(&mut self.selected_position,p.id,format!("{}  {}",p.display_name,p.display_frequency));});ui.checkbox(&mut self.safety,"I accept the operational safety notice");ui.label(egui::RichText::new("PRIVATE VA SIMULATION — VATSIM, TCAS AND REAL-WORLD SAFETY TAKE PRECEDENCE").color(AMBER));if ui.add_enabled(self.safety&&!self.busy,egui::Button::new("ACQUIRE POSITION").min_size(Vec2::new(520.0,38.0))).clicked(){self.claim()}}if !self.message.is_empty(){ui.add_space(12.0);ui.label(egui::RichText::new(&self.message).color(Color32::LIGHT_RED));}});});});
    }
}
impl eframe::App for JScopeApp {
    fn logic(&mut self, ctx: &egui::Context, _: &mut eframe::Frame) {
        self.events();
        if self.refresh_auth_on_start && !self.busy && self.auth.is_some() {
            self.refresh_auth_on_start = false;
            self.refresh_auth(RetryAction::Claim);
        }
        if self.resume_position
            && !self.busy
            && self.auth.is_some()
            && self.controller.is_some()
            && !self.selected_position.is_empty()
        {
            self.resume_position = false;
            self.claim();
        }
        self.poll();
        self.poll_voice();
        self.poll_vatsim();
        for state in self.voice_engine.updates().collect::<Vec<_>>() {
            if let VoiceEngineState::Failed(error) = &state {
                self.message = error.clone();
            }
            self.voice_engine_state = state;
        }
        ctx.request_repaint_after(Duration::from_millis(250));
    }
    fn ui(&mut self, ui: &mut egui::Ui, _: &mut eframe::Frame) {
        if self.auth.is_none() || self.controller.is_none() || self.position_session.is_empty() {
            self.gate(ui);
            if self.auth.is_some() {
                egui::Area::new(egui::Id::new("session-recovery"))
                    .anchor(egui::Align2::CENTER_BOTTOM, Vec2::new(0.0, -18.0))
                    .show(ui.ctx(), |area| {
                        egui::Frame::new()
                            .fill(PANEL)
                            .stroke(Stroke::new(1.0, LINE))
                            .inner_margin(8.0)
                            .show(area, |area| {
                                if area.button("SIGN OUT & CLEAR CONTROLLER SESSION").clicked() {
                                    self.logout();
                                }
                            });
                    });
            }
            return;
        }
        self.scope(ui)
    }
}

impl JScopeApp {
    fn scope(&mut self, ctx: &mut egui::Ui) {
        let context = ctx.ctx().clone();
        let position = self
            .controller
            .as_ref()
            .and_then(|c| c.positions.iter().find(|p| p.id == self.selected_position))
            .cloned()
            .unwrap_or_default();
        egui::Panel::top("command")
            .exact_size(88.0)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.heading(egui::RichText::new("JScope").color(GREEN).size(24.0));
                    ui.separator();
                    ui.label(format!(
                        "{} / {}",
                        position.display_name.to_uppercase(),
                        position.radio_callsign
                    ));
                    ui.label(
                        egui::RichText::new(format!("VHF {}", position.display_frequency))
                            .color(AMBER)
                            .strong(),
                    );
                    ui.separator();
                    for (label, value) in [
                        ("AIRSPACE", &mut self.layers.airspace),
                        ("AIRWAYS", &mut self.layers.airways),
                        ("FIXES", &mut self.layers.fixes),
                        ("NAVAIDS", &mut self.layers.navaids),
                        ("PROCS", &mut self.layers.procedures),
                        ("GROUND", &mut self.layers.ground),
                    ] {
                        ui.toggle_value(value, label);
                    }
                    ui.with_layout(egui::Layout::right_to_left(egui::Align::Center), |ui| {
                        if ui.button("SIGN OUT").clicked() {
                            self.logout()
                        }
                        ui.label(format!("AIRAC {}", self.sector.metadata.cycle));
                    });
                });
                ui.separator();
                ui.horizontal(|ui| {
                    ui.label(
                        egui::RichText::new("VATSIM COORDINATION")
                            .color(CYAN)
                            .strong(),
                    );
                    ui.separator();
                    egui::ScrollArea::horizontal()
                        .id_salt("vatsim-coordination-strip")
                        .show(ui, |ui| {
                            ui.horizontal(|ui| {
                                for (label, prefixes, suffix) in [
                                    ("LAX CTR", &["LAX"][..], "_CTR"),
                                    ("OAK CTR", &["OAK"][..], "_CTR"),
                                    ("SLC CTR", &["SLC"][..], "_CTR"),
                                    ("LAS APP", &["LAS"][..], "_APP"),
                                    ("NJK APP", &["NJK"][..], "_APP"),
                                    ("EDW APP", &["EDW"][..], "_APP"),
                                    (
                                        "SOCAL APP",
                                        &["LAX", "BUR", "ONT", "SNA", "SAN"][..],
                                        "_APP",
                                    ),
                                ] {
                                    let online = self
                                        .vatsim_controllers
                                        .iter()
                                        .filter(|controller| {
                                            vatsim_position_matches(
                                                &controller.callsign,
                                                prefixes,
                                                suffix,
                                            )
                                        })
                                        .collect::<Vec<_>>();
                                    if online.is_empty() {
                                        let state = if self.vatsim_received {
                                            "OFFLINE"
                                        } else {
                                            "CHECKING"
                                        };
                                        ui.label(
                                            egui::RichText::new(format!("{label} {state}"))
                                                .color(LINE),
                                        );
                                    } else {
                                        for controller in online {
                                            ui.label(
                                                egui::RichText::new(format!(
                                                    "{} {} ONLINE",
                                                    controller.callsign, controller.frequency
                                                ))
                                                .color(GREEN)
                                                .strong(),
                                            );
                                        }
                                    }
                                    ui.separator();
                                }
                                if !self.vatsim_error.is_empty() {
                                    ui.label(egui::RichText::new("FEED UNAVAILABLE").color(AMBER));
                                }
                            });
                        });
                });
            });
        egui::Panel::right("lists")
            .default_size(310.0)
            .min_size(260.0)
            .show(ctx, |ui| {
                ui.heading(egui::RichText::new("CONTROLLER LISTS").color(GREEN));
                ui.group(|ui| {
                    ui.label(egui::RichText::new("TACTICAL RADIO / CONTROLLER HOST").color(GREEN));
                    if let Some(voice) = &self.voice {
                        ui.label(format!(
                            "{} · SIGNALING READY",
                            voice.position_id.to_uppercase()
                        ));
                        let media = match &self.voice_engine_state {
                            VoiceEngineState::Offline => "MEDIA OFFLINE".into(),
                            VoiceEngineState::Listening => "UDP 30814 LISTENING".into(),
                            VoiceEngineState::Connecting => "WEBRTC NEGOTIATING".into(),
                            VoiceEngineState::Connected => "MEDIA ONLINE · DIRECT".into(),
                            VoiceEngineState::Central => "MEDIA ONLINE · CENTRAL JVA VOICE".into(),
                            VoiceEngineState::Failed(e) => format!("MEDIA FAILED · {e}"),
                        };
                        ui.label(egui::RichText::new(media).color(
                            if matches!(self.voice_engine_state, VoiceEngineState::Connected) {
                                GREEN
                            } else {
                                AMBER
                            },
                        ));
                        let keyboard_ptt =
                            ui.input(|i| i.modifiers.ctrl && i.key_down(egui::Key::Space));
                        let response = ui.add_enabled(
                            matches!(self.voice_engine_state, VoiceEngineState::Connected|VoiceEngineState::Central),
                            egui::Button::new(if self.controller_transmitting {
                                "TRANSMITTING"
                            } else {
                                "HOLD PTT - CTRL+SPACE"
                            }),
                        );
                        let active = response.is_pointer_button_down_on() || keyboard_ptt;
                        if active != self.controller_transmitting {
                            self.controller_transmitting = active;
                            self.voice_engine.ptt(active);
                        }
                        ui.label(format!(
                            "MODE {} · {} PILOTS",
                            voice.transport_mode.to_uppercase(),
                            self.voice_participants
                                .iter()
                                .filter(|p| p.role == "pilot")
                                .count()
                        ));
                        for participant in &self.voice_participants {
                            ui.label(format!(
                                "{}  {}  {}%{}",
                                participant.callsign,
                                participant.mode.as_deref().unwrap_or("connecting"),
                                participant.quality.unwrap_or(0),
                                if participant.transmitting { "  TX" } else { "" }
                            ));
                        }
                        if ui
                            .add_enabled(!self.busy, egui::Button::new("CLOSE RADIO"))
                            .clicked()
                        {
                            self.close_voice()
                        }
                    } else {
                        ui.label(egui::RichText::new("RADIO OFFLINE").color(Color32::LIGHT_RED));
                        if ui
                            .add_enabled(!self.busy, egui::Button::new("RETRY RADIO HOST"))
                            .clicked()
                        {
                            self.claim()
                        }
                    }
                });
                ui.separator();
                ui.label(format!(
                    "{} PARTICIPATING TARGETS",
                    self.snapshot.aircraft.len()
                ));
                ui.separator();
                egui::ScrollArea::vertical()
                    .max_height(280.0)
                    .show(ui, |ui| {
                        for a in &self.snapshot.aircraft {
                            let selected = a.id == self.selected_aircraft;
                            let status = if a.radio_tuned { "ON FREQ" } else { "OFF FREQ" };
                            let label = format!(
                                "{:<10} {:>5.0}  {:>3.0}KT\n{}→{}  COM1 {}  {}",
                                a.callsign,
                                a.altitude.unwrap_or(0.0),
                                a.ground_speed.unwrap_or(0.0),
                                a.origin,
                                a.destination,
                                a.com1_active
                                    .map(|v| format!("{v:.3}"))
                                    .unwrap_or("---.---".into()),
                                status
                            );
                            if ui.selectable_label(selected, label).clicked() {
                                self.selected_aircraft = a.id.clone();
                            }
                        }
                    });
                ui.separator();
                if let Some(a) = self
                    .snapshot
                    .aircraft
                    .iter()
                    .find(|a| a.id == self.selected_aircraft)
                {
                    ui.heading(egui::RichText::new(&a.callsign).color(AMBER));
                    egui::Grid::new("target_data").show(ui, |ui| {
                        ui.label("ALTITUDE");
                        ui.label(format!("{:.0} FT", a.altitude.unwrap_or(0.0)));
                        ui.end_row();
                        ui.label("SPEED");
                        ui.label(format!("{:.0} KT", a.ground_speed.unwrap_or(0.0)));
                        ui.end_row();
                        ui.label("VERT RATE");
                        ui.label(format!("{:.0} FPM", a.vertical_speed.unwrap_or(0.0)));
                        ui.end_row();
                        ui.label("SQUAWK");
                        ui.label(
                            a.transponder_code
                                .map(|v| format!("{:04.0}", v))
                                .unwrap_or("----".into()),
                        );
                        ui.end_row();
                        ui.label("COM1 / COM2");
                        ui.label(format!(
                            "{} / {}",
                            a.com1_active
                                .map(|v| format!("{v:.3}"))
                                .unwrap_or("---.---".into()),
                            a.com2_active
                                .map(|v| format!("{v:.3}"))
                                .unwrap_or("---.---".into())
                        ));
                        ui.end_row();
                    });
                    ui.separator();
                    ui.horizontal(|ui| {
                        ui.label("ASSIGN SQUAWK");
                        ui.add(
                            egui::TextEdit::singleline(&mut self.squawk_code)
                                .char_limit(4)
                                .desired_width(70.0)
                                .hint_text("0000"),
                        );
                        if ui
                            .add_enabled(
                                !self.busy && !self.selected_aircraft.is_empty(),
                                egui::Button::new("SET"),
                            )
                            .clicked()
                        {
                            self.assign_squawk();
                        }
                    });
                    ui.separator();
                    egui::ComboBox::from_label("INSTRUCTION")
                        .selected_text(self.instruction_type.to_uppercase())
                        .show_ui(ui, |ui| {
                            for kind in [
                                "heading",
                                "altitude",
                                "speed",
                                "route",
                                "direct_to",
                                "hold",
                                "approach_assignment",
                                "range_entry",
                                "range_exit",
                                "operating_area",
                                "advisory",
                            ] {
                                ui.selectable_value(
                                    &mut self.instruction_type,
                                    kind.into(),
                                    kind.to_uppercase(),
                                );
                            }
                        });
                    ui.add(
                        egui::TextEdit::multiline(&mut self.instruction_text)
                            .desired_rows(4)
                            .hint_text("Controller instruction / clearance"),
                    );
                    if ui
                        .add_enabled(
                            !self.busy && !self.instruction_text.trim().is_empty(),
                            egui::Button::new("ISSUE + AUDIT")
                                .min_size(Vec2::new(ui.available_width(), 34.0)),
                        )
                        .clicked()
                    {
                        self.issue()
                    }
                } else {
                    ui.label("Select a target to display the data block and issue instructions.");
                }
                if !self.message.is_empty() {
                    ui.separator();
                    ui.label(egui::RichText::new(&self.message).color(AMBER));
                }
            });
        egui::Panel::bottom("status")
            .exact_size(72.0)
            .show(ctx, |ui| {
                ui.horizontal(|ui| {
                    ui.label(format!("RANGE {:03.0} NM", 160.0 / self.zoom));
                    ui.separator();
                    ui.toggle_value(&mut self.vector_mode, "DRAW VECTOR");
                    if ui.button("CLEAR VECTORS").clicked() {
                        self.radar_vectors.clear();
                        self.vector_start = None;
                        self.vector_preview = None;
                    }
                    ui.separator();
                    ui.label("SERVER ONLINE");
                    ui.separator();
                    ui.label("VHF RADIO STACK / JCARS TELEMETRY");
                    ui.separator();
                    let procedures: Vec<String> = self
                        .sector
                        .airports
                        .iter()
                        .flat_map(|a| {
                            a.procedures.iter().map(move |p| {
                                format!("{} · {} · {} · {}", a.id, p.kind, p.name, p.transition)
                            })
                        })
                        .collect();
                    egui::ComboBox::from_id_salt("procedure")
                        .width(430.0)
                        .selected_text(
                            procedures
                                .get(self.selected_procedure)
                                .cloned()
                                .unwrap_or("NO PROCEDURE".into()),
                        )
                        .show_ui(ui, |ui| {
                            for (i, name) in procedures.iter().enumerate() {
                                ui.selectable_value(&mut self.selected_procedure, i, name);
                            }
                        });
                });
                ui.label(
                    egui::RichText::new(
                        "PRIVATE SIMULATION SERVICE — NOT FOR REAL-WORLD NAVIGATION",
                    )
                    .color(AMBER),
                );
            });
        egui::CentralPanel::default().show(ctx, |ui| self.radar(ui, &context));
    }
    fn radar(&mut self, ui: &mut egui::Ui, ctx: &egui::Context) {
        let (response, painter) = ui.allocate_painter(ui.available_size(), Sense::click_and_drag());
        let rect = response.rect;
        if response.hovered() {
            let scroll = ctx.input(|i| i.smooth_scroll_delta.y);
            if scroll.abs() > 0.0 {
                let old_zoom = self.zoom;
                let new_zoom = (old_zoom * (scroll * 0.002).exp()).clamp(0.65, 400.0);
                if let Some(cursor) = response.hover_pos() {
                    let center = rect.center();
                    let ratio = new_zoom / old_zoom;
                    self.pan = cursor - center - (cursor - center - self.pan) * ratio;
                }
                self.zoom = new_zoom;
            }
        }
        if response.dragged() && !self.vector_mode {
            self.pan += ctx.input(|i| i.pointer.delta())
        }
        let b = &self.sector.metadata.bounds;
        let project = |lon: f64, lat: f64, zoom: f32, pan: Vec2| -> Pos2 {
            let x = ((lon - b.west) / (b.east - b.west)) as f32;
            let y = ((b.north - lat) / (b.north - b.south)) as f32;
            Pos2::new(
                rect.left() + rect.width() * (0.5 + (x - 0.5) * zoom) + pan.x,
                rect.top() + rect.height() * (0.5 + (y - 0.5) * zoom) + pan.y,
            )
        };
        let unproject = |p: Pos2, zoom: f32, pan: Vec2| -> [f64; 2] {
            let x = 0.5 + ((p.x - rect.left() - pan.x) / rect.width() - 0.5) / zoom;
            let y = 0.5 + ((p.y - rect.top() - pan.y) / rect.height() - 0.5) / zoom;
            [
                b.west + x as f64 * (b.east - b.west),
                b.north - y as f64 * (b.north - b.south),
            ]
        };
        if self.vector_mode {
            if response.drag_started() {
                self.vector_start = response
                    .interact_pointer_pos()
                    .map(|p| unproject(p, self.zoom, self.pan));
                self.vector_preview = self.vector_start;
            }
            if response.dragged() {
                self.vector_preview = response
                    .interact_pointer_pos()
                    .map(|p| unproject(p, self.zoom, self.pan));
            }
            if response.drag_stopped() {
                if let (Some(start), Some(end)) =
                    (self.vector_start.take(), self.vector_preview.take())
                {
                    self.radar_vectors.push(RadarVector {
                        start,
                        end,
                        aircraft_id: self.selected_aircraft.clone(),
                    });
                }
            }
        }
        for n in 0..=8 {
            let x = rect.left() + rect.width() * n as f32 / 8.0;
            painter.line_segment(
                [Pos2::new(x, rect.top()), Pos2::new(x, rect.bottom())],
                Stroke::new(0.5, Color32::from_rgb(21, 39, 43)),
            );
        }
        for n in 0..=6 {
            let y = rect.top() + rect.height() * n as f32 / 6.0;
            painter.line_segment(
                [Pos2::new(rect.left(), y), Pos2::new(rect.right(), y)],
                Stroke::new(0.5, Color32::from_rgb(21, 39, 43)),
            );
        }
        if self.layers.airspace {
            for a in &self.sector.airspaces {
                let points: Vec<_> = a
                    .points
                    .iter()
                    .map(|p| project(p[0], p[1], self.zoom, self.pan))
                    .collect();
                if points.len() > 2 {
                    painter.add(Shape::closed_line(
                        points.clone(),
                        Stroke::new(1.0, Color32::from_rgb(69, 94, 101)),
                    ));
                    let c = points.iter().fold(Vec2::ZERO, |s, p| s + p.to_vec2())
                        / points.len() as f32;
                    painter.text(
                        c.to_pos2(),
                        egui::Align2::CENTER_CENTER,
                        a.name.split_whitespace().next().unwrap_or("AREA"),
                        FontId::monospace(10.0),
                        Color32::from_rgb(72, 105, 109),
                    );
                }
            }
        }
        if self.layers.airways {
            for a in &self.sector.airways {
                let points: Vec<_> = a
                    .points
                    .iter()
                    .map(|p| project(p[0], p[1], self.zoom, self.pan))
                    .collect();
                painter.add(Shape::line(
                    points,
                    Stroke::new(0.55, Color32::from_rgb(42, 68, 72)),
                ));
            }
        }
        if self.layers.procedures {
            let all: Vec<_> = self
                .sector
                .airports
                .iter()
                .flat_map(|a| a.procedures.iter())
                .collect();
            if let Some(p) = all.get(self.selected_procedure) {
                let points: Vec<_> = p
                    .points
                    .iter()
                    .map(|v| project(v.lon, v.lat, self.zoom, self.pan))
                    .collect();
                painter.add(Shape::line(
                    points.clone(),
                    Stroke::new(1.6, if p.kind == "SID" { CYAN } else { AMBER }),
                ));
                for (v, s) in p.points.iter().zip(points) {
                    painter.circle_filled(s, 2.5, AMBER);
                    painter.text(
                        s + Vec2::new(5.0, -5.0),
                        egui::Align2::LEFT_BOTTOM,
                        &v.id,
                        FontId::monospace(9.0),
                        AMBER,
                    );
                }
            }
        }
        if self.layers.fixes && self.zoom > 1.2 {
            for f in &self.sector.fixes {
                let p = project(f.lon, f.lat, self.zoom, self.pan);
                painter.circle_filled(p, 1.3, Color32::from_rgb(87, 122, 112));
                if self.zoom > 2.5 {
                    painter.text(
                        p + Vec2::new(3.0, 0.0),
                        egui::Align2::LEFT_CENTER,
                        &f.id,
                        FontId::monospace(8.0),
                        Color32::from_rgb(91, 131, 119),
                    );
                }
            }
        }
        if self.layers.navaids {
            for n in &self.sector.navaids {
                let p = project(n.lon, n.lat, self.zoom, self.pan);
                painter.circle_stroke(p, 3.0, Stroke::new(1.0, GREEN));
                painter.text(
                    p + Vec2::new(5.0, 0.0),
                    egui::Align2::LEFT_CENTER,
                    &n.id,
                    FontId::monospace(9.0),
                    GREEN,
                );
            }
        }
        for a in &self.sector.airports {
            let p = project(a.lon, a.lat, self.zoom, self.pan);
            if self.layers.ground && self.zoom > 18.0 {
                for pavement in &a.ground.pavements {
                    let points: Vec<_> = pavement
                        .points
                        .iter()
                        .map(|v| project(v[0], v[1], self.zoom, self.pan))
                        .collect();
                    if points.len() > 2 {
                        painter.add(Shape::closed_line(
                            points,
                            Stroke::new(1.0, Color32::from_rgb(72, 91, 92)),
                        ));
                    }
                }
                let nodes: std::collections::HashMap<_, _> = a
                    .ground
                    .taxi_nodes
                    .iter()
                    .map(|node| (node.id.as_str(), node))
                    .collect();
                for edge in &a.ground.taxi_edges {
                    if let (Some(from), Some(to)) =
                        (nodes.get(edge.from.as_str()), nodes.get(edge.to.as_str()))
                    {
                        let p1 = project(from.lon, from.lat, self.zoom, self.pan);
                        let p2 = project(to.lon, to.lat, self.zoom, self.pan);
                        painter.line_segment(
                            [p1, p2],
                            Stroke::new(2.0, Color32::from_rgb(125, 133, 96)),
                        );
                        if self.zoom > 70.0 && !edge.name.is_empty() {
                            painter.text(
                                p1 + (p2 - p1) * 0.5,
                                egui::Align2::CENTER_CENTER,
                                &edge.name,
                                FontId::monospace(8.0),
                                AMBER,
                            );
                        }
                    }
                }
            }
            for r in &a.runways {
                painter.line_segment(
                    [p, project(r.lon, r.lat, self.zoom, self.pan)],
                    Stroke::new(1.2, TEXT),
                );
            }
            painter.circle_filled(p, 2.5, TEXT);
            painter.text(
                p + Vec2::new(5.0, -3.0),
                egui::Align2::LEFT_BOTTOM,
                &a.id,
                FontId::monospace(10.0),
                TEXT,
            );
            if response.double_clicked() {
                if let Some(cursor) = response.interact_pointer_pos() {
                    if cursor.distance(p) < 18.0 {
                        let target_zoom = 110.0;
                        let base_x = ((a.lon - b.west) / (b.east - b.west)) as f32;
                        let base_y = ((b.north - a.lat) / (b.north - b.south)) as f32;
                        self.zoom = target_zoom;
                        self.pan = Vec2::new(
                            -rect.width() * (base_x - 0.5) * target_zoom,
                            -rect.height() * (base_y - 0.5) * target_zoom,
                        );
                        self.message = format!("{} AIRPORT DIAGRAM / GROUND MODE", a.id);
                    }
                }
            }
        }
        for a in &self.snapshot.aircraft {
            if let (Some(lat), Some(lon)) = (a.latitude, a.longitude) {
                let p = project(lon, lat, self.zoom, self.pan);
                let color = if a.id == self.selected_aircraft {
                    AMBER
                } else if a.radio_tuned {
                    GREEN
                } else {
                    CYAN
                };
                let angle = (a.heading.unwrap_or(0.0) as f32).to_radians();
                let dir = Vec2::angled(angle - std::f32::consts::FRAC_PI_2);
                painter.line_segment([p - dir * 5.0, p + dir * 5.0], Stroke::new(2.0, color));
                painter.line_segment([p, p + Vec2::new(20.0, 18.0)], Stroke::new(1.0, color));
                painter.text(
                    p + Vec2::new(23.0, 13.0),
                    egui::Align2::LEFT_TOP,
                    format!(
                        "{}\n{:03.0} {:03.0}",
                        a.callsign,
                        a.altitude.unwrap_or(0.0) / 100.0,
                        a.ground_speed.unwrap_or(0.0)
                    ),
                    FontId::monospace(10.0),
                    color,
                );
                if response.clicked() {
                    if let Some(cursor) = response.interact_pointer_pos() {
                        if cursor.distance(p) < 12.0 {
                            self.selected_aircraft = a.id.clone();
                        }
                    }
                }
            }
        }
        for vector in self.radar_vectors.iter().chain(
            self.vector_start
                .zip(self.vector_preview)
                .map(|(start, end)| RadarVector {
                    start,
                    end,
                    aircraft_id: self.selected_aircraft.clone(),
                })
                .iter(),
        ) {
            let start = project(vector.start[0], vector.start[1], self.zoom, self.pan);
            let end = project(vector.end[0], vector.end[1], self.zoom, self.pan);
            let delta = end - start;
            if delta.length() < 2.0 {
                continue;
            }
            let dir = delta.normalized();
            painter.line_segment([start, end], Stroke::new(1.8, AMBER));
            painter.line_segment(
                [end, end - dir * 10.0 + Vec2::new(-dir.y, dir.x) * 5.0],
                Stroke::new(1.8, AMBER),
            );
            painter.line_segment(
                [end, end - dir * 10.0 - Vec2::new(-dir.y, dir.x) * 5.0],
                Stroke::new(1.8, AMBER),
            );
            let heading = ((delta.x.atan2(-delta.y).to_degrees() + 360.0) % 360.0).round();
            let label = self
                .snapshot
                .aircraft
                .iter()
                .find(|a| a.id == vector.aircraft_id)
                .map(|a| format!("{}  HDG {:03.0}", a.callsign, heading))
                .unwrap_or_else(|| format!("HDG {:03.0}", heading));
            painter.text(
                (start + delta * 0.5) + Vec2::new(5.0, -5.0),
                egui::Align2::LEFT_BOTTOM,
                label,
                FontId::monospace(10.0),
                AMBER,
            );
        }
    }
}

fn session_path() -> Option<PathBuf> {
    directories::ProjectDirs::from("com", "JCars", "JScope")
        .map(|p| p.data_local_dir().join("session.json"))
}
fn load_session() -> Option<PersistedSession> {
    let p = session_path()?;
    serde_json::from_slice(&fs::read(p).ok()?).ok()
}
fn load_sector() -> Sector {
    let mut paths = Vec::new();
    if let Ok(p) = std::env::var("JSCOPE_SECTOR_PATH") {
        paths.push(PathBuf::from(p))
    }
    paths.push(PathBuf::from("public/generated/nttr-sector.json"));
    if let Ok(exe) = std::env::current_exe() {
        if let Some(dir) = exe.parent() {
            paths.push(dir.join("nttr-sector.json"));
            paths.push(dir.join("data/nttr-sector.json"));
        }
    }
    for p in paths {
        if let Ok(bytes) = fs::read(p) {
            if let Ok(sector) = serde_json::from_slice(&bytes) {
                return sector;
            }
        }
    }
    Sector {
        metadata: SectorMetadata {
            cycle: "NO DATA".into(),
            bounds: Bounds {
                west: -118.2,
                east: -114.6,
                south: 35.7,
                north: 38.5,
            },
        },
        ..Default::default()
    }
}
