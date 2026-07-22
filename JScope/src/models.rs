use serde::{Deserialize, Serialize};

#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Position {
    pub id: String,
    pub display_name: String,
    pub radio_callsign: String,
    pub display_frequency: String,
    pub channel_id: String,
}
#[derive(Clone, Default, Deserialize, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct ControllerSession {
    pub session_id: String,
    pub token: String,
    pub expires_at: String,
    pub callsign: Option<String>,
    pub positions: Vec<Position>,
}
#[derive(Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Aircraft {
    pub id: String,
    pub callsign: String,
    pub aircraft_type: Option<String>,
    pub latitude: Option<f64>,
    pub longitude: Option<f64>,
    pub altitude: Option<f64>,
    pub ground_speed: Option<f64>,
    pub heading: Option<f64>,
    pub vertical_speed: Option<f64>,
    pub origin: String,
    pub destination: String,
    pub communications_status: String,
    pub com1_active: Option<f64>,
    pub com2_active: Option<f64>,
    pub transponder_code: Option<f64>,
    pub required_frequency: String,
    pub radio_tuned: bool,
}
#[derive(Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Snapshot {
    pub generated_at: String,
    pub aircraft: Vec<Aircraft>,
    pub positions: Vec<Position>,
}
#[derive(Clone, Default, Deserialize, Serialize)]
pub struct AuthSession {
    pub access_token: String,
    pub refresh_token: String,
    pub expires_at: i64,
}
#[derive(Clone, Default, Deserialize, Serialize)]
pub struct PersistedSession {
    pub auth: AuthSession,
    pub controller: Option<ControllerSession>,
    pub position_session: String,
    pub selected_position: String,
}
#[derive(Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VoiceGrant {
    pub room_id: String,
    pub operation_id: String,
    pub position_id: String,
    pub status: String,
    pub transport_mode: String,
    pub credential: String,
    pub credential_expires_at: String,
    pub subject_id: String,
}
#[derive(Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct VoiceParticipant {
    pub subject_id: String,
    pub callsign: String,
    pub role: String,
    pub state: String,
    pub mode: Option<String>,
    pub quality: Option<i64>,
    pub transmitting: bool,
}
#[derive(Clone, Default, Deserialize)]
pub struct VoicePoll {
    pub events: Vec<serde_json::Value>,
    pub participants: Vec<VoiceParticipant>,
}
#[derive(Clone, Default, Deserialize)]
pub struct VoiceHostResponse {
    pub radio: VoiceGrant,
    pub central: CentralVoiceGrant,
}
#[derive(Clone, Default, Deserialize)]
pub struct CentralVoiceGrant {
    pub mode: String,
    pub url: String,
    pub token: String,
    pub room_name: String,
    pub expires_in: i64,
}

#[derive(Clone, Default, Deserialize)]
pub struct VatsimController {
    pub callsign: String,
    pub frequency: String,
}

#[derive(Clone, Default, Deserialize)]
pub struct VatsimFeed {
    #[serde(default)]
    pub controllers: Vec<VatsimController>,
}

#[derive(Clone, Default, Deserialize)]
pub struct SectorMetadata {
    pub cycle: String,
    pub bounds: Bounds,
}
#[derive(Clone, Default, Deserialize)]
pub struct Bounds {
    pub west: f64,
    pub east: f64,
    pub south: f64,
    pub north: f64,
}
#[derive(Clone, Default, Deserialize)]
pub struct GeoPoint {
    pub id: String,
    pub lat: f64,
    pub lon: f64,
}
#[derive(Clone, Default, Deserialize)]
pub struct Procedure {
    pub kind: String,
    pub name: String,
    pub transition: String,
    pub points: Vec<GeoPoint>,
}
#[derive(Clone, Default, Deserialize)]
pub struct Airport {
    pub id: String,
    pub lat: f64,
    pub lon: f64,
    pub elevation: f64,
    pub runways: Vec<GeoPoint>,
    pub procedures: Vec<Procedure>,
    #[serde(default)]
    pub ground: GroundLayout,
}
#[derive(Clone, Default, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct GroundLayout {
    pub pavements: Vec<GroundPath>,
    pub taxi_nodes: Vec<GroundNode>,
    pub taxi_edges: Vec<GroundEdge>,
}
#[derive(Clone, Default, Deserialize)]
pub struct GroundPath {
    pub name: String,
    pub points: Vec<[f64; 2]>,
}
#[derive(Clone, Default, Deserialize)]
pub struct GroundNode {
    pub id: String,
    pub lat: f64,
    pub lon: f64,
}
#[derive(Clone, Default, Deserialize)]
pub struct GroundEdge {
    pub from: String,
    pub to: String,
    pub name: String,
}
#[derive(Clone, Default, Deserialize)]
pub struct Navaid {
    pub id: String,
    pub lat: f64,
    pub lon: f64,
    pub frequency: f64,
    pub name: String,
}
#[derive(Clone, Default, Deserialize)]
pub struct Airway {
    pub name: String,
    pub points: Vec<[f64; 2]>,
}
#[derive(Clone, Default, Deserialize)]
pub struct Airspace {
    pub name: String,
    pub lower: String,
    pub upper: String,
    pub points: Vec<[f64; 2]>,
}
#[derive(Clone, Default, Deserialize)]
pub struct Sector {
    pub metadata: SectorMetadata,
    pub airports: Vec<Airport>,
    pub fixes: Vec<GeoPoint>,
    pub navaids: Vec<Navaid>,
    pub airways: Vec<Airway>,
    pub airspaces: Vec<Airspace>,
}
