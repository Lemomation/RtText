# For the next agent — RtText handoff (2026-10-08)

Everything you need to continue this project. Read this before touching anything.

## What this is

RtText (`C:\Users\gulza\Desktop\Rttext`, repo `github.com/Lemomation/RtText`, branch `main`):
A Flutter Android messaging app where users chat with:
1. **AI characters (bots)** they create or discover.
2. **1:1 Direct Messages with other humans (DMs)** (free, with read receipts, typing indicator, live online/last-active presence).
3. **Group chats** (multiple humans + multiple bots; bots only engage when @mentioned).

Currency is **beads**:
- 1 bead = 1 AI reply.
- DMs are 100% free (never touch beads or invoke AI).
- Group chats: when a user @mentions a bot (`@BotName`), 1 bead is taken from the sender who triggered the bot and credited to the creator of the bot. If the sender is out of beads, nothing is sent to the AI and a banner/chip warns "out of beads".
- Daily bead giveaway is currently suspended to simulate the economy and prevent hoarding.

**Latest shipped version**: **v0.5.1** (signed, released via GitHub Releases). All CI green on `main`.

---

## Stack & environment

- **Flutter 3.47.x**, Material 3 dark-only. AppId `com.lemomation.rttext`. `go_router`, `supabase_flutter ^2.8`, `flutter_animate`, `provider`, `intl`, `firebase_core`, `firebase_messaging`.
- **NO Flutter/Dart SDK on this machine. You cannot run `flutter` locally.**
  CI (GitHub Actions) is the only analyzer/test/build gate: `.github/workflows/build.yml` runs `flutter analyze && flutter test` + APK build on every push to `main`, and **fails on ANY analyzer finding** (including infos: `prefer_const_constructors`, `prefer_final_locals`, `use_build_context_synchronously`, `body_might_complete_normally_catch_error`, unnecessary casts).
  - Test syntax and types carefully before pushing.
  - Push in batches, not per-file (user pays for CI minutes).
- **Tooling available locally**:
  - Python 3.11 (with `cryptography`, `PIL`).
  - `gh` CLI at `/c/Program Files/GitHub CLI/gh.exe` (authenticated as `Lemomation`).
  - Git push works with stored credentials.
- **Supabase project ref**: `jskzgedrciwklcmmpwcx`.
  - Supabase MCP tools available in-session (`apply_migration`, `execute_sql`, `deploy_edge_function`, `query_logs`).
  - Email confirmation is ON in auth settings (`auth.users.email_confirmed_at` can be flipped for test users via SQL).

---

## Supabase schema & migrations (in `supabase/migrations/`, ALL applied live)

- `0001_init`: profiles (RLS select/update/insert own), bots (+ `public_bots` view hiding sys_prompt), conversations, messages, `pfp` bucket + storage policies, realtime publication.
- `0002`: `bots.owner` DEFAULT `auth.uid()`; `bots.bubble_color` text; `public_bots` view recreated with `bubble_color`.
- `0003` beads economy: `profiles.credits` -> **beads**; +100 signup; `credit_events` ledger; chat-earn trigger `on_message_chat_earned` (+1 to bot owner per user message, ignores DMs); `claim_daily_beads()` RPC; `spend_bead(p_user)`/`refund_bead(p_user)` RPCs (atomic, **service_role-only grant**); profiles UPDATE column-granted to `(username, avatar_url)` only.
- `0004`: dropped stale `on_conversation_created` trigger.
- `0005`: `pfp` storage policy accepts both `user/<uid>/<file>` and `user/<uid>.<ext>`.
- `0006` human DMs: `conversations.dm_user_id`; unique index `least/greatest(user_id, dm_user_id)`; messages.sender_id; `public.people` view (`id, username, avatar_url, created_at, last_seen_at`).
- `0007_push_notifications`: FCM token storage (`profiles.fcm_token`), webhook triggers on new messages.
- `0008_read_receipts`: `conversations.user_last_read_at` and `conversations.dm_user_last_read_at`; `mark_as_read()` RPC; double ticks in chat (gray sent, blue read).
- `0009_media_and_replies`: `messages.media_url`, `messages.reply_to_id`, `messages.reply_to_content`, `messages.reply_to_sender`.
- `0010_people_created_at`: `people` view includes `created_at` for "Joined <Month Year>".
- `0011_suspend_daily_beads`: `claim_daily_beads()` suspended (returns -2).
- `0012_group_chats`: `conversations.is_group`, `title`, `created_by`, `avatar_url`; `conversation_members` table (`conversation_id, user_id, bot_id, role, joined_at, last_read_at`); `group_members_view`.
- `0013_fix_rls_recursion_and_storage`:
  - **CRITICAL RLS FIX**: Postgres throws `infinite recursion detected in policy for relation "conversation_members", code: 42P17` if policies on `conversation_members` run subqueries against `conversation_members`. Fixed by defining `SECURITY DEFINER` helpers:
    - `public.is_conversation_member(conv_id uuid, u_id uuid)`
    - `public.is_conversation_admin(conv_id uuid, u_id uuid)`
    - `public.is_conversation_owner(conv_id uuid, u_id uuid)`
  - Re-wrote `conversation_members` policies (select, insert, update, delete) to use these helpers exclusively.
  - Storage policies: added update, delete, and group photo upload policies to `pfp` bucket.
