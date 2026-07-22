"use client";
import {LogOut} from "lucide-react";
import {useRouter} from "next/navigation";
import {createClient} from "@/lib/supabase/client";
import {clearAuthSession} from "@/lib/auth-session-storage";

export function SignOutButton(){const router=useRouter();async function signOut(){clearAuthSession();await createClient().auth.signOut();router.replace("/login");router.refresh()}return <button className="button" type="button" onClick={signOut}><LogOut size={15}/> Sign out</button>}
