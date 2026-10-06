-- Human-to-human 1:1 DMs alongside AI bot chats.
-- conversations gains dm_user_id (the OTHER human) so a row is either a bot
-- chat (bot_id set, dm_user_id null) or a DM (dm_user_id set, bot_id null).
-- DMs are free: beads only ever pay for AI replies. The chat_earned trigger
-- (0003) resolves the owner via c.bot_id, which is null for DMs, so DM
-- messages never touch beads — enforced here, not in app code.
--
-- 1) dm_user_id column + "exactly one of bot_id/dm_user_id" check.
-- 2) Canonical pair uniqueness: one conversation per user pair.
-- 3) RLS widened to BOTH participants (conversations + messages).
-- 4) people view: username search without exposing beads.
-- 5) messages.sender_id to attribute DM bubbles to their sender.

-- ------------------------------------------------------ conversations.DM --
alter table public.conversations
  add column if not exists dm_user_id uuid
  references public.profiles (id) on delete cascade;

-- Exactly one of bot_id / dm_user_id must be set. NOT VALID skips scanning
-- existing rows (they all have bot_id and no dm_user_id, so they comply).
alter table public.conversations
  add constraint conversations_chat_type_check
  check ((bot_id is null) <> (dm_user_id is null))
  not valid;

-- Canonical pair: least/greatest orders the ids so (A,B) and (B,A) collide.
create unique index if not exists conversations_dm_pair_idx
  on public.conversations (least(user_id, dm_user_id), greatest(user_id, dm_user_id))
  where dm_user_id is not null;

-- Mirrors conversations_user_idx for the "other side" of DM list queries.
create index if not exists conversations_dm_user_idx
  on public.conversations (dm_user_id);

-- ------------------------------------------------------------- RLS: chats --
drop policy if exists "conversations_owner_all" on public.conversations;
create policy "conversations_participant_all" on public.conversations
  for all to authenticated
  using (auth.uid() = user_id or auth.uid() = dm_user_id)
  with check (auth.uid() = user_id or auth.uid() = dm_user_id);

-- Both participants read, insert, and delete messages. No update policy
-- (messages are immutable), same as before. The subquery runs under the
-- caller's RLS, so a participant resolves their own conversation row.
drop policy if exists "messages_select_own" on public.messages;
create policy "messages_select_participant" on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.user_id = auth.uid() or c.dm_user_id = auth.uid())
  ));
drop policy if exists "messages_insert_own" on public.messages;
create policy "messages_insert_participant" on public.messages
  for insert to authenticated
  with check (exists (
    select 1 from public.conversations c
    where c.id = conversation_id
      and (c.user_id = auth.uid() or c.dm_user_id = auth.uid())
  ));
drop policy if exists "messages_delete_own" on public.messages;
create policy "messages_delete_participant" on public.messages
  for delete to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id
      and (c.user_id = auth.uid() or c.dm_user_id = auth.uid())
  ));

-- ------------------------------------------------- messages.sender_id --
-- Set on user messages in DM chats (null in bot chats, where role already
-- distinguishes the sides). on delete set null keeps the message, unnamed.
alter table public.messages
  add column if not exists sender_id uuid
  references public.profiles (id) on delete set null;

-- ------------------------------------------------- people (search view) --
-- Username search surface. profiles is select-own-only and carries beads;
-- the view (security_invoker = false, like public_bots) exposes only id,
-- username, avatar_url to authenticated users, never the balance.
create or replace view public.people as
  select id, username, avatar_url
  from public.profiles;

grant select on public.people to authenticated;
