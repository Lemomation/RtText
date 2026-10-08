-- Group chats: support for multi-user and multi-bot conversations.
-- 1) conversations gains is_group, title, avatar_url, created_by.
-- 2) conversation_members table tracks human and bot members.
-- 3) messages gains bot_id to attribute assistant replies to specific bots.
-- 4) group_members_view helper to fetch member names and avatars.
-- 5) RLS policies updated to allow group members full access.

-- -------------------------------------------------- conversations updates --
alter table public.conversations
  add column if not exists is_group boolean not null default false,
  add column if not exists title text,
  add column if not exists avatar_url text,
  add column if not exists created_by uuid references public.profiles (id) on delete set null;

alter table public.conversations drop constraint if exists conversations_chat_type_check;

alter table public.conversations
  add constraint conversations_chat_type_check
  check (
    (is_group = true and bot_id is null and dm_user_id is null)
    or
    (is_group = false and ((bot_id is null) <> (dm_user_id is null)))
  )
  not valid;

-- ---------------------------------------------------- conversation_members --
create table if not exists public.conversation_members (
  id uuid primary key default gen_random_uuid(),
  conversation_id uuid not null references public.conversations (id) on delete cascade,
  user_id uuid references public.profiles (id) on delete cascade,
  bot_id uuid references public.bots (id) on delete cascade,
  role text not null default 'member' check (role in ('admin', 'member')),
  joined_at timestamptz not null default now(),
  last_read_at timestamptz not null default now(),
  check ((user_id is null) <> (bot_id is null))
);

create unique index if not exists conversation_members_user_idx
  on public.conversation_members (conversation_id, user_id)
  where user_id is not null;

create unique index if not exists conversation_members_bot_idx
  on public.conversation_members (conversation_id, bot_id)
  where bot_id is not null;

create index if not exists conversation_members_conv_idx
  on public.conversation_members (conversation_id);

create index if not exists conversation_members_user_lookup_idx
  on public.conversation_members (user_id);

-- -------------------------------------------------------- messages.bot_id --
alter table public.messages
  add column if not exists bot_id uuid references public.bots (id) on delete set null;

-- ---------------------------------------------------- group_members_view --
create or replace view public.group_members_view as
  select
    m.id as member_id,
    m.conversation_id,
    m.user_id,
    m.bot_id,
    m.role,
    m.joined_at,
    m.last_read_at,
    case
      when m.user_id is not null then p.username
      when m.bot_id is not null then b.name
    end as name,
    case
      when m.user_id is not null then p.avatar_url
      when m.bot_id is not null then b.pfp_url
    end as avatar_url,
    case
      when m.bot_id is not null then true
      else false
    end as is_bot
  from public.conversation_members m
  left join public.people p on p.id = m.user_id
  left join public.public_bots b on b.id = m.bot_id;

grant select on public.group_members_view to authenticated;
grant select, insert, update, delete on public.conversation_members to authenticated;

-- -------------------------------------------------------------- RLS Setup --
alter table public.conversation_members enable row level security;

create policy "conversations_group_members_all" on public.conversations
  for all to authenticated
  using (
    is_group = true and exists (
      select 1 from public.conversation_members m
      where m.conversation_id = id and m.user_id = auth.uid()
    )
  )
  with check (
    is_group = true
  );

create policy "messages_group_select" on public.messages
  for select to authenticated
  using (exists (
    select 1 from public.conversations c
    join public.conversation_members m on m.conversation_id = c.id
    where c.id = messages.conversation_id
      and c.is_group = true
      and m.user_id = auth.uid()
  ));

create policy "messages_group_insert" on public.messages
  for insert to authenticated
  with check (exists (
    select 1 from public.conversations c
    join public.conversation_members m on m.conversation_id = c.id
    where c.id = conversation_id
      and c.is_group = true
      and m.user_id = auth.uid()
  ));

create policy "messages_group_delete" on public.messages
  for delete to authenticated
  using (
    sender_id = auth.uid()
    or exists (
      select 1 from public.conversations c
      where c.id = messages.conversation_id
        and c.is_group = true
        and c.created_by = auth.uid()
    )
  );

create policy "conversation_members_select" on public.conversation_members
  for select to authenticated
  using (
    exists (
      select 1 from public.conversation_members m
      where m.conversation_id = conversation_members.conversation_id
        and m.user_id = auth.uid()
    )
    or exists (
      select 1 from public.conversations c
      where c.id = conversation_members.conversation_id
        and (c.user_id = auth.uid() or c.created_by = auth.uid())
    )
  );

create policy "conversation_members_insert" on public.conversation_members
  for insert to authenticated
  with check (
    exists (
      select 1 from public.conversations c
      where c.id = conversation_id
        and (c.user_id = auth.uid() or c.created_by = auth.uid())
    )
    or exists (
      select 1 from public.conversation_members m
      where m.conversation_id = conversation_id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );

create policy "conversation_members_delete" on public.conversation_members
  for delete to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.conversations c
      where c.id = conversation_members.conversation_id
        and (c.user_id = auth.uid() or c.created_by = auth.uid())
    )
    or exists (
      select 1 from public.conversation_members m
      where m.conversation_id = conversation_members.conversation_id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );

create policy "conversation_members_update" on public.conversation_members
  for update to authenticated
  using (
    user_id = auth.uid()
    or exists (
      select 1 from public.conversations c
      where c.id = conversation_members.conversation_id
        and (c.user_id = auth.uid() or c.created_by = auth.uid())
    )
    or exists (
      select 1 from public.conversation_members m
      where m.conversation_id = conversation_members.conversation_id
        and m.user_id = auth.uid()
        and m.role = 'admin'
    )
  );
