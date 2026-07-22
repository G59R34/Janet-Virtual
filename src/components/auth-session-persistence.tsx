"use client";
import {useEffect} from "react";
import {usePathname,useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
import {clearAuthSession,readAuthSession,storeAuthSession} from "@/lib/auth-session-storage";

export function AuthSessionPersistence(){
 const pathname=usePathname();const router=useRouter();
 useEffect(()=>{const db=createClient();let mounted=true;
  const restore=async()=>{const {data:{session}}=await db.auth.getSession();if(session){storeAuthSession(session);return}const stored=readAuthSession();if(!stored)return;const {data,error}=await db.auth.setSession({access_token:stored.accessToken,refresh_token:stored.refreshToken});if(!mounted)return;if(error||!data.session){clearAuthSession();return}storeAuthSession(data.session);if(pathname==="/login"){router.replace("/crew");router.refresh()}};
  void restore();
  const {data:{subscription}}=db.auth.onAuthStateChange((event,session)=>{if(session)storeAuthSession(session);else if(event==="SIGNED_OUT")clearAuthSession()});
  return()=>{mounted=false;subscription.unsubscribe()};
 },[pathname,router]);
 return null;
}
