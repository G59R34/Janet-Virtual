import {ConnectionState,Room,RoomEvent,Track} from "livekit-client";
import {jvaApi,type VoiceParticipant,type VoiceRoomGrant} from "./api";

export type VoiceConnectionState={status:"offline"|"connecting"|"direct"|"relayed"|"degraded";room?:VoiceRoomGrant;participants:VoiceParticipant[];activeTransmitter?:string;quality:number};
export interface VoiceTransport{
  connect(acarsSessionId:string,inputDevice:string,outputDevice:string):Promise<void>;
  setPushToTalk(active:boolean):Promise<void>;
  disconnect():Promise<void>;
}

export class WebRTCVoiceTransport implements VoiceTransport{
  private room?:Room;
  private grant?:VoiceRoomGrant;
  private ptt=false;
  private audioElements=new Set<HTMLAudioElement>();
  constructor(private readonly update:(state:VoiceConnectionState)=>void){}

  async connect(acarsSessionId:string,inputDevice:string,outputDevice:string){
    await this.disconnect();
    this.update({status:"connecting",participants:[],quality:0});
    const {radio,central}=await jvaApi.voiceJoin(acarsSessionId);
    this.grant=radio;
    const room=new Room({adaptiveStream:false,dynacast:false});
    this.room=room;
    room.on(RoomEvent.TrackSubscribed,(track)=>{
      if(track.kind!==Track.Kind.Audio)return;
      const element=track.attach() as HTMLAudioElement;
      element.autoplay=true;
      if(outputDevice!=="default"&&"setSinkId" in element)void (element as HTMLAudioElement&{setSinkId(id:string):Promise<void>}).setSinkId(outputDevice);
      this.audioElements.add(element);
    });
    room.on(RoomEvent.TrackUnsubscribed,(track)=>{
      track.detach().forEach(element=>{element.remove();this.audioElements.delete(element as HTMLAudioElement);});
    });
    room.on(RoomEvent.ConnectionStateChanged,()=>this.publishState());
    room.on(RoomEvent.ActiveSpeakersChanged,()=>this.publishState());
    room.on(RoomEvent.ParticipantConnected,()=>this.publishState());
    room.on(RoomEvent.ParticipantDisconnected,()=>this.publishState());
    try{
      await room.connect(central.url,central.token,{autoSubscribe:true});
      // Create the selected radio input once, then mute it until the pilot
      // holds PTT. Subsequent PTT changes only mute/unmute that same track.
      await room.localParticipant.setMicrophoneEnabled(true,{deviceId:inputDevice==="default"?undefined:{exact:inputDevice},echoCancellation:true,noiseSuppression:true,autoGainControl:true});
      await room.localParticipant.setMicrophoneEnabled(false);
      this.publishState();
    }catch(error){
      await this.disconnect();
      throw error;
    }
  }

  private participants():VoiceParticipant[]{
    if(!this.room)return [];
    return [...this.room.remoteParticipants.values()].map(participant=>({subjectId:participant.identity,callsign:participant.name||participant.identity,role:"participant",state:participant.connectionQuality,mode:"central",quality:100,transmitting:this.room?.activeSpeakers.some(speaker=>speaker.identity===participant.identity)??false}));
  }
  private publishState(){
    const room=this.room;
    if(!room||!this.grant)return;
    const connected=room.state===ConnectionState.Connected;
    const active=room.activeSpeakers.find(speaker=>speaker.identity!==room.localParticipant.identity);
    this.update({status:connected?"direct":room.state===ConnectionState.Reconnecting?"connecting":"degraded",room:this.grant,participants:this.participants(),activeTransmitter:active?.name||active?.identity,quality:connected?100:0});
  }
  async setPushToTalk(active:boolean){
    if(active===this.ptt||!this.room)return;
    this.ptt=active;
    await this.room.localParticipant.setMicrophoneEnabled(active);
    this.publishState();
  }
  async disconnect(){
    this.ptt=false;
    for(const element of this.audioElements)element.remove();
    this.audioElements.clear();
    this.room?.disconnect();this.room=undefined;this.grant=undefined;
    this.update({status:"offline",participants:[],quality:0});
  }
}
