use crate::{
    api_native::Api,
    models::{AuthSession, CentralVoiceGrant, VoiceGrant},
};
use bytes::Bytes;
use cpal::traits::{DeviceTrait, HostTrait, StreamTrait};
use ropus::{Application, Channels, DecodeMode, Decoder, Encoder};
use serde_json::{Value, json};
use std::{
    collections::{HashMap, VecDeque},
    sync::{
        Arc, Mutex,
        atomic::{AtomicBool, AtomicI64, Ordering},
    },
    thread,
    time::{Duration, SystemTime},
};
use tokio::{net::UdpSocket, runtime::Runtime, sync::mpsc};
use livekit::prelude::{LocalAudioTrack, LocalTrack, PlatformAudio, Room, RoomOptions};
use webrtc::{
    api::{APIBuilder, media_engine::MediaEngine, setting_engine::SettingEngine},
    ice::{
        udp_mux::{UDPMuxDefault, UDPMuxParams},
        udp_network::UDPNetwork,
    },
    ice_transport::ice_candidate::RTCIceCandidateInit,
    media::Sample,
    peer_connection::{
        RTCPeerConnection, configuration::RTCConfiguration,
        peer_connection_state::RTCPeerConnectionState,
        sdp::session_description::RTCSessionDescription,
    },
    rtp_transceiver::rtp_codec::RTCRtpCodecCapability,
    track::track_local::{TrackLocal, track_local_static_sample::TrackLocalStaticSample},
};

pub enum VoiceCommand {
    Start(Api, AuthSession, VoiceGrant),
    StartCentral(CentralVoiceGrant),
    Events(Vec<Value>),
    Stop,
    Ptt(bool),
}
#[derive(Clone, Debug)]
pub enum VoiceEngineState {
    Offline,
    Listening,
    Connecting,
    Connected,
    Central,
    Failed(String),
}
pub struct VoiceEngine {
    tx: mpsc::UnboundedSender<VoiceCommand>,
    rx: std::sync::mpsc::Receiver<VoiceEngineState>,
}
impl VoiceEngine {
    pub fn new() -> Self {
        let (tx, mut commands) = mpsc::unbounded_channel();
        let (state_tx, rx) = std::sync::mpsc::channel();
        thread::spawn(move || {
            Runtime::new().expect("voice runtime").block_on(async move {
                let mut context: Option<Context> = None;
                let mut central: Option<CentralContext> = None;
                while let Some(command) = commands.recv().await {
                    match command {
                        VoiceCommand::StartCentral(grant) => {
                            if central.as_ref().is_some_and(|active| active.room_name == grant.room_name) {
                                let _ = state_tx.send(VoiceEngineState::Connected);
                                continue;
                            }
                            if let Some(mut active) = context.take() { active.shutdown().await; }
                            if let Some(active) = central.take() { let _ = active.room.close().await; }
                            match CentralContext::new(grant).await {
                                Ok(v) => { central = Some(v); let _ = state_tx.send(VoiceEngineState::Central); }
                                Err(e) => { let _ = state_tx.send(VoiceEngineState::Failed(e)); }
                            }
                        }
                        VoiceCommand::Start(api, auth, grant) => {
                            if let Some(active) = central.take() { let _ = active.room.close().await; }
                            if context
                                .as_ref()
                                .is_some_and(|active| active.grant.room_id == grant.room_id)
                            {
                                let _ = state_tx.send(VoiceEngineState::Listening);
                                continue;
                            }
                            if let Some(mut active) = context.take() {
                                active.shutdown().await;
                            }
                            match Context::new(api, auth, grant, state_tx.clone()).await {
                                Ok(v) => {
                                    context = Some(v);
                                    let _ = state_tx.send(VoiceEngineState::Listening);
                                }
                                Err(e) => {
                                    let _ = state_tx.send(VoiceEngineState::Failed(e));
                                }
                            }
                        }
                        VoiceCommand::Events(events) => {
                            if let Some(ctx) = context.as_mut() {
                                for event in events {
                                    if let Err(e) = ctx.event(event).await {
                                        let _ = state_tx.send(VoiceEngineState::Failed(e));
                                    }
                                }
                            }
                        }
                        VoiceCommand::Stop => {
                            if let Some(mut active) = context.take() {
                                active.shutdown().await;
                            }
                            if let Some(active) = central.take() { let _ = active.room.close().await; }
                            let _ = state_tx.send(VoiceEngineState::Offline);
                        }
                        VoiceCommand::Ptt(active) => {
                            if let Some(ctx) = central.as_ref() {
                                ctx.set_ptt(active)
                            } else if let Some(ctx) = context.as_ref() {
                                ctx.set_ptt(active).await
                            }
                        }
                    }
                }
            })
        });
        Self { tx, rx }
    }
    pub fn start(&self, api: Api, auth: AuthSession, grant: VoiceGrant) {
        let _ = self.tx.send(VoiceCommand::Start(api, auth, grant));
    }
    pub fn start_central(&self, grant: CentralVoiceGrant) {
        let _ = self.tx.send(VoiceCommand::StartCentral(grant));
    }
    pub fn events(&self, events: Vec<Value>) {
        let _ = self.tx.send(VoiceCommand::Events(events));
    }
    pub fn stop(&self) {
        let _ = self.tx.send(VoiceCommand::Stop);
    }
    pub fn ptt(&self, active: bool) {
        let _ = self.tx.send(VoiceCommand::Ptt(active));
    }
    pub fn updates(&self) -> impl Iterator<Item = VoiceEngineState> + '_ {
        self.rx.try_iter()
    }
}
struct CentralContext {
    room_name: String,
    room: Room,
    track: LocalAudioTrack,
    _audio: PlatformAudio,
}
impl CentralContext {
    async fn new(grant: CentralVoiceGrant) -> Result<Self, String> {
        if grant.mode != "central" || grant.url.is_empty() || grant.token.is_empty() { return Err("Invalid central voice grant".into()); }
        let audio = PlatformAudio::new().map_err(|e| e.to_string())?;
        let (room, _) = Room::connect(&grant.url, &grant.token, RoomOptions::default()).await.map_err(|e| e.to_string())?;
        let track = LocalAudioTrack::create_audio_track("jva-radio", audio.rtc_source());
        room.local_participant().publish_track(LocalTrack::Audio(track.clone()), Default::default()).await.map_err(|e| e.to_string())?;
        track.mute();
        Ok(Self { room_name: grant.room_name, room, track, _audio: audio })
    }
    fn set_ptt(&self, active: bool) { if active { self.track.unmute(); } else { self.track.mute(); } }
}
struct Context {
    api: Api,
    auth: AuthSession,
    grant: VoiceGrant,
    webrtc: webrtc::api::API,
    peers: HashMap<String, Arc<RTCPeerConnection>>,
    sequence: Arc<AtomicI64>,
    state: std::sync::mpsc::Sender<VoiceEngineState>,
    track: Arc<TrackLocalStaticSample>,
    ptt: Arc<AtomicBool>,
    output_queue: Arc<Mutex<VecDeque<f32>>>,
    _input: cpal::Stream,
    _output: cpal::Stream,
}
impl Context {
    async fn shutdown(&mut self) {
        self.ptt.store(false, Ordering::SeqCst);
        for (_, peer) in self.peers.drain() {
            let _ = peer.close().await;
        }
    }

