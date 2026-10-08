-- Suspend daily bead giveaway to simulate the economy and prevent hoarding.
create or replace function public.claim_daily_beads()
returns integer
language plpgsql
security definer set search_path = public
as $$
begin
  -- Daily giveaway is suspended; always returns -1 (no claim).
  return -1;
end;
$$;
