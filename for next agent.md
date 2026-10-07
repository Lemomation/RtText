# For the next agent — RtText handoff (2026-10-07)

Everything you need to continue this project. Read this before touching anything.

## What this is

RtText (`C:\Users\gulza\Desktop\Rttext`, repo `github.com/Lemomation/RtText`, branch `main`):
a Flutter Android messaging app where users chat with **AI characters (bots)** they create,
and **1:1 with other humans (DMs)**. Currency is **beads** (1 bead = 1 AI reply; DMs are free).
Latest shipped version: **v0.3.4** (signed, released via GitHub Releases). All CI green on main.

## Stack & environment

- Flutter 3.47.x, Material 3 dark-only. AppId `com.lemomation.rttext`. go_router, supabase_flutter ^2.8, flutter_animate, provider.
- **NO Flutter/Dart SDK on this machine. You cannot run `flutter` locally.** CI (GitHub Actions) is the only analyzer/test/build gate: `.github/workflows/build.yml` runs `flutter analyze && flutter test` + APK build on every push to main, and **fails on ANY analyzer finding** (incl. infos: prefer_const_constructors, prefer_final_locals, use_build_context_synchronously, unnecessary_cast…). Push in batches, not per-fix (user pays for CI minutes).
- Tooling that IS available locally: Python 3.11 (with `cryptography`, `PIL`), `gh` CLI at `/c/Program Files/GitHub CLI/gh.exe` (authenticated as Lemomation), GitHub REST via `printf "protocol=https\nhost=github.com\n" | git credential fill` for the token. Git push works with stored credentials.
- Supabase project ref `jskzgedrciwklcmmpwcx`. Supabase MCP tools available in-session (apply_migration, execute_sql, deploy_edge_function, query_logs). Email confirmation is ON in auth settings (SQL can flip `auth.users.email_confirmed_at` for test users).

## Supabase schema (migrations in `supabase/migrations/`, ALL applied live)

- `0001_init`: profiles (RLS select/update/insert own), bots (+ public_bots view hiding sys_prompt), conversations, messages, pfp bucket + storage policies, realtime publication.
- `0002`: bots.owner DEFAULT auth.uid(); bots.bubble_color text; public_bots view recreated with bubble_color.
- `0003` beads economy: profiles.credits→**beads**; +100 signup (handle_new_user + ledger event); `last_daily_claim` date; `credit_events` ledger (reason enum signup/daily/chat_spent/chat_earned; RLS select-own); chat-earn trigger `on_message_chat_earned` (+1 to bot owner per user message, ignores DMs via null bot_id); bot-minting trigger dropped; `claim_daily_beads()` RPC (returns new balance or -1); `spend_bead(p_user)`/`refund_bead(p_user)` RPCs (atomic, **service_role-only grant**); profiles UPDATE column-granted to (username, avatar_url) only — clients can't write their own balance.
- `0004`: dropped stale `on_conversation_created` trigger (referenced renamed column — broke conversation inserts).
- `0005`: pfp storage policy accepts both `user/<uid>/<file>` AND `user/<uid>.<ext>` — because `storage.foldername()` strips the FILENAME (a file directly under `user/` parses to `['user']`).
- `0006` human DMs: conversations.dm_user_id (check: exactly one of bot_id/dm_user_id); unique index `least/greatest(user_id, dm_user_id)` (one row per pair); RLS = EITHER participant on conversations AND messages; messages.sender_id; `public.people` view (id, username, avatar_url — never beads) for username search.

Key RPCs: `claim_daily_beads()`, `spend_bead(p_user uuid)` (returns new balance or -1), `refund_bead(p_user uuid)`.
Views: `public_bots` (bot fields, no sys_prompt), `people` (profiles sans beads).
Realtime: conversations + messages in `supabase_realtime` publication; RLS applies to realtime delivery.

## Edge function `supabase/functions/ai-reply` (currently version 12, verify_jwt = **false**)

