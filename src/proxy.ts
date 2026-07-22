import {createServerClient} from "@supabase/ssr";
import {NextResponse,type NextRequest} from "next/server";

const jcarsOrigins=new Set(["http://tauri.localhost","https://tauri.localhost","tauri://localhost","http://localhost:1420","http://localhost:1430"]);
function applyJcarsCors(request:NextRequest,response:NextResponse){
 const origin=request.headers.get("origin");
 if((request.nextUrl.pathname.startsWith("/api/acars/")||request.nextUrl.pathname.startsWith("/api/jscope/"))&&origin&&jcarsOrigins.has(origin)){
  response.headers.set("Access-Control-Allow-Origin",origin);
  response.headers.set("Access-Control-Allow-Methods","GET, POST, OPTIONS");
  response.headers.set("Access-Control-Allow-Headers","Authorization, Content-Type, X-JScope-Session");
  response.headers.set("Access-Control-Max-Age","86400");
  response.headers.set("Vary","Origin");
 }
 return response;
}

export async function proxy(request:NextRequest){
 if(request.method==="OPTIONS"&&(request.nextUrl.pathname.startsWith("/api/acars/")||request.nextUrl.pathname.startsWith("/api/jscope/")))return applyJcarsCors(request,new NextResponse(null,{status:204}));
 let response=NextResponse.next({request});
 const key=process.env.NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY??process.env.NEXT_PUBLIC_SUPABASE_ANON_KEY;
 if(process.env.NEXT_PUBLIC_SUPABASE_URL&&key){
  const supabase=createServerClient(process.env.NEXT_PUBLIC_SUPABASE_URL,key,{cookies:{getAll:()=>request.cookies.getAll(),setAll(items){items.forEach(({name,value})=>request.cookies.set(name,value));response=NextResponse.next({request});items.forEach(({name,value,options})=>response.cookies.set(name,value,options))}}});
  await supabase.auth.getUser();
 }
 return applyJcarsCors(request,response);
}
export const config={matcher:["/((?!_next/static|_next/image|favicon.ico|.*\\.(?:svg|png|jpg|jpeg|gif|webp)$).*)"]};
