import type { Env } from "./types";
import { route } from "./routes";
import { corsHeaders, error, withHeaders } from "./http";
import { dispatchScheduledNotifications } from "./notification-dispatcher";
export default { async fetch(request:Request,env:Env):Promise<Response>{
  const requestId=request.headers.get("x-request-id")||crypto.randomUUID();
  if(request.method==="OPTIONS") return withHeaders(new Response(null,{status:204,headers:corsHeaders(request,env)}),request,env);
  const unsafe=!['GET','HEAD','OPTIONS'].includes(request.method.toUpperCase());
  const origin=request.headers.get('origin')||'';
  const pathname=new URL(request.url).pathname;
  const bootstrapCli=(pathname==='/api/bootstrap/initialize'||pathname==='/api/platform/bootstrap/initialize') && !origin && Boolean(request.headers.get('x-bootstrap-secret'));
  if(unsafe && !bootstrapCli && origin!==env.APP_ORIGIN) return withHeaders(error('origin_denied','Request origin is not allowed',403,requestId),request,env);
  try{return withHeaders(await route(request,env,requestId),request,env);}catch(e:any){
    const status=Number(e?.status||500),code=String(e?.code||(status===500?"internal_error":"request_failed"));
    console.error(JSON.stringify({level:"error",requestId,code,status,message:String(e?.message||e)}));
    return withHeaders(error(code,status===500?"An internal error occurred":String(e?.message||"Request failed"),status,requestId),request,env);
  }
},
  async scheduled(_controller:ScheduledController,env:Env,ctx:ExecutionContext):Promise<void>{
    ctx.waitUntil(dispatchScheduledNotifications(env));
  }
};
