import type { Env } from "./types";

type SiteverifyResult = {
  success?: boolean;
  hostname?: string;
  action?: string;
  "error-codes"?: string[];
};

export async function verifyTurnstile(env: Env, token: string, request: Request, expectedAction = "login"): Promise<void> {
  const testMode=env.TURNSTILE_TEST_MODE==="true";
  const secret=testMode?"1x0000000000000000000000000000000AA":env.TURNSTILE_SECRET;
  if (!secret) {
    throw Object.assign(new Error("Human verification is not configured"), { code: "turnstile_not_configured", status: 503 });
  }
  if (!token || token.length > 2048) {
    throw Object.assign(new Error("Complete the human verification before signing in"), { code: "turnstile_required", status: 403 });
  }

  const form = new FormData();
  form.set("secret", secret);
  form.set("response", token);
  const remoteIp = request.headers.get("cf-connecting-ip");
  if (remoteIp) form.set("remoteip", remoteIp);

  let response: Response;
  try {
    response = await fetch("https://challenges.cloudflare.com/turnstile/v0/siteverify", {
      method: "POST",
      body: form,
      signal: AbortSignal.timeout(10000)
    });
  } catch {
    throw Object.assign(new Error("Human verification service is temporarily unavailable"), { code: "turnstile_unavailable", status: 503 });
  }

  if (!response.ok) {
    throw Object.assign(new Error("Human verification service is temporarily unavailable"), { code: "turnstile_unavailable", status: 503 });
  }

  const result = await response.json<SiteverifyResult>();
  const expectedHostname = new URL(env.APP_ORIGIN).hostname;
  const hostnameMismatch=result.hostname !== expectedHostname;
  const actionMismatch=result.action !== expectedAction;
  const metadataInvalid=!testMode && (hostnameMismatch || actionMismatch);
  if (!result.success || metadataInvalid) {
    console.warn(JSON.stringify({
      level: "warn",
      event: "turnstile.rejected",
      hostname: result.hostname || null,
      action: result.action || null,
      errors: result["error-codes"] || []
    }));
    throw Object.assign(new Error("Human verification failed. Please try again."), { code: "turnstile_failed", status: 403 });
  }
}
