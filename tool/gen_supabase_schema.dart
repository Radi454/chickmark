// Generates Postgres DDL for the panel sample tables, mirroring the local SQLite
// schema (lib/data/database/database_schema.dart `_createPanelTable`) column-for-column.
//
// Column names use the SAME snake_case algorithm as SupabaseService._snakeCase so the
// generated columns match exactly what the client pushes (a mismatch = silent sync fail).
//
// Run:  dart run tool/gen_supabase_schema.dart
import 'package:hatchaudit/data/models/panel_sample_schema.dart';

/// Exact copy of SupabaseService._snakeCase — keep in sync.
String snake(String key) {
  final buffer = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final char = key[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

String pgType(String sqliteType) {
  switch (sqliteType.toUpperCase()) {
    case 'INTEGER':
      return 'integer';
    case 'REAL':
      return 'double precision';
    default:
      return 'text';
  }
}

/// 'estAvg REAL' -> '  est_avg double precision'
String col(String definition) {
  final parts = definition.trim().split(RegExp(r'\s+'));
  return '  ${snake(parts.first)} ${pgType(parts.length > 1 ? parts[1] : 'TEXT')}';
}

void main() {
  final buf = StringBuffer();
  for (final panel in PanelSampleSchema.panels) {
    final t = panel.tableName;
    final cols = <String>[
      '  id text primary key',
      '  session_id text not null',
      '  customer_id text not null',
      '  flock_id text',
      '  hatchery_id text',
      '  date text not null',
      '  breed text',
      '  flock_age_weeks integer',
      ...panel.hierarchyColumnDefinitions.map(col),
      '  storage_period_days integer',
      '  bmk_age_weeks integer',
      '  notes text',
      '  created_at text not null',
      '  updated_at text not null',
      "  sync_status text not null default 'pending'",
      '  last_synced_at text',
      '  sync_error text',
      ...panel.measurementColumns.map(col),
      '  foreign key (session_id) references public.audit_sessions(id) on delete cascade',
      '  foreign key (customer_id) references public.customers(id) on delete cascade',
      '  foreign key (flock_id) references public.flocks(id) on delete cascade',
      '  foreign key (hatchery_id) references public.hatcheries(id) on delete cascade',
    ];
    buf.writeln('create table public.$t (');
    buf.writeln(cols.join(',\n'));
    buf.writeln(');');
    buf.writeln('create index idx_${t}_session on public.$t(session_id);');
    buf.writeln(
      'create index idx_${t}_dashboard on public.$t(customer_id, flock_id, date);',
    );
    buf.writeln('alter table public.$t enable row level security;');
    buf.writeln(
      'create policy authenticated_all on public.$t for all to authenticated using (true) with check (true);',
    );
    buf.writeln();
  }
  // ignore: avoid_print
  print(buf.toString());
}
