-- RtText follow-ups.
-- 1) owner default: clients that insert a bot without specifying owner get
--    auth.uid() automatically (RLS bots_owner_all then passes). App code is
--    being fixed to send owner explicitly; this is the safety net.
-- 2) bubble_color: optional per-bot chat bubble accent chosen by the creator
--    (hex string like '#A78BFA', null = theme default). Exposed through the
--    public_bots view so any signed-in user's chat can render it.

alter table public.bots
  alter column owner set default auth.uid();

alter table public.bots
  add column if not exists bubble_color text;

-- Recreate the view with bubble_color appended (column order and grants of
-- the existing view are preserved; new columns may only be appended).
create or replace view public.public_bots as
  select
    b.id,
    b.owner,
    b.name,
    b.bio,
    b.description,
    b.pfp_url,
    b.is_public,
    b.created_at,
    b.bubble_color
  from public.bots b
  where b.is_public or b.owner = auth.uid();