    async fn set_ptt(&self, active: bool) {
        self.ptt.store(active, Ordering::SeqCst);
        let seq = self.sequence.fetch_add(1, Ordering::SeqCst) + 1;
        let kind = if active {
            "radio.ptt.start"
        } else {
            "radio.ptt.stop"
        };
        let _ = self.api.voice_signal(
            &self.auth,
            &self.grant,
            seq,
            kind,
            &self.grant.subject_id,
            json!({}),
        );
    }
    async fn new(
        api: Api,
        auth: AuthSession,
        grant: VoiceGrant,
        state: std::sync::mpsc::Sender<VoiceEngineState>,
    ) -> Result<Self, String> {
        let socket = UdpSocket::bind(("0.0.0.0", 30814))
            .await
            .map_err(|e| format!("UDP 30814: {e}"))?;
        let mux = UDPMuxDefault::new(UDPMuxParams::new(socket));
        let mut settings = SettingEngine::default();
        settings.set_udp_network(UDPNetwork::Muxed(mux));
        let mut media = MediaEngine::default();
        media.register_default_codecs().map_err(|e| e.to_string())?;
        let webrtc = APIBuilder::new()
            .with_setting_engine(settings)
            .with_media_engine(media)
            .build();
        let track = Arc::new(TrackLocalStaticSample::new(
            RTCRtpCodecCapability {
                mime_type: "audio/opus".into(),
                clock_rate: 48000,
                channels: 1,
                ..Default::default()
            },
            "jscope-audio".into(),
            "jscope-radio".into(),
        ));
        let ptt = Arc::new(AtomicBool::new(false));
        let output_queue = Arc::new(Mutex::new(VecDeque::new()));
        let (input, output) = start_audio(track.clone(), ptt.clone(), output_queue.clone())?;
        Ok(Self {
            api,
            auth,
            grant,
            webrtc,
            peers: HashMap::new(),
            sequence: Arc::new(AtomicI64::new(0)),
            state,
            track,
            ptt,
            output_queue,
            _input: input,
            _output: output,
        })
    }
    async fn event(&mut self, event: Value) -> Result<(), String> {
        let kind = event.get("type").and_then(Value::as_str).unwrap_or("");
        let sender = event
            .get("senderId")
            .and_then(Value::as_str)
            .ok_or("Voice sender missing")?
            .to_owned();
        let payload = event.get("payload").cloned().unwrap_or_else(|| json!({}));
        match kind {
            "radio.signal.offer" => self.offer(sender, payload).await,
            "radio.signal.ice_candidate" => {
                if let Some(peer) = self.peers.get(&sender) {
                    let candidate: RTCIceCandidateInit = serde_json::from_value(
                        payload
                            .get("candidate")
                            .cloned()
                            .ok_or("ICE candidate missing")?,
                    )
                    .map_err(|e| e.to_string())?;
                    peer.add_ice_candidate(candidate)
                        .await
                        .map_err(|e| e.to_string())?;
                }
                Ok(())
            }
            "radio.member.leave" => {
                if let Some(peer) = self.peers.remove(&sender) {
                    peer.close().await.map_err(|e| e.to_string())?;
                }
                Ok(())
            }
            _ => Ok(()),
        }
    }
    async fn offer(&mut self, sender: String, payload: Value) -> Result<(), String> {
        if let Some(old) = self.peers.remove(&sender) {
            let _ = old.close().await;
        }
        let peer = Arc::new(
            self.webrtc
                .new_peer_connection(RTCConfiguration::default())
                .await
                .map_err(|e| e.to_string())?,
        );
        peer.add_track(self.track.clone() as Arc<dyn TrackLocal + Send + Sync>)
            .await
            .map_err(|e| e.to_string())?;
        let output = self.output_queue.clone();
        peer.on_track(Box::new(move |track, _, _| {
            let output = output.clone();
            Box::pin(async move {
                let mut decoder = match Decoder::new(48_000, Channels::Mono) {
                    Ok(v) => v,
                    Err(_) => return,
                };
                let mut pcm = vec![0.0f32; 5760];
                while let Ok((packet, _)) = track.read_rtp().await {
                    if let Ok(samples) =
                        decoder.decode_float(&packet.payload, &mut pcm, DecodeMode::Normal)
                    {
                        if let Ok(mut queue) = output.lock() {
                            queue.extend(pcm[..samples].iter().copied());
                            while queue.len() > 96_000 {
                                queue.pop_front();
                            }
                        }
                    }
                }
            })
        }));
        let (api, auth, grant, recipient, sequence) = (
            self.api.clone(),
            self.auth.clone(),
            self.grant.clone(),
            sender.clone(),
            self.sequence.clone(),
        );
        peer.on_ice_candidate(Box::new(move |candidate| {
            let (api, auth, grant, recipient, sequence) = (
                api.clone(),
                auth.clone(),
                grant.clone(),
                recipient.clone(),
                sequence.clone(),
            );
            Box::pin(async move {
                if let Some(candidate) = candidate {
                    if let Ok(value) = candidate.to_json() {
                        let seq = sequence.fetch_add(1, Ordering::SeqCst) + 1;
                        let _ = tokio::task::spawn_blocking(move || {
                            api.voice_signal(
                                &auth,
                                &grant,
                                seq,
                                "radio.signal.ice_candidate",
                                &recipient,
                                json!({"candidate":value}),
                            )
                        })
                        .await;
                    }
                }
            })
        }));
        let (state_sender, api, auth, grant, recipient, sequence) = (
            self.state.clone(),
            self.api.clone(),
            self.auth.clone(),
            self.grant.clone(),
            sender.clone(),
            self.sequence.clone(),
        );
        peer.on_peer_connection_state_change(Box::new(move|state|{let(state_sender,api,auth,grant,recipient,sequence)=(state_sender.clone(),api.clone(),auth.clone(),grant.clone(),recipient.clone(),sequence.clone());Box::pin(async move{let local=match state{RTCPeerConnectionState::Connected=>VoiceEngineState::Connected,RTCPeerConnectionState::Failed|RTCPeerConnectionState::Closed=>VoiceEngineState::Failed(format!("WEBRTC {state}")),_=>VoiceEngineState::Connecting};let _=state_sender.send(local);let seq=sequence.fetch_add(1,Ordering::SeqCst)+1;let value=format!("{state}").to_lowercase();let _=tokio::task::spawn_blocking(move||api.voice_signal(&auth,&grant,seq,"radio.connection.state",&recipient,json!({"state":value,"mode":"direct","quality":if state==RTCPeerConnectionState::Connected{100}else{25}}))).await;})}));
        let offer: RTCSessionDescription =
            serde_json::from_value(payload).map_err(|e| e.to_string())?;
        peer.set_remote_description(offer)
            .await
            .map_err(|e| e.to_string())?;
        let answer = peer.create_answer(None).await.map_err(|e| e.to_string())?;
        peer.set_local_description(answer.clone())
            .await
            .map_err(|e| e.to_string())?;
        let seq = self.sequence.fetch_add(1, Ordering::SeqCst) + 1;
        self.api
            .voice_signal(
                &self.auth,
                &self.grant,
                seq,
                "radio.signal.answer",
                &sender,
                serde_json::to_value(answer).map_err(|e| e.to_string())?,
            )
            .map_err(|e| e.to_string())?;
        self.peers.insert(sender, peer);
        Ok(())
    }
}

