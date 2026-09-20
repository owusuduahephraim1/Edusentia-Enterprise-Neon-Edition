export interface Env {
  DATABASE_URL: string;
  APP_ORIGIN: string;
  SESSION_PEPPER: string;
  BOOTSTRAP_ADMIN_SECRET: string;
  PLATFORM_BOOTSTRAP_SECRET?: string;
  TURNSTILE_SECRET?: string;
  SESSION_COOKIE_NAME?: string;
  PLATFORM_SESSION_COOKIE_NAME?: string;
  SESSION_TTL_SECONDS?: string;
  PRODUCT_VERSION?: string;
  OBJECTS: R2Bucket;
}
export type SessionContext = {sessionId:string; userId:string; tenantId:string; role:string; assuranceLevel:number; email:string; displayName:string};
export type PlatformSessionContext = {sessionId:string; userId:string; role:"platform_super_admin"; assuranceLevel:number; email:string; displayName:string};
