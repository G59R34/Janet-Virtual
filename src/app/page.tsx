import Link from "next/link";
import { ArrowRight, Radio, ShieldCheck, Plane, Clock3 } from "lucide-react";

const flights = [
  ["JANET11", "LAS", "STN 3", "03:40", "ON TIME"],
  ["JANET55", "LAS", "STN 7", "04:05", "BOARDING"],
  ["JANET29", "PMD", "STN 3", "08:30", "SCHEDULED"],
];

export default function Home() {
  return <>
    <header className="topbar"><Link className="brand" href="/"><span>JANET</span><small>VIRTUAL AIRLINES</small></Link><nav><Link href="/about">About</Link><Link href="/fleet">Fleet</Link><Link href="/network">Network</Link><Link href="/statistics">Statistics</Link></nav><Link href="/login" className="button ghost">Employee access</Link></header>
    <main>
      <section className="hero"><div className="eyebrow"><Radio size={14}/> OPERATIONS NETWORK / WESTERN REGION</div><h1>Personnel transport.<br/><em>Precisely coordinated.</em></h1><p>Join a disciplined flight-simulation community built around commuter schedules, special movements, dispatch standards, and persistent airline operations.</p><div className="actions"><Link href="/apply" className="button primary">Submit application <ArrowRight size={16}/></Link><Link href="/ops/map" className="button">View public operations</Link></div><div className="hero-meta"><span><b>21</b> weekday rotations</span><span><b>02</b> fleet categories</span><span><b>09</b> primary stations</span></div></section>
      <section className="status-strip"><div><span className="pulse"/> SYSTEM STATUS</div><b>ALL SERVICES NOMINAL</b><span>UPDATED 23:41Z</span></section>
      <section className="operations"><div className="section-head"><div><span className="kicker">TODAY / COMMUTER PROGRAM</span><h2>Movement board</h2></div><Link href="/ops/map">Open live board <ArrowRight size={14}/></Link></div><div className="flight-table"><div className="tr th"><span>CALLSIGN</span><span>ORIGIN</span><span>DESTINATION</span><span>STD</span><span>STATUS</span></div>{flights.map((f)=><div className="tr" key={f[0]}><strong>{f[0]}</strong><span>{f[1]}</span><span>{f[2]}</span><span>{f[3]}L</span><span className={`status ${f[4].toLowerCase().replace(" ", "-")}`}>{f[4]}</span></div>)}</div></section>
      <section className="feature-grid"><article><Plane/><span>01 / OPERATIONS</span><h3>More than a flight list.</h3><p>Aircraft, personnel, missions, maintenance, and schedules remain connected as the network moves.</p></article><article><ShieldCheck/><span>02 / STANDARDS</span><h3>Qualification matters.</h3><p>Assignments validate role, rank, currency, aircraft qualification, and operational conflicts.</p></article><article><Clock3/><span>03 / CONTINUITY</span><h3>A persistent system.</h3><p>Flights update aircraft location, crew records, utilization, and fictional personnel movement.</p></article></section>
    </main><Footer/>
  </>;
}

export function Footer(){return <footer><div className="brand"><span>JANET</span><small>VIRTUAL AIRLINES</small></div><p>Independent flight-simulation community. Not affiliated with JANET, the U.S. Government, military, contractors, or any real-world organization.</p><span>© 2026 JVA ECOSYSTEM</span></footer>}