fn start_audio(
    track: Arc<TrackLocalStaticSample>,
    ptt: Arc<AtomicBool>,
    output_queue: Arc<Mutex<VecDeque<f32>>>,
) -> Result<(cpal::Stream, cpal::Stream), String> {
    let host = cpal::default_host();
    let input_device = host
        .default_input_device()
        .ok_or("No microphone available")?;
    let output_device = host.default_output_device().ok_or("No speaker available")?;
    let input_supported = input_device
        .default_input_config()
        .map_err(|e| e.to_string())?;
    let input_channels = input_supported.channels() as usize;
    let input_config = cpal::StreamConfig {
        channels: input_supported.channels(),
        sample_rate: 48_000,
        buffer_size: cpal::BufferSize::Default,
    };
    let buffer = Arc::new(Mutex::new(Vec::<f32>::new()));
    let encoder = Arc::new(Mutex::new(
        Encoder::builder(48_000, Channels::Mono, Application::Voip)
            .build()
            .map_err(|e| e.to_string())?,
    ));
    let handle = tokio::runtime::Handle::current();
    let make_callback = move |samples: &[f32]| {
        if let Ok(mut pending) = buffer.lock() {
            for frame in samples.chunks(input_channels) {
                let sample = if ptt.load(Ordering::SeqCst) {
                    frame.iter().sum::<f32>() / input_channels as f32
                } else {
                    0.0
                };
                pending.push(sample);
            }
            while pending.len() >= 960 {
                let pcm: Vec<_> = pending.drain(..960).collect();
                let mut packet = vec![0u8; 1275];
                if let Ok(mut encoder) = encoder.lock() {
                    if let Ok(size) = encoder.encode_float(&pcm, &mut packet) {
                        packet.truncate(size);
                        let track = track.clone();
                        handle.spawn(async move {
                            let _ = track
                                .write_sample(&Sample {
                                    data: Bytes::from(packet),
                                    timestamp: SystemTime::now(),
                                    duration: Duration::from_millis(20),
                                    packet_timestamp: 0,
                                    prev_dropped_packets: 0,
                                    prev_padding_packets: 0,
                                })
                                .await;
                        });
                    }
                }
            }
        }
    };
    let input = match input_supported.sample_format() {
        cpal::SampleFormat::F32 => input_device.build_input_stream(
            &input_config,
            move |data: &[f32], _| make_callback(data),
            move |_| {},
            None,
        ),
        cpal::SampleFormat::I16 => {
            let callback = Arc::new(Mutex::new(make_callback));
            input_device.build_input_stream(
                &input_config,
                move |data: &[i16], _| {
                    let converted: Vec<_> = data.iter().map(|v| *v as f32 / 32768.0).collect();
                    if let Ok(cb) = callback.lock() {
                        cb(&converted)
                    }
                },
                move |_| {},
                None,
            )
        }
        format => return Err(format!("Unsupported microphone format {format}")),
    }
    .map_err(|e| e.to_string())?;
    let output_supported = output_device
        .default_output_config()
        .map_err(|e| e.to_string())?;
    let channels = output_supported.channels() as usize;
    let output_config = cpal::StreamConfig {
        channels: output_supported.channels(),
        sample_rate: 48_000,
        buffer_size: cpal::BufferSize::Default,
    };
    let output = match output_supported.sample_format() {
        cpal::SampleFormat::F32 => output_device.build_output_stream(
            &output_config,
            move |data: &mut [f32], _| {
                if let Ok(mut queue) = output_queue.lock() {
                    for frame in data.chunks_mut(channels) {
                        let value = queue.pop_front().unwrap_or(0.0);
                        frame.fill(value)
                    }
                }
            },
            move |_| {},
            None,
        ),
        format => return Err(format!("Unsupported speaker format {format}")),
    }
    .map_err(|e| e.to_string())?;
    input.play().map_err(|e| e.to_string())?;
    output.play().map_err(|e| e.to_string())?;
    Ok((input, output))
}
