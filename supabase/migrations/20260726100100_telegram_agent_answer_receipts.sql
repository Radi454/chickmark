begin;

-- Backend-only webhook receipts keep successful staff-answer updates
-- idempotent. This table is intentionally excluded from the app sync graph.
create table public.telegram_agent_update_receipts (
  update_id text primary key,
  message_id text not null,
  staff_link_id text not null
    references public.telegram_staff_links(id) on delete cascade,
  telegram_chat_id text not null,
  submission_ids_json text not null,
  created_at text not null
);
create index idx_telegram_agent_update_receipts_staff
  on public.telegram_agent_update_receipts(staff_link_id, created_at desc);

alter table public.telegram_agent_update_receipts enable row level security;
revoke all on public.telegram_agent_update_receipts from anon, authenticated;
grant all on public.telegram_agent_update_receipts to service_role;

commit;
