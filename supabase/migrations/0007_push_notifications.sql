-- Push notification device tokens for human DM messaging.
-- Each user records their Firebase Cloud Messaging (FCM) tokens on sign in.
-- Service role / Edge Functions query recipient tokens to deliver push notifications.

create table if not exists public.user_push_tokens (
  user_id uuid not null references public.profiles (id) on delete cascade,
  token text not null,
  platform text not null default 'android',
  updated_at timestamptz not null default now(),
  primary key (user_id, token)
);

-- RLS: users manage only their own device tokens
alter table public.user_push_tokens enable row level security;

create policy "push_tokens_select_own"
  on public.user_push_tokens for select to authenticated
  using (auth.uid() = user_id);

create policy "push_tokens_insert_own"
  on public.user_push_tokens for insert to authenticated
  with check (auth.uid() = user_id);

create policy "push_tokens_update_own"
  on public.user_push_tokens for update to authenticated
  using (auth.uid() = user_id)
  with check (auth.uid() = user_id);

create policy "push_tokens_delete_own"
  on public.user_push_tokens for delete to authenticated
  using (auth.uid() = user_id);

create index if not exists user_push_tokens_user_id_idx
  on public.user_push_tokens (user_id);
