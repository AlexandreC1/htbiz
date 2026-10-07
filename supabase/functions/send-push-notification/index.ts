import { createClient } from "https://esm.sh/@supabase/supabase-js@2";
import { serve } from "https://deno.land/std@0.177.0/http/server.ts";
import { encode as base64UrlEncode } from "https://deno.land/std@0.177.0/encoding/base64url.ts";

// This function is deployed with --no-verify-jwt so the database trigger can
// reach it, which means it is a PUBLIC endpoint. It therefore authenticates
// the caller itself with a shared secret. Without this, anyone who learned the
// URL could POST an arbitrary {record} and push a notification, with any text,
// to any user of the app.
const PUSH_SECRET = Deno.env.get("PUSH_WEBHOOK_SECRET");
const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
const SERVICE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

const json = (body: unknown, status = 200) =>
  new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });

/** Constant-time compare, so a timing side channel cannot leak the secret. */
function secretMatches(provided: string | null): boolean {
  if (!PUSH_SECRET || !provided) return false;
  const a = new TextEncoder().encode(PUSH_SECRET);
  const b = new TextEncoder().encode(provided);
  if (a.length !== b.length) return false;
  let diff = 0;
  for (let i = 0; i < a.length; i++) diff |= a[i] ^ b[i];
  return diff === 0;
}

// -----------------------------------------------------------------------------
// Google OAuth access token
// -----------------------------------------------------------------------------
// Tokens are valid for an hour. The previous version minted a fresh one on
// every single notification, adding an RSA sign plus a round trip to Google to
// the latency of every push.
let cachedToken: { value: string; expiresAt: number } | null = null;

async function getAccessToken(): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedToken && cachedToken.expiresAt > now + 60) return cachedToken.value;

  const raw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!raw) throw new Error("FIREBASE_SERVICE_ACCOUNT is not set");
  const serviceAccount = JSON.parse(raw);

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: serviceAccount.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };

  const encoder = new TextEncoder();
  const headerB64 = base64UrlEncode(encoder.encode(JSON.stringify(header)));
  const payloadB64 = base64UrlEncode(encoder.encode(JSON.stringify(payload)));
  const unsignedToken = `${headerB64}.${payloadB64}`;

  // A key pasted into an env var usually carries literal "\n" rather than real
  // newlines, which made the base64 body unparseable.
  const pemBody = String(serviceAccount.private_key)
    .replace(/\\n/g, "\n")
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s/g, "");
  const keyData = Uint8Array.from(atob(pemBody), (c: string) => c.charCodeAt(0));

  const key = await crypto.subtle.importKey(
    "pkcs8",
    keyData,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    encoder.encode(unsignedToken),
  );
  const jwt = `${unsignedToken}.${base64UrlEncode(new Uint8Array(signature))}`;

  const tokenResponse = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion: jwt,
    }),
  });

  if (!tokenResponse.ok) {
    throw new Error(
      `Google token exchange failed (${tokenResponse.status}): ${await tokenResponse.text()}`,
    );
  }

  const tokenData = await tokenResponse.json();
  if (!tokenData.access_token) throw new Error("No access_token in Google response");

  cachedToken = {
    value: tokenData.access_token,
    expiresAt: now + (tokenData.expires_in ?? 3600),
  };
  return cachedToken.value;
}

// FCM tells us a token is dead in the response body, not only via the status.
// Deleting on HTTP 404/410 alone left UNREGISTERED tokens in the table forever,
// so every push to a reinstalled app kept failing.
function isDeadToken(status: number, body: { error?: { status?: string; details?: unknown[] } }): boolean {
  if (status === 404 || status === 410) return true;
  const errorStatus = body?.error?.status;
  if (errorStatus === "NOT_FOUND" || errorStatus === "UNREGISTERED") return true;
  const details = body?.error?.details;
  if (Array.isArray(details)) {
    return details.some(
      (d) => (d as { errorCode?: string })?.errorCode === "UNREGISTERED",
    );
  }
  return false;
}

serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", {
      headers: {
        "Access-Control-Allow-Origin": "*",
        "Access-Control-Allow-Headers":
          "authorization, x-client-info, apikey, content-type, x-htbiz-push-secret",
      },
    });
  }

  if (req.method !== "POST") return json({ error: "Method not allowed" }, 405);

  if (!PUSH_SECRET) {
    console.error("PUSH_WEBHOOK_SECRET is not configured; refusing to send.");
    return json({ error: "Not configured" }, 500);
  }

  if (!secretMatches(req.headers.get("x-htbiz-push-secret"))) {
    return json({ error: "Unauthorized" }, 401);
  }

  try {
    const payload = await req.json().catch(() => null);
    const record = payload?.record;

    if (!record?.user_id || !record?.title) {
      return json({ error: "Missing notification record" }, 400);
    }

    const adminClient = createClient(SUPABASE_URL, SERVICE_KEY);

    const { data: tokens, error: tokenError } = await adminClient
      .from("fcm_tokens")
      .select("token")
      .eq("user_id", record.user_id);

    if (tokenError) {
      console.error("Token lookup failed", tokenError);
      return json({ error: "Token lookup failed" }, 500);
    }
    if (!tokens || tokens.length === 0) {
      return json({ message: "No FCM tokens for user", sent: 0 });
    }

    const accessToken = await getAccessToken();
    const serviceAccount = JSON.parse(Deno.env.get("FIREBASE_SERVICE_ACCOUNT")!);
    const fcmUrl =
      `https://fcm.googleapis.com/v1/projects/${serviceAccount.project_id}/messages:send`;

    const deadTokens: string[] = [];
    let delivered = 0;

    const results = await Promise.allSettled(
      tokens.map(async ({ token }: { token: string }) => {
        const response = await fetch(fcmUrl, {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            Authorization: `Bearer ${accessToken}`,
          },
          body: JSON.stringify({
            message: {
              token,
              notification: {
                title: String(record.title),
                // FCM rejects a null body; notifications always have one, but
                // a future notification type might not.
                body: String(record.body ?? ""),
              },
              // Every value in `data` must be a string or FCM returns 400.
              data: {
                type: String(record.type ?? ""),
                business_id: String(record.business_id ?? ""),
                review_id: String(record.review_id ?? ""),
                notification_id: String(record.id ?? ""),
              },
              android: { priority: "high" },
              apns: { payload: { aps: { sound: "default" } } },
            },
          }),
        });

        const body = await response.json().catch(() => ({}));

        if (response.ok) {
          delivered++;
          return "ok";
        }
        if (isDeadToken(response.status, body)) {
          deadTokens.push(token);
          return "dead";
        }
        throw new Error(`FCM ${response.status}: ${JSON.stringify(body)}`);
      }),
    );

    // Batch the cleanup: the old code issued one DELETE per dead token from
    // inside the map, so a user with many stale devices produced a burst of
    // writes on every notification.
    if (deadTokens.length > 0) {
      await adminClient.from("fcm_tokens").delete().in("token", deadTokens);
    }

    for (const result of results) {
      if (result.status === "rejected") console.error("Push failed:", result.reason);
    }

    return json({
      sent: delivered,
      pruned: deadTokens.length,
      failed: results.filter((r) => r.status === "rejected").length,
    });
  } catch (err) {
    console.error("send-push-notification error", err);
    // Never leak the internal message to a caller we cannot fully trust.
    return json({ error: "Internal error" }, 500);
  }
});
