-- Extend the private photos bucket policy to cover Lab Analysis report PDFs.
-- Audit photos remain scoped by <auditSessionId>/..., while lab PDFs use
-- lab_analysis_reports/<customerId>/<flockId>/<date>/... and are also
-- authorized through the report row that references the object.

drop policy if exists photos_read on storage.objects;
drop policy if exists photos_write on storage.objects;

create policy photos_read on storage.objects for select to authenticated
  using (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_read_customer(s.customer_id)
      )
      or exists (
        select 1
        from public.lab_analysis_reports r
        where chickmark_private.app_can_read_customer(r.customer_id)
          and (
            r.report_file_remote_path = 'supabase://photos/' || name
            or r.report_file_remote_path like '%/photos/' || name
          )
      )
    )
  );

create policy photos_write on storage.objects for all to authenticated
  using (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_write_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
      or exists (
        select 1
        from public.lab_analysis_reports r
        where chickmark_private.app_can_write_customer(r.customer_id)
          and (
            r.report_file_remote_path = 'supabase://photos/' || name
            or r.report_file_remote_path like '%/photos/' || name
          )
      )
    )
  )
  with check (
    bucket_id = 'photos'
    and (
      exists (
        select 1
        from public.audit_sessions s
        where s.id = split_part(name, '/', 1)
          and chickmark_private.app_can_write_customer(s.customer_id)
      )
      or (
        split_part(name, '/', 1) = 'lab_analysis_reports'
        and chickmark_private.app_can_write_customer(
          split_part(name, '/', 2)
        )
      )
    )
  );
