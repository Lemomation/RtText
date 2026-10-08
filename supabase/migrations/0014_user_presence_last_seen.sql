-- Migration 0014: Track user presence and last active timestamp

-- Add last_seen_at column to profiles
alter table public.profiles
  add column if not exists last_seen_at timestamptz default now();

-- Update people view to include last_seen_at
create or replace view public.people as
select
  id,
  username,
  avatar_url,
  created_at,
  last_seen_at
from public.profiles;

-- RPC to update last_seen_at for the current authenticated user
create or replace function public.update_last_seen()
returns void
language sql
security definer
set search_path = public
as $$
  update public.profiles
  set last_seen_at = now()
  where id = auth.uid();
$$;

grant execute on function public.update_last_seen() to authenticated;
