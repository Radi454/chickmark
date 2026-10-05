-- Run as the database test administrator against a project containing an approved
-- admin and an audit session. Fixtures use a unique panel key and always roll back.
begin;
do $test$
declare
  sid text;
  admin_id text;
  pk text := '__sampling_rpc_check_20261005_' || gen_random_uuid()::text;
  a text := gen_random_uuid()::text || '-a';
  b text := a || '-b';
  c text := a || '-c';
  d text := a || '-deleted';
  e text := a || '-e';
  denied boolean := false;
  assigned integer;
begin
  select id into sid from public.audit_sessions order by id limit 1;
  select id::text into admin_id from public.profiles where status='approved' and role='admin' limit 1;
  if sid is null or admin_id is null then raise exception 'Missing isolated test context'; end if;
  perform set_config('request.jwt.claim.sub','',true);
  perform set_config('request.jwt.claims','{}',true);
  begin
    perform public.reconcile_panel_sample_serials(sid,pk);
  exception when others then
    if sqlerrm = 'Not authorized to reconcile sampling serials' then denied := true; else raise; end if;
  end;
  if not denied then raise exception 'Unauthorized RPC unexpectedly succeeded'; end if;
  perform set_config('request.jwt.claim.sub',admin_id,true);
  perform set_config('request.jwt.claims',json_build_object('sub',admin_id,'role','authenticated')::text,true);
  execute 'set local role authenticated';
  insert into public.panel_sampling_nodes(id,session_id,panel_key,parent_id,level,identity_key,identity_json,sample_id,sample_number,is_terminal,created_at,updated_at)
  values (a,sid,pk,'','tray','1','{"code":"1"}',a,1,1,now()::text,now()::text),
         (b,sid,pk,'','tray','2','{"code":"2"}',b,1,1,now()::text,now()::text),
         (c,sid,pk,'','tray','3','{"code":"3"}',c,7,1,now()::text,now()::text);
  insert into public.panel_sample_serial_reservations(id,session_id,panel_key,sample_number,sample_id,created_at)
    values(d,sid,pk,7,d,now()::text);
  perform public.reconcile_panel_sample_serials(sid,pk);
  select sample_number into assigned from public.panel_sampling_nodes where id=a;
  if assigned <> 1 then raise exception 'Deterministic winner serial mismatch: %',assigned; end if;
  select sample_number into assigned from public.panel_sampling_nodes where id=b;
  if assigned <> 8 then raise exception 'Collision loser serial mismatch: %',assigned; end if;
  select sample_number into assigned from public.panel_sampling_nodes where id=c;
  if assigned <> 9 then raise exception 'Deleted reservation reused: %',assigned; end if;
  update public.panel_sampling_nodes set sample_number=1 where id=b;
  update public.panel_sample_serial_reservations set sample_number=1 where sample_id=b and panel_key=pk;
  update public.panel_sampling_states set serial_high_watermark=1 where panel_key=pk;
  perform public.reconcile_panel_sample_serials(sid,pk);
  select sample_number into assigned from public.panel_sampling_nodes where id=b;
  if assigned <> 8 then raise exception 'Stale node/reservation lowered canonical assignment'; end if;
  select serial_high_watermark into assigned from public.panel_sampling_states where panel_key=pk;
  if assigned <> 9 then raise exception 'Stale state lowered high watermark'; end if;
  delete from public.panel_sampling_nodes where id=b;
  insert into public.panel_sampling_nodes(id,session_id,panel_key,parent_id,level,identity_key,identity_json,sample_id,sample_number,is_terminal,created_at,updated_at)
    values(e,sid,pk,'','tray','4','{"code":"4"}',e,8,1,now()::text,now()::text);
  perform public.reconcile_panel_sample_serials(sid,pk);
  select sample_number into assigned from public.panel_sampling_nodes where id=e;
  if assigned <> 10 then raise exception 'Consumed deleted serial reused'; end if;
  perform public.reconcile_panel_sample_serials(sid,pk);
  select sample_number into assigned from public.panel_sampling_nodes where id=e;
  if assigned <> 10 then raise exception 'Second reconciliation was not stable'; end if;
end;
$test$;
rollback;
