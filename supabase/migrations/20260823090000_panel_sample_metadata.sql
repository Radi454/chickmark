-- v61 mirror: explicit sample identity and domain ownership on panel rows.
-- Additive and nullable. Local camelCase maps to these names automatically
-- through _supabaseSnakeCase, so the column names must match exactly.
do $$
declare
  panel text;
begin
  foreach panel in array array[
    'egg_storage',
    'egg_quality',
    'chick_quality',
    'chick_weights',
    'fresh_egg_breakout',
    'candled_egg_breakout',
    'residue_breakout',
    'setter_optimizing',
    'hatcher_optimizing'
  ]
  loop
    execute format('alter table public.%I
      add column if not exists sample_mode text,
      add column if not exists scope_type text,
      add column if not exists sample_label text,
      add column if not exists sample_index integer,
      add column if not exists source_domain text,
      add column if not exists action_domain text,
      add column if not exists recommendation_target text', panel);
  end loop;
end $$;
