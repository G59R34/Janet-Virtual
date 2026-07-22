import {createClient} from "@/lib/supabase/server";
import {PilotCards} from "@/components/pilot-cards";
import type {PilotDirectoryEntry} from "@/lib/pilot-directory";

export async function InternalPilots(){const db=await createClient();const {data,error}=await db.rpc("get_internal_pilots");const pilots=(data??[]) as PilotDirectoryEntry[];return <div className="internal-pilots"><section className="module-intro"><div><span className="kicker">INTERNAL CREW DIRECTORY</span><h2>All pilots</h2><p>Current pilot roster, operational identities, network IDs, and activity totals. This directory is available to signed-in members only.</p></div></section>{error?<div className="notice"><strong>Unable to load pilot directory.</strong><p>{error.message}</p></div>:pilots.length?<PilotCards pilots={pilots} internal/>:<div className="data-empty">No active pilots were found.</div>}</div>}
