import type { Env } from "./types";
import { route } from "./routes";
import { corsHeaders, error, withHeaders } from "./http";
import { dispatchScheduledNotifications } from "./notification-dispatcher";
import { dispatchScheduledBackups } from "./backup-service";
import { platformPackageMaintenance } from "./platform-package-service";
import { db } from "./db";
export default { async fetch(request:Request,env:Env):Promise<Response>{
  const requestId=request.headers.get("x-request-id")||crypto.randomUUID();
  if(request.method==="OPTIONS") return withHeaders(new Response(null,{status:204,headers:corsHeaders(request,env)}),request,env);
  const unsafe=!['GET','HEAD','OPTIONS'].includes(request.method.toUpperCase());
  const origin=request.headers.get('origin')||'';
  const pathname=new URL(request.url).pathname;
  const bootstrapCli=(pathname==='/api/bootstrap/initialize'||pathname==='/api/platform/bootstrap/initialize') && !origin && Boolean(request.headers.get('x-bootstrap-secret'));
  if(unsafe && !bootstrapCli && origin!==env.APP_ORIGIN) return withHeaders(error('origin_denied','Request origin is not allowed',403,requestId),request,env);
  try{return withHeaders(await route(request,env,requestId),request,env);}catch(e:any){
    const sqlState=String(e?.code||"");
    const sqlStatus:Record<string,number>={"22023":422,"22001":422,"23514":422,"23505":409,"23503":409,"40001":409,"42501":403,"55000":409,"P0001":422,"P0002":404};
    const status=Number(e?.status||sqlStatus[sqlState]||500);
    const mappedCode=sqlState==="42501"?"forbidden":(sqlState==="40001"||sqlState==="55000")?"conflict":sqlState==="P0002"?"not_found":"validation_error";
    const code=String(e?.status?e?.code:(sqlStatus[sqlState]?mappedCode:(status===500?"internal_error":"request_failed")));
    console.error(JSON.stringify({level:"error",requestId,code,status,sqlState:sqlState||undefined,message:String(e?.message||e)}));
    return withHeaders(error(code,status===500?"An internal error occurred":String(e?.message||"Request failed"),status,requestId),request,env);
  }
},
  async scheduled(controller:ScheduledController,env:Env,ctx:ExecutionContext):Promise<void>{
    ctx.waitUntil(dispatchScheduledNotifications(env));
    if(controller.cron==="0 2 * * *"){
      ctx.waitUntil(dispatchScheduledBackups(env));
      ctx.waitUntil(platformPackageMaintenance(env,db(env)));
    }
  }
};