- `0014_user_presence_last_seen`:
  - `profiles.last_seen_at timestamptz default now()`.
  - `people` view includes `last_seen_at`.
  - `public.update_last_seen()` security-definer RPC function.

---

## Edge function `supabase/functions/ai-reply` (verify_jwt = false)

- POST `{conversation_id, bot_id?}` with user JWT in Authorization.
- Auth via `createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {global:{headers:{Authorization, apikey: ANON_KEY}}}).auth.getUser()`. **Do NOT pass user JWT as client key.**
- Provider chain: `DEEPSEEK_API_KEY` -> `deepseek-chat` with `thinking: {"type":"disabled"}`; fallback to `GEMMA_API_KEY` -> `gemma-4-31b-it` -> `gemma-3-27b-it`. 30s timeout, retry on 429/500/502/503.
- Group chat logic: Bot only replies when mentioned; beads taken from the sender and given to bot creator.
- Models must end on a **user turn**: trim trailing assistant messages; strip thinking output (`<(thought|think)>[\s\S]*<\/\1>`).

---

## App architecture & key services

- `lib/services/presence_service.dart`:
  - Singleton `PresenceService.instance`.
  - Tracks user presence on channel `presence:user:<uid>` using Supabase Realtime Presence.
  - Implements `WidgetsBindingObserver` to track `online: true` on resume and untrack on pause/detach.
  - Periodic 60s heartbeat calls `update_last_seen()` RPC.
  - `createPeerPresenceSubscription(peerId: ...)` for listening to peer online state real-time.
  - `formatLastActive(DateTime lastSeen)`:
    - `< 60s`: `last active just now`
    - `< 60m`: `last active 5 mins ago`
    - Today: `last active today at 10:28 AM`
    - Yesterday: `last active yesterday at 8:15 PM`
    - Within 7 days: `last active Monday at 10:28 AM`
    - Older: `last active 12 Sep`
- `lib/auth/auth_controller.dart`:
  - Starts `PresenceService.instance.start(uid)` upon authenticated session or login.
  - Calls `PresenceService.instance.stop()` on logout.
- `lib/services/conversations_service.dart`:
  - Handles DM, bot, and group conversations.
  - `watchConversation`, `watchMessages` (dedupes rows by id).
  - `markAsRead`, `getPeerProfile` (includes `last_seen_at`), `createGroup`, `getGroupMembers`.
- `lib/services/notifications_service.dart`:
  - Handles FCM push notifications.
  - `setupNavigation` routes clicks directly to `/chat/:id`.
  - Android manifest configured with `FLUTTER_NOTIFICATION_CLICK` intent filter and no interfering `android:taskAffinity`.
