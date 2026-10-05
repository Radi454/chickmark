-- Keep read authorization separate from write actions so SELECT evaluates one policy.
drop policy if exists panel_sampling_states_write on public.panel_sampling_states;
create policy panel_sampling_states_insert on public.panel_sampling_states for insert to authenticated with check (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));
create policy panel_sampling_states_update on public.panel_sampling_states for update to authenticated using (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id))) with check (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));
create policy panel_sampling_states_delete on public.panel_sampling_states for delete to authenticated using (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));

drop policy if exists panel_sampling_nodes_write on public.panel_sampling_nodes;
create policy panel_sampling_nodes_insert on public.panel_sampling_nodes for insert to authenticated with check (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));
create policy panel_sampling_nodes_update on public.panel_sampling_nodes for update to authenticated using (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id))) with check (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));
create policy panel_sampling_nodes_delete on public.panel_sampling_nodes for delete to authenticated using (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));

drop policy if exists panel_sample_serial_reservations_write on public.panel_sample_serial_reservations;
create policy panel_sample_serial_reservations_insert on public.panel_sample_serial_reservations for insert to authenticated with check (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));
create policy panel_sample_serial_reservations_update on public.panel_sample_serial_reservations for update to authenticated using (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id))) with check (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));
create policy panel_sample_serial_reservations_delete on public.panel_sample_serial_reservations for delete to authenticated using (exists (select 1 from public.audit_sessions s where s.id = session_id and chickmark_private.app_can_write_customer(s.customer_id)));

