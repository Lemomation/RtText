-- Beads economy (replaces credits).
-- 1 bead = 1 AI reply. +100 at signup, +20/day via lazy claim RPC,
-- +1 to a bot's owner per user message in their bot's conversations,
-- -1 charged by the ai-reply edge function only (reserve-then-refund).
-- No beads for creating a bot (minting loophole closed).

-- ----------------------------------------------------------------- rename --
alter table public.profiles rename column credits to beads;

alter table public.profiles add column if not exists last_daily_claim date;

-- Backfill: existing users get the signup grant they never received.
update public.profiles set beads = beads + 100;

insert into public.credit_events (user_id, delta, reason)
select id, 100, 'signup' from public.profiles
where not exists (
  select 1 from public.credit_events e
  where e.user_id = profiles.id and e.reason = 'signup'
);

-- -------------------------------------------------------------- ledger --
create type public.bead_reason as enum ('signup', 'daily', 'chat_spent', 'chat_earned');

create table public.credit_events (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references public.profiles (id) on delete cascade,
  delta int not null,
  reason public.bead_reason not null,
  ref_conversation uuid,
  ref_message uuid,
  created_at timestamptz not null default now()
);

create index credit_events_user_idx on public.credit_events (user_id, created_at desc);

alter table public.credit_events enable row level security;

-- Read-only for users; every write goes through triggers, the claim RPC,
-- or the ai-reply function's service-role client.
create policy "credit_events_select_own" on public.credit_events
  for select to authenticated using (auth.uid() = user_id);

-- --------------------------------------------------- signup grant (+100) --
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer set search_path = public
as $$
begin
  insert into public.profiles (id, username, beads)
  values (
    new.id,
    coalesce(
      nullif(split_part(coalesce(new.email, ''), '@', 1), ''),
      'user_' || left(new.id::text, 8)
    ),
    100
  )
  on conflict (id) do nothing;
  if found then
    insert into public.credit_events (user_id, delta, reason)
    values (new.id, 100, 'signup');
  end if;
  return new;
end;
$$;

-- ------------------------------------------ no beads for bot creation --
drop trigger if exists on_bot_created on public.bots;
drop function if exists public.credit_bot_created();

-- ------------------------------------- chat earning (+1 to bot owner) --
-- Fires on every user message; the owner earns exactly 1, including when
-- chatting with their own bot (net-zero with the chat_spent charge, by design).
create or replace function public.credit_chat_earned()
returns trigger
language plpgsql
security definer set search_path = public
as $$
declare
  bot_owner uuid;
begin
  if new.role <> 'user' then
    return new;
  end if;
  select b.owner into bot_owner
    from public.conversations c
    join public.bots b on b.id = c.bot_id
    where c.id = new.conversation_id;
  if bot_owner is not null then
    update public.profiles set beads = beads + 1 where id = bot_owner;
    insert into public.credit_events (user_id, delta, reason, ref_conversation, ref_message)
    values (bot_owner, 1, 'chat_earned', new.conversation_id, new.id);
  end if;
  return new;
end;
$$;

drop trigger if exists on_message_chat_earned on public.messages;
create trigger on_message_chat_earned
  after insert on public.messages
  for each row execute function public.credit_chat_earned();

-- ------------------------------------------------- daily claim (+20/day) --
-- Returns the new balance when a claim happened, -1 if already claimed today.
create or replace function public.claim_daily_beads()
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  new_balance int;
begin
  update public.profiles
    set beads = beads + 20, last_daily_claim = current_date
    where id = auth.uid()
      and (last_daily_claim is null or last_daily_claim < current_date)
    returning beads into new_balance;
  if new_balance is null then
    return -1;
  end if;
  insert into public.credit_events (user_id, delta, reason)
    values (auth.uid(), 20, 'daily');
  return new_balance;
end;
$$;

grant execute on function public.claim_daily_beads() to authenticated;

-- --------------------------------------------- spend / refund (atomic) --
-- Used by the ai-reply edge function via its service-role client. Locked
-- down to service_role so clients cannot move balances directly.
create or replace function public.spend_bead(p_user uuid)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  remaining int;
begin
  update public.profiles
    set beads = beads - 1
    where id = p_user and beads > 0
    returning beads into remaining;
  return coalesce(remaining, -1);
end;
$$;

create or replace function public.refund_bead(p_user uuid)
returns integer
language plpgsql
security definer set search_path = public
as $$
declare
  remaining int;
begin
  update public.profiles
    set beads = beads + 1
    where id = p_user
    returning beads into remaining;
  return coalesce(remaining, -1);
end;
$$;

revoke execute on function public.spend_bead(uuid) from public;
revoke execute on function public.refund_bead(uuid) from public;
grant execute on function public.spend_bead(uuid) to service_role;
grant execute on function public.refund_bead(uuid) to service_role;

-- --------------------------------------------- protect profile columns --
-- Users may edit their username and avatar but NOT their own balance
-- (beads) or claim date; those move only via the functions above.
revoke update on public.profiles from authenticated;
grant update (username, avatar_url) on public.profiles to authenticated;
