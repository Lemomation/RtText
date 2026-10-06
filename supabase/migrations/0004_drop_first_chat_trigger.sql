-- Remove the superseded first-chat credit trigger.
-- Migration 0003 renamed profiles.credits → beads but missed this trigger,
-- so every conversation INSERT failed with 42703 (column "credits" does not
-- exist). The +1 to the bot's owner is now paid per user message by the
-- on_message_chat_earned trigger (migration 0003), which fully replaces it.

drop trigger if exists on_conversation_created on public.conversations;
drop function if exists public.credit_first_chat();
