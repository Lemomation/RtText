-- -----------------------------------------------------------------------------
-- 0013_fix_rls_recursion_and_storage.sql
-- Fixes:
-- 1. Infinite recursion in conversation_members RLS by using security definer
--    helpers public.is_conversation_member(), public.is_conversation_admin(),
--    and public.is_conversation_owner().
-- 2. Storage RLS policies for 'pfp' bucket: adds update, delete, and group upload
--    policies so users can update existing avatars and upload group photos.
-- -----------------------------------------------------------------------------

create or replace function public.is_conversation_member(conv_id uuid, u_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv_id
      and user_id = u_id
  );
$$;

create or replace function public.is_conversation_admin(conv_id uuid, u_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.conversation_members
    where conversation_id = conv_id
      and user_id = u_id
      and role = 'admin'
  );
$$;

create or replace function public.is_conversation_owner(conv_id uuid, u_id uuid)
returns boolean
language sql
security definer
set search_path = public
stable
as $$
  select exists (
    select 1 from public.conversations
    where id = conv_id
      and (user_id = u_id or created_by = u_id)
  );
$$;

grant execute on function public.is_conversation_admin(uuid, uuid) to authenticated;
grant execute on function public.is_conversation_owner(uuid, uuid) to authenticated;
grant execute on function public.is_conversation_member(uuid, uuid) to authenticated;

alter policy "conversation_members_select" on public.conversation_members
  using (
    user_id = auth.uid()
    or public.is_conversation_member(conversation_id, auth.uid())
    or public.is_conversation_owner(conversation_id, auth.uid())
  );

alter policy "conversation_members_insert" on public.conversation_members
  with check (
    public.is_conversation_owner(conversation_id, auth.uid())
    or public.is_conversation_admin(conversation_id, auth.uid())
  );

alter policy "conversation_members_update" on public.conversation_members
  using (
    user_id = auth.uid()
    or public.is_conversation_owner(conversation_id, auth.uid())
    or public.is_conversation_admin(conversation_id, auth.uid())
  );

alter policy "conversation_members_delete" on public.conversation_members
  using (
    user_id = auth.uid()
    or public.is_conversation_owner(conversation_id, auth.uid())
    or public.is_conversation_admin(conversation_id, auth.uid())
  );

alter policy "conversations_group_members_all" on public.conversations
  using (
    is_group = true and (
      created_by = auth.uid()
      or user_id = auth.uid()
      or public.is_conversation_member(id, auth.uid())
    )
  )
  with check (
    is_group = true
  );

alter policy "messages_group_select" on public.messages
  using (
    public.is_conversation_owner(conversation_id, auth.uid())
    or public.is_conversation_member(conversation_id, auth.uid())
  );

alter policy "messages_group_insert" on public.messages
  with check (
    public.is_conversation_owner(conversation_id, auth.uid())
    or public.is_conversation_member(conversation_id, auth.uid())
  );

alter policy "messages_group_delete" on public.messages
  using (
    sender_id = auth.uid()
    or public.is_conversation_owner(conversation_id, auth.uid())
  );

create policy "pfp_authenticated_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'pfp')
  with check (bucket_id = 'pfp');

create policy "pfp_authenticated_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'pfp');

create policy "pfp_authenticated_upload_groups" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'pfp');
