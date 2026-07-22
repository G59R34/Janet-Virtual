import type {Session} from "@supabase/supabase-js";

const SESSION_STORAGE_KEY="janet-virtual-auth-session";

type StoredSession={accessToken:string;refreshToken:string;expiresAt:number|null};

export function storeAuthSession(session:Session){
 if(typeof window==="undefined")return;
 const stored:StoredSession={accessToken:session.access_token,refreshToken:session.refresh_token,expiresAt:session.expires_at??null};
 window.localStorage.setItem(SESSION_STORAGE_KEY,JSON.stringify(stored));
}

export function readAuthSession():StoredSession|null{
 if(typeof window==="undefined")return null;
 const value=window.localStorage.getItem(SESSION_STORAGE_KEY);if(!value)return null;
 try{const parsed=JSON.parse(value) as Partial<StoredSession>;if(typeof parsed.accessToken!=="string"||typeof parsed.refreshToken!=="string")throw new Error("Invalid stored session");return {accessToken:parsed.accessToken,refreshToken:parsed.refreshToken,expiresAt:typeof parsed.expiresAt==="number"?parsed.expiresAt:null}}catch{clearAuthSession();return null}
}

export function clearAuthSession(){if(typeof window!=="undefined")window.localStorage.removeItem(SESSION_STORAGE_KEY)}
