export interface Env {
  DATABASE_URL: string;
  PROVISIONER_DATABASE_URL?: string;
  TENANT_TEMPLATE_DATABASE?: string;
  APP_ORIGIN: string;
  APP_BASE_PATH?: string;
  SESSION_PEPPER: string;
  BOOTSTRAP_ADMIN_SECRET: string;
  PLATFORM_BOOTSTRAP_SECRET?: string;
  TURNSTILE_SECRET?: string;
  TURNSTILE_TEST_MODE?: string;
  SESSION_COOKIE_NAME?: string;
  PLATFORM_SESSION_COOKIE_NAME?: string;
  SESSION_TTL_SECONDS?: string;
  PRODUCT_VERSION?: string;
  RESEND_API_KEY?: string;
  EMAIL_FROM?: string;
  BACKUP_ENCRYPTION_KEY?: string;
  BACKUP_SIGNING_SECRET?: string;
  BACKUP_MAX_OBJECTS?: string;
  BACKUP_MAX_BYTES?: string;
  OBJECTS: R2Bucket;
}
export type SessionContext = {sessionId:string; userId:string; tenantId:string; tenantCode:string; tenantName:string; databaseName:string; role:string; assuranceLevel:number; email:string; displayName:string};
export type PlatformSessionContext = {sessionId:string; userId:string; role:"platform_super_admin"; assuranceLevel:number; email:string; displayName:string};
