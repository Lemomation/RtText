-- RtText initial schema.
-- Idempotent-ish initial migration: profiles, bots, conversations, messages,
-- credits triggers, RLS (sys_prompt never exposed publicly), realtime, storage.

create extension if not exists "pgcrypto";

-- ---------------------------------------------------------------- profiles --
create table if not exists public.profiles (
  id uuid primary key references auth.users (id) on delete cascade,
  username text unique not null,
  avatar_url text,
  credits int not null default 0,
  created_at timestamptz not null default now()
);

alter table public.profiles enable row level security;

create policy "profiles_select_own" on public.profiles
  for select to authenticated using (auth.uid() = id);
create policy "profiles_update_own" on public.profiles
  for update to authenticated using (auth.uid() = id) with check (auth.uid() = id);
create policy "profiles_insert_own" on public.profiles
  for insert to authenticated with check (auth.uid() = id);

-- Auto-create a profile on signup; username from email prefix.
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username)
  values (
    new.id,
    coalesce(
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'user_' || left(new.id::text, 8)
    )
  )
  on conflict (id) do nothing;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ------------------------------------------------------------------- bots --
create table if not exists public.bots (
  id uuid primary key default gen_random_uuid(),
  owner uuid references public.profiles (id) on delete cascade,
  name text not null,
  bio text,
  description text,
  pfp_url text,
  sys_prompt text not null,
  is_public boolean not null default true,
  created_at timestamptz not null default now()
);

create index if not exists bots_owner_idx on public.bots (owner);

alter table public.bots enable row level security;

-- Owner-only access to the base table (including sys_prompt).
create policy "bots_owner_all" on public.bots
  for all to authenticated
  using (auth.uid() = owner)
  with check (auth.uid() = owner);

-- Hide the base table (and thus sys_prompt) from non-privileged roles;
-- reads go through the public_bots view below.
revoke all on public.bots from anon, authenticated;
grant select, insert, update, delete on public.bots to authenticated;

-- Public view without sys_prompt. security_invoker = false (default) means
-- the view runs with the privileges of the view owner (table owner, exempt
-- from RLS), and the WHERE clause enforces visibility instead.
create or replace view public.public_bots as
  select
    b.id,
    b.owner,
    b.name,
    b.bio,
    b.description,
    b.pfp_url,
    b.is_public,
    b.created_at
  from public.bots b
  where b.is_public or b.owner = auth.uid();

grant select on public.public_bots to anon, authenticated;

-- ----------------------------------------------------------- conversations --
create table if not exists public.conversations (
  id uuid primary key default gen_random_uuid(),
  user_id uuid references public.profiles (id) on delete cascade,
  bot_id uuid references public.bots (id) on delete cascade,
  last_message_at timestamptz not null default now(),
  created_at timestamptz not null default now(),
  unique (user_id, bot_id)
);

create index if not exists conversations_user_idx on public.conversations (user_id);

alter table public.conversations enable row level security;

create policy "conversations_owner_all" on public.conversations
  for all to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

-- ---------------------------------------------------------------- messages --
create table if not exists public.messages (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid references public.conversations (id) on delete cascade,
  role text not null check (role in ('user', 'assistant')),
  content text not null,
  created_at timestamptz not null default now()
);

create index if not exists messages_conversation_idx on public.messages (conversation_id, created_at);

alter table public.messages enable row level security;

create policy "messages_select_own" on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id and c.user_id = auth.uid()
  ));
create policy "messages_insert_own" on public.messages
  for insert to authenticated
  with check (exists (
    select 1 from public.conversations c
    where c.id = conversation_id and c.user_id = auth.uid()
  ));
create policy "messages_delete_own" on public.messages
  for delete to authenticated
  using (exists (
    select 1 from public.conversations c
    where c.id = messages.conversation_id and c.user_id = auth.uid()
  ));

-- ---------------------------------------------------------------- credits --
-- +10 credits for creating a bot.
create or replace function public.credit_bot_created()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  update public.profiles set credits = credits + 10 where id = new.owner;
  return new;
end;
$$;

drop trigger if exists on_bot_created on public.bots;
create trigger on_bot_created
  after insert on public.bots
  for each row execute function public.credit_bot_created();

-- +1 credit to the bot owner the first time someone else chats with it.
create or replace function public.credit_first_chat()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  bot_owner uuid;
begin
  select owner into bot_owner from public.bots where id = new.bot_id;
  if bot_owner is not null and bot_owner <> new.user_id then
    update public.profiles set credits = credits + 1 where id = bot_owner;
  end if;
  return new;
end;
$$;

drop trigger if exists on_conversation_created on public.conversations;
create trigger on_conversation_created
  after insert on public.conversations
  for each row execute function public.credit_first_chat();

-- ---------------------------------------------------------------- realtime --
alter publication supabase_realtime add table public.conversations;
alter publication supabase_realtime add table public.messages;

-- ----------------------------------------------------------------- storage --
insert into storage.buckets (id, name, public)
values ('pfp', 'pfp', true)
on conflict (id) do nothing;

-- Authenticated users may upload profile/character pictures under their own
-- user/<uid>/ prefix or a bot/<bot-id>/ prefix.
create policy "pfp_public_read" on storage.objects
  for select to public using (bucket_id = 'pfp');

create policy "pfp_authenticated_upload" on storage.objects
  for insert to authenticated with check (
    bucket_id = 'pfp'
    and (
      (storage.foldername(name))[1] = 'user'
        and (storage.foldername(name))[2] = auth.uid()::text
      or (storage.foldername(name))[1] = 'bot'
    )
  );