- POST `{conversation_id}` with user JWT in Authorization. auth via `createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {global:{headers:{Authorization, apikey: ANON_KEY}}}).auth.getUser()` — **do NOT pass the user JWT as the client key**; modern Supabase auth rejects that (this exact bug caused days of 401s).
- Provider chain (env keys only — **never hardcode keys, repo is PUBLIC**): `DEEPSEEK_API_KEY` → deepseek-chat @ `https://api.deepseek.com/chat/completions` with `thinking: {"type":"disabled"}`; then GEMMA_API_KEY → gemma-4-31b-it, then gemma-3-27b-it @ `https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`. 2 attempts each, 900ms apart, 30s `AbortSignal.timeout`, retry on 429/500/502/503 (Google free tier 500/503s "high demand" constantly).
- Model must end on a **user turn**: trim trailing assistant messages (thinking models emit zero tokens otherwise — this is the app's Retry path) and never send system-only (compat layer 400s "contents is not specified").
- Strip thinking output: `.replace(/<(thought|think)>[\s\S]*<\/\1>/gi)`.
- Beads: `spend_bead` reserves BEFORE generation, `refund` on any failure, `chat_spent` ledger event after insert. Returns `{content, beads}`; 402 `{error:"out_of_beads"}` at zero.
- Secrets live in Supabase (Edge Functions → Secrets): GEMMA_API_KEY, DEEPSEEK_API_KEY (user-provided), SUPABASE_URL/SERVICE_ROLE/ANON auto-injected. There is NO secrets tool via MCP — user adds them in the dashboard.

## App structure

- `lib/core/`: app_router.dart (routes: /login, shell /chats+/discover, /chat/:id, /bot/:id, /create-bot?id=, /profile), app_theme.dart (`AppTheme.dark({Color seed})`), accents.dart (6 accent presets), animations.dart (Motion — shared durations/curves/page transition), supabase_config.dart (dart-define SUPABASE_URL/SUPABASE_ANON_KEY).
- `lib/providers/theme_provider.dart`: accent persisted via shared_preferences key `accent_id`.
- `lib/services/`: bots_service (writes to `bots` with owner, reads via `public_bots`), conversations_service (realtime streams; **watchMessages dedupes rows by id** — realtime is at-least-once; **conversation stream is unfiltered + client-side participant filter** because SupabaseStreamFilterBuilder has NO `.or()`), beads_service, updater_service, ai request sends the session token EXPLICITLY in invoke headers (FunctionsClient snapshots headers at construction).
- `lib/widgets/`: bead_icon.dart (CustomPainter bead — brand icon), rt_icons.dart (custom icon set: chatBubble/explore/person/plus/send/sparkle), rt_markdown.dart (inline bold/italic/code + bullet normalization for bubbles), app_toast.dart (`showAppToast` — custom drop-down toast, replaces SnackBars), pressable_scale.dart, bot_avatar.dart.
- Screens: chats_shell (bottom nav + daily bead claim popup), chats, discover (Characters/People segmented tabs; People = username prefix search → DM), chat (bot mode w/ beads + ai-reply, DM mode free w/ sender attribution; out-of-beads banner; keyboard-aware re-scroll), create_bot (bubble color picker), bot_profile, profile (beads chip, appearance, my bots, app updates card).

## CI/CD & release

- Secrets on GitHub repo: SUPABASE_URL, SUPABASE_ANON_KEY (legacy JWT), KEYSTORE_BASE64, KEYSTORE_PASSWORD, KEY_ALIAS=rttext. Keystore backup on user's machine: `C:\Users\gulza\rttext-release-keystore\` (PKCS12, valid to 2051; SHA-1 `CB:DB:7F:73:C6:C6:1C:8C:E0:C0:00:18:9B:94:33:AC:7F:21:0F:E7` — put this in the Google Cloud Android OAuth client).
- Build: `flutter build apk --release --split-per-abi`; arm64 copied to `app-release.apk` (asset name kept stable so old updaters work) + armeabi-v7a; release step: if tag `v<pubspec version>` exists → `gh release upload --clobber`, else create + `--latest`. **Bump `pubspec.yaml version` for the in-app updater to prompt** (it compares pubspec version vs release tag).
- In-app updater: UpdaterService checks `api.github.com/repos/Lemomation/RtText/releases/latest` anonymously, semver-compares, downloads, installs via open_filex (REQUEST_INSTALL_PACKAGES in manifest).
- Signing falls back to debug keystore if secrets absent (local builds). Signature is STABLE now — updates install over each other; only pre-v0.3.0 installs need one uninstall.

## Gotchas that actually bit (don't rediscover these)

- Analyzer lint failures: const-hygiene in animated widgets, unnecessary casts on supabase rows, `TextDirection` in intl collides with dart:ui (alias `import 'dart:ui' as ui show TextDirection;`), ShapeBorder needs getInnerPath + exact ui.TextDirection signatures, mounted guards before context use after awaits, AnimatedSwitcher has NO `alignment` param.
- Lazy ListView in tests: `ensureVisible` can't see unbuilt children ("No element"); `scrollUntilVisible` breaks on TextField-embedded Scrollables → hand-rolled drag loop until finder materializes (see test/discover_create_bot_test.dart).
- Realtime: at-least-once delivery → dedupe rows by id; stream filter builder lacks `.or()`.
- `storage.foldername()` strips filenames.
- deepseek-chat: `thinking:{type:"disabled"}` param works; `reasoning_effort` misbehaves (fills reasoning_content, empties content).
- Supabase auth: user JWT as apikey = 401 (use anon key as apikey + JWT as Bearer).
- Old `handle_new_user`-era triggers referencing renamed columns will 42703 — when renaming columns, grep triggers/functions/views for the old name.

## Users, testing, diagnostics

- Function logs: Supabase MCP `query_logs` (sources `function_logs` = stdout, `function_edge_logs` = gateway statuses). Postgres errors seen in app snackbars give PostgrestException codes (42501 RLS, 42703 column, 23505 unique).
- Throwaway test account you can sign into: `diag-rttext-176@proton.me` / `Diag-Test-176!` (has a Gojo conversation, id f46867e5-6b80-40a5-99db-af8dddced341). Real users: Lemomation + friends (2-3 devices, testing daily).
- User preference: minimal design but NOT bland — custom icons, motion, color; "don't overdo it". Batch git pushes (CI minutes). User tests on real devices and reports with screenshots; debug via DB queries + function logs before asking them anything.

## Open items / next ideas

- Google OAuth Android client: needs the SHA-1 above (was blocked on unstable debug signing; now stable). Google provider is enabled with web client credentials.
- Key rotation: user pasted the DeepSeek key into chat once — suggest rotating it eventually.
- `diag-rttext-176` test user can be deleted after use (or kept for testing).
- Possible next: typing persistence, message editing/deletion, group chats, bot discovery ranking, DeepSeek reasoner as premium option, real error-code mapping in toasts.
