import Link from "next/link";
import { ArrowRight, Radio, ShieldCheck, Plane, Clock3 } from "lucide-react";
import {getPublicOperations} from "@/lib/public-operations";
import {PublicOperationsLive} from "@/components/public-operations-live";

export default async function Home() {
  const operations=await getPublicOperations();
  return <>
    <header className="topbar"><Link className="brand" href="/"><span>JANET</span><small>VIRTUAL AIRLINES</small></Link><nav><Link href="/about">About</Link><Link href="/fleet">Fleet</Link><Link href="/network">Network</Link><Link href="/pilots">Pilots</Link><Link href="/statistics">Statistics</Link></nav><Link href="/login" className="button ghost">Employee access</Link></header>
    <main>
      <section className="hero"><div className="eyebrow"><Radio size={14}/> OPERATIONS NETWORK / WESTERN REGION</div><h1>Personnel transport.<br/><em>Precisely coordinated.</em></h1><p>Fly a living, persistent schedule where every movement updates the network—from dispatch and crew assignment to aircraft location and pilot records.</p><div className="actions"><Link href="/apply" className="button primary">Submit application <ArrowRight size={16}/></Link><Link href="#live-network" className="button">Track the network</Link></div><div className="hero-meta"><span><b>{operations.metrics.todayMovements.toString().padStart(2,"0")}</b> movements today</span><span><b>{operations.metrics.fleetSize.toString().padStart(2,"0")}</b> active aircraft</span><span><b>{operations.metrics.stations.toString().padStart(2,"0")}</b> public stations</span></div></section>
      <section className="status-strip"><div><span className="pulse"/> OPERATIONS FEED</div><b>{operations.metrics.activeFlights?`${operations.metrics.activeFlights} ACTIVE MOVEMENT${operations.metrics.activeFlights===1?"":"S"}`:"NETWORK MONITORING"}</b><span>{operations.metrics.pilotsOnline} PILOT{operations.metrics.pilotsOnline===1?"":"S"} CONNECTED</span></section>
      <div id="live-network"><PublicOperationsLive initial={operations} token={process.env.NEXT_PUBLIC_MAPBOX_ACCESS_TOKEN??""}/></div>
      <section className="feature-grid"><article><Plane/><span>01 / OPERATIONS</span><h3>More than a flight list.</h3><p>Aircraft, personnel, missions, maintenance, and schedules remain connected as the network moves.</p></article><article><ShieldCheck/><span>02 / STANDARDS</span><h3>Qualification matters.</h3><p>Assignments validate role, rank, currency, aircraft qualification, and operational conflicts.</p></article><article><Clock3/><span>03 / CONTINUITY</span><h3>A persistent system.</h3><p>Flights update aircraft location, crew records, utilization, and fictional personnel movement.</p></article></section>
    </main><Footer/>
  </>;
}

export function Footer(){return <footer><div className="brand"><span>JANET</span><small>VIRTUAL AIRLINES</small></div><p>Independent flight-simulation community. Not affiliated with JANET, the U.S. Government, military, contractors, or any real-world organization.</p><span>© 2026 JVA ECOSYSTEM</span></footer>}
