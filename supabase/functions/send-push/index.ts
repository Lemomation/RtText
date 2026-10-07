// Supabase Edge Function: send-push
// Dispatches Firebase Cloud Messaging (FCM) v1 push notifications to the
// recipient of a 1:1 human DM message.
//
// POST { conversation_id, content }
// Requires Bearer JWT in Authorization header.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

interface ServiceAccount {
  project_id: string;
  client_email: string;
  private_key: string;
}

let cachedAccessToken: { token: string; expiresAt: number } | null = null;

async function getGoogleAccessToken(sa: ServiceAccount): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  if (cachedAccessToken && cachedAccessToken.expiresAt > now + 60) {
    return cachedAccessToken.token;
  }

  const pem = sa.private_key;
  const pemContents = pem
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");

  const binaryDerString = atob(pemContents);
  const binaryDer = new Uint8Array(binaryDerString.length);
  for (let i = 0; i < binaryDerString.length; i++) {
    binaryDer[i] = binaryDerString.charCodeAt(i);
  }

  const cryptoKey = await crypto.subtle.importKey(
    "pkcs8",
    binaryDer.buffer,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );

  const header = { alg: "RS256", typ: "JWT" };
  const payload = {
    iss: sa.client_email,
    sub: sa.client_email,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
  };

  const encodeBase64Url = (obj: unknown) =>
    btoa(JSON.stringify(obj))
      .replace(/\+/g, "-")
      .replace(/\//g, "_")
      .replace(/=+$/, "");

  const encodedHeader = encodeBase64Url(header);
  const encodedPayload = encodeBase64Url(payload);
  const dataToSign = new TextEncoder().encode(`${encodedHeader}.${encodedPayload}`);

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    cryptoKey,
    dataToSign,
  );

  const encodedSignature = btoa(
    String.fromCharCode(...new Uint8Array(signature)),
  )
    .replace(/\+/g, "-")
    .replace(/\//g, "_")
    .replace(/=+$/, "");

  const jwt = `${encodedHeader}.${encodedPayload}.${encodedSignature}`;

  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body: `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });

  if (!res.ok) {
    const errText = await res.text();
    throw new Error(`Google OAuth error (${res.status}): ${errText}`);
  }

  const data = await res.json();
  cachedAccessToken = {
    token: data.access_token as string,
    expiresAt: now + (data.expires_in as number || 3600),
  };
  return cachedAccessToken.token;
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  // 1. Authenticate the caller
  const authHeader = req.headers.get("Authorization") ?? "";
  const userToken = authHeader.replace(/^Bearer\s+/i, "");
  if (!userToken) {
    return json({ error: "Missing authorization" }, 401);
  }

  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: { headers: { Authorization: `Bearer ${userToken}`, apikey: ANON_KEY } },
  });
  const { data: userData, error: userError } = await userClient.auth.getUser();
  if (userError || !userData?.user) {
    return json({ error: "Unauthorized" }, 401);
  }
  const callerUid = userData.user.id;

  let conversationId: string;
  let content: string;
  try {
    const body = await req.json();
    conversationId = body.conversation_id;
    content = (body.content || "").trim();
    if (!conversationId || !content) {
      return json({ error: "conversation_id and content required" }, 400);
    }
  } catch (_) {
    return json({ error: "Invalid JSON body" }, 400);
  }

  const adminClient = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // 2. Fetch conversation to verify participant and resolve recipient
  const { data: conv, error: convError } = await adminClient
    .from("conversations")
    .select("user_id, dm_user_id")
    .eq("id", conversationId)
    .maybeSingle();

  if (convError || !conv) {
    return json({ error: "Conversation not found" }, 404);
  }

  if (conv.user_id !== callerUid && conv.dm_user_id !== callerUid) {
    return json({ error: "Forbidden" }, 403);
  }

  // Only DM conversations have recipients (bots do not get push notifications)
  if (!conv.dm_user_id) {
    return json({ ok: true, sent: 0, reason: "bot_chat" });
  }

  const recipientId = callerUid === conv.user_id ? conv.dm_user_id : conv.user_id;

  // 3. Fetch sender's username
  const { data: senderProfile } = await adminClient
    .from("profiles")
    .select("username")
    .eq("id", callerUid)
    .maybeSingle();
  const senderName = senderProfile?.username || "Someone";

  // 4. Fetch recipient's registered device tokens
  const { data: tokens, error: tokensError } = await adminClient
    .from("user_push_tokens")
    .select("token")
    .eq("user_id", recipientId);

  if (tokensError || !tokens || tokens.length === 0) {
    return json({ ok: true, sent: 0, reason: "no_device_tokens" });
  }

  // 5. Parse Firebase Service Account
  const saRaw = Deno.env.get("FIREBASE_SERVICE_ACCOUNT");
  if (!saRaw) {
    console.warn("FIREBASE_SERVICE_ACCOUNT env secret is not configured");
    return json({ ok: false, error: "FIREBASE_SERVICE_ACCOUNT not configured" }, 500);
  }

  let sa: ServiceAccount;
  try {
    sa = JSON.parse(saRaw);
  } catch (e) {
    console.error("Invalid FIREBASE_SERVICE_ACCOUNT JSON:", e);
    return json({ ok: false, error: "Invalid service account JSON" }, 500);
  }

  // 6. Request Google OAuth2 access token and dispatch FCM messages
  let googleToken: string;
  try {
    googleToken = await getGoogleAccessToken(sa);
  } catch (e) {
    console.error("Failed to acquire Google access token:", e);
    return json({ ok: false, error: "Google auth failure" }, 500);
  }

  const fcmEndpoint = `https://fcm.googleapis.com/v1/projects/${sa.project_id}/messages:send`;
  let sentCount = 0;
  const staleTokens: string[] = [];

  for (const row of tokens) {
    const fcmToken = row.token;
    try {
      const resp = await fetch(fcmEndpoint, {
        method: "POST",
        headers: {
          Authorization: `Bearer ${googleToken}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message: {
            token: fcmToken,
            notification: {
              title: senderName,
              body: content,
            },
            data: {
              conversation_id: conversationId,
            },
            android: {
              priority: "high",
              notification: {
                channel_id: "rttext_messages",
                sound: "default",
                default_sound: true,
                default_vibrate_timings: true,
                notification_priority: "PRIORITY_HIGH",
                click_action: "FLUTTER_NOTIFICATION_CLICK",
              },
            },
          },
        }),
      });

      if (resp.ok) {
        sentCount++;
      } else {
        const errJson = await resp.json().catch(() => ({}));
        const status = resp.status;
        console.warn(`FCM send failed for token (${status}):`, errJson);

        // If token is invalid or unregistered, schedule deletion
        if (
          status === 404 ||
          errJson?.error?.details?.some((d: { errorCode?: string }) =>
            d.errorCode === "UNREGISTERED"
          )
        ) {
          staleTokens.push(fcmToken);
        }
      }
    } catch (err) {
      console.error("Error sending FCM message:", err);
    }
  }

  // Prune any stale tokens asynchronously
  if (staleTokens.length > 0) {
    adminClient
      .from("user_push_tokens")
      .delete()
      .in("token", staleTokens)
      .then();
  }

  return json({ ok: true, sent: sentCount });
});
