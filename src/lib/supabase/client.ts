import {createBrowserClient} from "@supabase/ssr";
export function createClient(){const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY??process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;if(!process.env.NEXT_PUBLIC_SUPABASE_URL||!key)throw new Error("Supabase public environment variables are missing");return createBrowserClient(process.env.NEXT_PUBLIC_SUPABASE_URL,key)}
