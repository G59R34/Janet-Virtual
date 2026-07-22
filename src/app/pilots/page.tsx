import Link from "next/link";
import {Users} from "lucide-react";
import {Footer} from "@/app/page";
import {PilotCards} from "@/components/pilot-cards";
import {getPublicPilots} from "@/lib/pilot-directory";

export default async function PilotsPage(){const pilots=await getPublicPilots();return <><header className="topbar"><Link className="brand" href="/"><span>JANET</span><small>VIRTUAL AIRLINES</small></Link><nav><Link href="/about">About</Link><Link href="/fleet">Fleet</Link><Link href="/network">Network</Link><Link href="/pilots">Pilots</Link><Link href="/statistics">Statistics</Link></nav><Link href="/login" className="button ghost">Employee access</Link></header><main><section className="data-hero pilot-hero"><div><span className="eyebrow">PUBLIC DIRECTORY / PILOTS</span><h1>The people behind the callsigns.</h1><p>Meet the members who choose to share their JANET Virtual pilot profiles with the community.</p></div><Users size={70}/></section><section className="public-pilots"><div className="section-head"><div><span className="kicker">VOLUNTARY PUBLIC PROFILES</span><h2>{pilots.length} pilot{pilots.length===1?"":"s"}</h2></div></div>{pilots.length?<PilotCards pilots={pilots}/>:<div className="data-empty">No pilots have published their profiles yet.</div>}</section></main><Footer/></>}
