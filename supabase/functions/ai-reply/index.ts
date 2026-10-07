// Edge function: generate an AI reply for a conversation.
// POST { conversation_id } with the caller's Supabase auth JWT.
// Verifies ownership, reserves 1 bead (refunded if generation fails),
// loads the bot's sys_prompt plus the last ~20 messages, calls the Gemma
// endpoint (OpenAI-compatible), inserts the assistant message, writes a
// chat_spent ledger event, and bumps conversations.last_message_at.
// Returns 402 { error: "out_of_beads" } when the balance is zero.

const CORS_HEADERS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Headers":
    "authorization, x-client-info, apikey, content-type",
  "Access-Control-Allow-Methods": "POST, OPTIONS",
};

const GEMMA_ENDPOINT =
  "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions";
// Google AI Studio OpenAI-compatible endpoint — switching models is a
// one-string change (user-specified: gemma-4-31b-it).
const GEMMA_MODEL = "gemma-4-31b-it";

interface ChatMessage {
  role: "user" | "assistant";
  content: string;
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { ...CORS_HEADERS, "Content-Type": "application/json" },
  });
}

Deno.serve(async (req: Request) => {
  if (req.method === "OPTIONS") {
    return new Response("ok", { headers: CORS_HEADERS });
  }
  if (req.method !== "POST") {
    return json({ error: "Method not allowed" }, 405);
  }

  const GEMMA_API_KEY = Deno.env.get("GEMMA_API_KEY");
  if (!GEMMA_API_KEY) {
    return json({ error: "GEMMA_API_KEY is not configured" }, 500);
  }

  const SUPABASE_URL = Deno.env.get("SUPABASE_URL")!;
  const SERVICE_ROLE_KEY = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY")!;

  const authHeader = req.headers.get("Authorization") ?? "";
  const userToken = authHeader.replace(/^Bearer\s+/i, "");
  if (!userToken) {
    return json({ error: "Missing authorization" }, 401);
  }

  let conversationId: string;
  try {
    const body = await req.json();
    conversationId = String(body?.conversation_id ?? "");
  } catch {
    return json({ error: "Invalid JSON body" }, 400);
  }
  if (!conversationId) {
    return json({ error: "conversation_id is required" }, 400);
  }

  // Caller-scoped client: the anon key is the API key and the caller's JWT
  // rides in Authorization (the canonical pattern — modern Supabase auth
  // rejects a user JWT used as the apikey). RLS scopes data to the caller.
  const ANON_KEY = Deno.env.get("SUPABASE_ANON_KEY")!;
  const { createClient } = await import(
    "https://esm.sh/@supabase/supabase-js@2"
  );
  const userClient = createClient(SUPABASE_URL, ANON_KEY, {
    global: {
      headers: { Authorization: authHeader, apikey: ANON_KEY },
    },
  });

  const { data: authData, error: authError } = await userClient.auth.getUser();
  if (authError || !authData?.user) {
    console.error(
      "auth.getUser failed:",
      authError?.message,
      "| authHeader present:",
      authHeader.length > 7,
    );
    return json({ error: "Invalid token" }, 401);
  }

  const { data: conversation, error: convError } = await userClient
    .from("conversations")
    .select("id, user_id, bot_id")
    .eq("id", conversationId)
    .maybeSingle();
  if (convError || !conversation) {
    return json({ error: "Conversation not found" }, 404);
  }
  if (conversation.user_id !== authData.user.id) {
    return json({ error: "Forbidden" }, 403);
  }

  // Service-role client for beads, sys_prompt, and history.
  const admin = createClient(SUPABASE_URL, SERVICE_ROLE_KEY);

  // Reserve one bead atomically (spend_bead is service-role-only and only
  // decrements when the balance is positive). If the Gemma call below fails
  // the bead is refunded, so users are charged only for delivered replies.
  const { data: reserved, error: spendError } = await admin.rpc("spend_bead", {
    p_user: authData.user.id,
  });
  if (spendError) {
    console.error("spend_bead failed", spendError);
    return json({ error: "Could not check bead balance" }, 500);
  }
  if (typeof reserved !== "number" || reserved < 0) {
    return json({ error: "out_of_beads" }, 402);
  }
  const refund = () => admin.rpc("refund_bead", { p_user: authData.user.id });

  const { data: bot, error: botError } = await admin
    .from("bots")
    .select("sys_prompt, name")
    .eq("id", conversation.bot_id)
    .maybeSingle();
  if (botError || !bot) {
    return json({ error: "Bot not found" }, 404);
  }

  const { data: history, error: msgError } = await admin
    .from("messages")
    .select("role, content, created_at")
    .eq("conversation_id", conversationId)
    .order("created_at", { ascending: false })
    .limit(20);
  if (msgError) {
    return json({ error: "Failed to load messages" }, 500);
  }

  const chatMessages: ChatMessage[] = (history ?? [])
    .slice()
    .reverse()
    .map((m: { role: string; content: string }) => ({
      role: m.role === "assistant" ? "assistant" : "user",
      content: m.content,
    }));
  // The model needs the conversation to END on a user turn: Gemma 4 emits
  // zero tokens when the last message is its own (which is exactly the
  // app's retry path). Trim trailing assistant turns so we regenerate
  // against the latest user message, and never send a system-only request
  // (the compat layer maps that to zero contents).
  while (
    chatMessages.length > 0 &&
    chatMessages[chatMessages.length - 1].role === "assistant"
  ) {
    chatMessages.pop();
  }
  if (chatMessages.length === 0) {
    chatMessages.push({ role: "user", content: "Hi!" });
  }

  let content: string;
  try {
    const gemmaBody = JSON.stringify({
      model: GEMMA_MODEL,
      messages: [
        {
          role: "system",
          content:
            bot.sys_prompt ||
            `You are ${bot.name}, an AI character in a messaging app. Stay in character, keep replies conversational and concise.`,
        },
        ...chatMessages,
      ],
      max_tokens: 2048,
    });
    // Google's free tier flakes with 429/500/503 ("high demand"); retry
    // with backoff and fall back to a second model before giving up.
    const GEMMA_FALLBACK_MODEL = "gemma-3-27b-it";
    const attempt = async (model: string) =>
      fetch(GEMMA_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          Authorization: `Bearer ${GEMMA_API_KEY}`,
        },
        body: JSON.stringify({ ...JSON.parse(gemmaBody), model }),
        signal: AbortSignal.timeout(30_000),
      });
    let gemmaRes = await attempt(GEMMA_MODEL);
    for (const delay of [900, 2500]) {
      if (![429, 500, 503].includes(gemmaRes.status)) break;
      await new Promise((r) => setTimeout(r, delay));
      gemmaRes = await attempt(GEMMA_MODEL);
    }
    if (![200].includes(gemmaRes.status) && [429, 500, 503].includes(gemmaRes.status)) {
      console.error("Falling back to", GEMMA_FALLBACK_MODEL);
      gemmaRes = await attempt(GEMMA_FALLBACK_MODEL);
    }
    if (!gemmaRes.ok) {
      const detail = await gemmaRes.text();
      console.error("Gemma error", gemmaRes.status, detail);
      await refund();
      return json({ error: "AI provider error" }, 502);
    }
    const payload = await gemmaRes.json();
    // Gemma 4 is a thinking model: strip the raw reasoning block so only
    // the actual reply reaches the chat.
    content =
      (payload?.choices?.[0]?.message?.content as string | undefined)
        ?.replace(/<(thought|think)>[\s\S]*?<\/\1>/gi, "")
        .trim() || "";
    if (!content) {
      await refund();
      return json({ error: "Empty AI response" }, 502);
    }
  } catch (err) {
    console.error("Gemma request failed", err);
    await refund();
    return json({ error: "AI provider unreachable" }, 502);
  }

  const { data: inserted, error: insertError } = await admin
    .from("messages")
    .insert({
      conversation_id: conversationId,
      role: "assistant",
      content,
    })
    .select("id")
    .single();
  if (insertError) {
    console.error("Insert assistant message failed", insertError);
    await refund();
    return json({ error: "Failed to save reply" }, 500);
  }

  // Ledger: the caller paid 1 bead for this reply.
  await admin.from("credit_events").insert({
    user_id: authData.user.id,
    delta: -1,
    reason: "chat_spent",
    ref_conversation: conversationId,
    ref_message: inserted?.id ?? null,
  });

  await admin
    .from("conversations")
    .update({ last_message_at: new Date().toISOString() })
    .eq("id", conversationId);

  return json({ content, beads: reserved });
});
