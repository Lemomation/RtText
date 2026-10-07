-- Read receipts and unread tracking for conversations.
-- Adds user_last_read_at (when conversation.user_id last read the chat)
-- and dm_user_last_read_at (when conversation.dm_user_id last read the chat).

alter table public.conversations
  add column if not exists user_last_read_at timestamptz not null default now(),
  add column if not exists dm_user_last_read_at timestamptz not null default now();
