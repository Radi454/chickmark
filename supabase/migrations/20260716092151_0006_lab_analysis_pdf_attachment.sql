alter table public.lab_analysis_reports
  add column if not exists report_file_name text,
  add column if not exists report_file_path text,
  add column if not exists report_file_remote_path text;
