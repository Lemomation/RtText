-- Milestone 3: Rich Media & Interactions
-- Create storage bucket for chat attachments and add media/reply columns to messages.

insert into storage.buckets (id, name, public)
values ('chat_media', 'chat_media', true)
on conflict (id) do nothing;

create policy "chat_media_public_read" on storage.objects
  for select to public using (bucket_id = 'chat_media');

create policy "chat_media_authenticated_upload" on storage.objects
  for insert to authenticated with check (bucket_id = 'chat_media');

create policy "chat_media_authenticated_delete" on storage.objects
  for delete to authenticated using (bucket_id = 'chat_media');

alter table public.messages
  alter column content drop not null;

alter table public.messages
  add column if not exists media_url text,
  add column if not exists reply_to_id uuid references public.messages(id) on delete set null,
  add column if not exists reply_to_content text,
  add column if not exists reply_to_sender text;
