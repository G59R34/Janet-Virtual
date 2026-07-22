import Link from "next/link";
import {Award,Coins,Gauge,Target} from "lucide-react";
import {createClient} from "@/lib/supabase/server";

type Progression={grade_code:string;accepted_sectors:number;accepted_minutes:number;proficiency:number;credit_balance:number;distinct_routes:number};
type Rank={code:string;name:string;minimum_hours:number;minimum_sectors:number;minimum_proficiency:number;sort_order:number};
type Objective={id:string;title:string;target:number;progress:number;credit_reward:number;completed_at:string|null};
type Achievement={achievement_code:string;awarded_at:string;definition:{name:string}|null};

export async function ProgressionOverview({userId}:{userId:string}){
 const db=await createClient();
 const monday=new Date();monday.setDate(monday.getDate()-((monday.getDay()+6)%7));monday.setHours(0,0,0,0);
 const [{data:progression},{data:ranks},{data:objectives},{data:achievements}]=await Promise.all([
  db.from("pilot_progression").select("grade_code,accepted_sectors,accepted_minutes,proficiency,credit_balance,distinct_routes").eq("user_id",userId).maybeSingle(),
  db.from("ranks").select("code,name,minimum_hours,minimum_sectors,minimum_proficiency,sort_order").eq("active",true).order("sort_order"),
  db.from("pilot_weekly_objectives").select("id,title,target,progress,credit_reward,completed_at").eq("user_id",userId).eq("week_start",monday.toISOString().slice(0,10)).order("created_at"),
  db.from("pilot_achievements").select("achievement_code,awarded_at,definition:achievement_definitions(name)").eq("user_id",userId).order("awarded_at",{ascending:false}).limit(3),
 ]);
 const progress=progression as Progression|null;
 const gradeList=(ranks??[]) as Rank[];
 const current=gradeList.find(rank=>rank.code===(progress?.grade_code??"TRN"))??gradeList[0];
 const next=gradeList.find(rank=>rank.sort_order>(current?.sort_order??0));
 const proficiency=Number(progress?.proficiency??0);
 const hours=Number(progress?.accepted_minutes??0)/60;
 const sectorPercent=next?Math.min(100,((progress?.accepted_sectors??0)/next.minimum_sectors)*100):100;
 const hourPercent=next?Math.min(100,(hours/Number(next.minimum_hours))*100):100;
 const promotionPercent=Math.round(Math.min(sectorPercent,hourPercent,next?Math.min(100,(proficiency/Number(next.minimum_proficiency))*100):100));
 return <section className="progression-panel">
  <header><div><span className="kicker">CAREER PROGRESSION</span><h2>{current?.name??"Trainee"}</h2><p>{next?`${promotionPercent}% toward ${next.name}`:"Highest career grade achieved"}</p></div><div className="credit-balance"><Coins/><span>MERIT CREDITS</span><b>{progress?.credit_balance??0}</b></div></header>
  <div className="progression-meter"><span style={{width:`${promotionPercent}%`}}/></div>
  <div className="progression-stats">
   <article><Gauge/><span>PROFICIENCY</span><b>{proficiency.toFixed(1)}</b><small>rolling last 10 flights</small></article>
   <article><Award/><span>ACCEPTED SECTORS</span><b>{progress?.accepted_sectors??0}</b><small>{hours.toFixed(1)} hours · {progress?.distinct_routes??0} routes</small></article>
   <article className="promotion-requirements"><Target/><span>{next?`NEXT: ${next.name.toUpperCase()}`:"CAREER MILESTONE"}</span><b>{next?`${next.minimum_sectors} sectors · ${next.minimum_hours} hrs · ${next.minimum_proficiency} proficiency`:"Complete"}</b><small>All requirements must be met</small></article>
  </div>
  <div className="progression-lower"><div><h3>Weekly objectives</h3>{objectives?.length?<div className="objective-list">{(objectives as Objective[]).map(item=><article key={item.id}><div><strong>{item.title}</strong><small>+{item.credit_reward} credits</small></div><span>{Math.min(item.progress,item.target)} / {item.target}</span><div className="objective-meter"><i style={{width:`${Math.min(100,item.progress/item.target*100)}%`}}/></div></article>)}</div>:<p className="progression-empty">Objectives activate when your first accepted flight of the week is recorded.</p>}</div><div><h3>Recent achievements</h3>{achievements?.length?<div className="achievement-list">{(achievements as unknown as Achievement[]).map(item=><span key={item.achievement_code}><Award size={14}/>{item.definition?.name??item.achievement_code}</span>)}</div>:<p className="progression-empty">Your first accepted flight unlocks your first achievement.</p>}<Link href="/crew/logbook">View flight history →</Link></div></div>
 </section>
}