- `lib/services/updater_service.dart`:
  - Checks GitHub Releases anonymously for latest APK version.
  - Prompts in-app update dialog and installs via `open_filex`.

---

## Screen features & UI hierarchy

- **`ChatScreen`** (`lib/screens/chat_screen.dart`):
  - **Top AppBar**:
    - Human DMs:
      - Priority 1: `typing…` (primary accent color when peer is typing).
      - Priority 2: `online` (primary accent color with w500 when peer is in-app).
      - Priority 3: `last active <time ago>` (subtle text color when peer is offline).
    - Group Chats: shows member count or `<BotName> is typing…` or `typing…`.
    - Bot Chats: shows bot bio or `typing…`.
  - **Group Chats**:
    - Autocomplete mention suggestions popup when user types `@`.
    - Tapping mention inserts `@BotName `.
  - **Messages**:
    - Image attachments (`ImagePicker`), photo viewer (`FullScreenImageViewer`).
    - Swipe-to-reply or bottom sheet "Reply" quoting previous snippet.
    - Double ticks for read receipts (gray sent, blue read).
    - Optimistic bubbles with spring animations.
- **`PeerProfileScreen`** (`lib/screens/peer_profile_screen.dart`):
  - Displays avatar, display name, `@username` copy pill.
  - Live status badge (`Online now` with dot, or `last active <time ago>`).
  - Joined date (`Joined <Month Year>`).
  - Shared media gallery, clear chat history, delete chat.
- **`CreateGroupScreen`** (`lib/screens/create_group_screen.dart`):
  - Multi-select participants from both People and AI Characters tabs.
  - Group title and avatar upload.
- **`ChatsShellScreen`** / **`ChatsScreen`** / **`DiscoverScreen`** / **`ProfileScreen`**.

---

## Realtime channel naming convention

1. `presence:user:<uid>` — Personal presence channel for user `<uid>`. User tracks `{online: true}`, peers subscribe to read presence state.
2. `chat_presence:<conversation_id>` — Broadcast channel for `typing` and `stop_typing` events.
3. `supabase_realtime` — Built-in publication for Postgres changes on `conversations`, `messages`, `conversation_members`.

---

## Critical gotchas & lessons learned

1. **RLS infinite recursion (42P17)**:
   - **NEVER** write a policy on table `X` that runs a subquery on table `X` without wrapping it in a `SECURITY DEFINER` function!
   - In Supabase/Postgres, subqueries on the same table trigger the policy recursively until the depth limit is exceeded. Always use `is_conversation_member`, `is_conversation_admin`, or `is_conversation_owner`.
2. **Storage RLS on `pfp` bucket**:
   - `INSERT` policy alone is not enough; updating profile pictures needs an `UPDATE` policy (`bucket_id = 'pfp'`), and deleting needs a `DELETE` policy.
3. **Android notification click handling**:
   - Do NOT set `android:taskAffinity=""` on MainActivity; it prevents standard Android intent launchers and notifications from bringing the existing task to the foreground.
   - Keep `<action android:name="FLUTTER_NOTIFICATION_CLICK" />` inside MainActivity's `<intent-filter>`.
4. **Dart analysis on CI**:
   - Any warning or info fails the build.
   - Do NOT use `.catchError((_) {})` on futures returning non-void types unless returning a typed fallback (causes `body_might_complete_normally_catch_error`). Use `try { await ...; } catch (_) {}` instead.
   - Ensure all widget tree brackets are cleanly matched and const constructors are used where possible.
5. **Version Bumping**:
   - Always bump `version` in `pubspec.yaml` (e.g. `0.5.1` -> `0.5.2`) when making app-facing changes. CI tags the GitHub release from `pubspec.yaml`, which the in-app updater relies upon to detect updates.

---

## Diagnostics & test accounts

- Test account: `diag-rttext-176@proton.me` / `Diag-Test-176!`.
- Query logs: Supabase MCP `query_logs` (`source: "function_logs"` or `"function_edge_logs"`).
- Database SQL: Supabase MCP `execute_sql`.
