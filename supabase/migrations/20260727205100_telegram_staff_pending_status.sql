begin;

alter table public.telegram_staff_links
  drop constraint if exists telegram_staff_links_status_check;

alter table public.telegram_staff_links
  add constraint telegram_staff_links_status_check
  check (status in ('pending', 'allowed', 'revoked'));

alter table public.telegram_staff_links
  alter column status set default 'pending';

commit;
