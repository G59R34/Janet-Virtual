"use client";
import {useEffect,useState} from "react";
import Link from "next/link";
import {ArrowRight,Clock3,Plane,Radio,TowerControl} from "lucide-react";
import {MapboxNetworkMap} from "@/components/mapbox-network-map";
import type {PublicOperationsSnapshot} from "@/lib/public-operations";

const formatTime=(value:string)=>new Intl.DateTimeFormat("en-US",{hour:"2-digit",minute:"2-digit",hour12:false,timeZone:"America/Los_Angeles"}).format(new Date(value));
const statusLabel=(status:string)=>status.replaceAll("_"," ").toUpperCase();

export function PublicOperationsLive({initial,token}:{initial:PublicOperationsSnapshot;token:string}){
 const [snapshot,setSnapshot]=useState(initial);const [connected,setConnected]=useState(initial.feedAvailable);
 useEffect(()=>{let active=true;let timeout:number|undefined;const refresh=async()=>{try{const response=await fetch("/api/public/operations",{cache:"no-store"});if(!response.ok)throw new Error();const next=await response.json() as PublicOperationsSnapshot;if(active){setSnapshot(next);setConnected(next.feedAvailable)}}catch{if(active)setConnected(false)}finally{if(active)timeout=window.setTimeout(refresh,5000)}};void refresh();return()=>{active=false;if(timeout)window.clearTimeout(timeout)}},[]);
 const updated=formatTime(snapshot.generatedAt);
 return <>
  <section className="live-operations" aria-labelledby="live-operations-title">
   <div className="section-head live-heading"><div><span className="kicker"><Radio size={13}/> LIVE OPERATIONS / JCARS TRACKING</span><h2 id="live-operations-title">The network, in motion.</h2></div><div className={`feed-state ${connected?"online":"offline"}`}><span className="pulse"/>{connected?"FEED ONLINE":"RECONNECTING"} · {updated} PT</div></div>
   <div className="live-layout">
    <div className="home-map"><MapboxNetworkMap token={token} stations={snapshot.stations} routes={snapshot.routes} positions={snapshot.positions}/><span className="map-policy">LIVE JCARS FEED · UPDATES EVERY 5 SEC</span></div>
    <aside className="pilot-board"><div className="pilot-board-head"><div><span className="kicker">LIVE PILOTS</span><h3>{snapshot.metrics.pilotsOnline.toString().padStart(2,"0")} connected</h3></div><TowerControl/></div>
     <div className="pilot-list">{snapshot.positions.length?snapshot.positions.map(position=><article key={position.flightId}><span className="aircraft-glyph"><Plane size={15}/></span><div><strong>{position.callsign}</strong><small>{position.origin} → {position.destination}</small></div><div className="pilot-telemetry"><b>{position.altitude.toLocaleString()} FT</b><small>{position.groundSpeed} KT · {position.heading.toString().padStart(3,"0")}°</small></div></article>):<div className="quiet-state"><Radio/><strong>{connected?"No flights being tracked":"Tracking feed unavailable"}</strong><p>{connected?"JCars is connected and monitoring for the next movement.":"The live tracking database function has not been deployed."}</p></div>}</div>
     <Link href="/ops/map" className="board-link">Open full operations board <ArrowRight size={14}/></Link>
    </aside>
   </div>
  </section>
  <section className="operations movement-section"><div className="section-head"><div><span className="kicker">TODAY / PUBLIC MOVEMENTS</span><h2>Movement board</h2></div><span className="board-time"><Clock3 size={13}/> Times shown in Pacific</span></div><div className="flight-table"><div className="tr th"><span>CALLSIGN</span><span>ORIGIN</span><span>DESTINATION</span><span>STD</span><span>STATUS</span></div>{snapshot.movements.length?snapshot.movements.slice(0,8).map(flight=><div className="tr" key={flight.id}><strong>{flight.callsign}</strong><span>{flight.origin}</span><span>{flight.destination}</span><span>{formatTime(flight.departure)}</span><span className={`status ${flight.status}`}>{statusLabel(flight.status)}</span></div>):<div className="home-empty"><strong>No public movements scheduled.</strong><span>Schedule generation may not have run for today yet.</span></div>}</div></section>
 </>
}
