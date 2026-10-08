-- Add created_at to people view for peer profile display (join date)
create or replace view public.people as
  select id, username, avatar_url, created_at
  from public.profiles;

grant select on public.people to authenticated;
