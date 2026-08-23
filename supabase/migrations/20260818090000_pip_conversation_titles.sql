-- 20260818090000 pip_conversation_titles
--
-- Multi-conversation support for the app door (app-hatchery-agent): each
-- agent_conversations row can now carry a short, derived title so a caller's
-- conversation list (action 'conversations') has something to show besides
-- the newest message preview. Titles are set once, from the caller's first
-- message, by conversation_title.ts's deriveConversationTitle — never
-- computed here. NULL means "not yet titled" (including every pre-existing
-- conversation), which the app door already treats as a placeholder to omit
-- unless it is the legacy 'app' conversation.

begin;

alter table public.agent_conversations
  add column if not exists title text;

commit;
