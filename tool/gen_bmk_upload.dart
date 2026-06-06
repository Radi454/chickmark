// Emits SQL to mirror the local BMK reference seeds (lib/data/database/seeds/
// bmk_seeds.dart) into the Supabase `bmk_breeds` and `bmk_egg_breakout` tables.
//
// BMK is pull-only in the client sync (cloud -> local), so the app never uploads
// it. This one-shot generator makes the cloud match local exactly: delete-all +
// reinsert (BMK is lookup data; nothing FK-references it).
//
// Column names use the SAME snake_case algorithm as SupabaseService._snakeCase so
// they match the table DDL (a mismatch = silent insert fail).
//
// Run:  dart run tool/gen_bmk_upload.dart
import 'package:hatchaudit/data/database/seeds/bmk_seeds.dart';

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

String lit(Object? value) {
  if (value == null) return 'null';
  if (value is num) return value.toString();
  final escaped = value.toString().replaceAll("'", "''");
  return "'$escaped'";
}

String insertBlock(String table, List<Map<String, dynamic>> rows) {
  final columns = rows.first.keys.toList();
  final pgColumns = columns.map(snake).toList();
  final buf = StringBuffer();
  buf.writeln('delete from public.$table;');
  buf.writeln('insert into public.$table (${pgColumns.join(', ')}) values');
  final values = rows.map((row) {
    final cells = columns.map((column) => lit(row[column])).join(', ');
    return '  ($cells)';
  }).join(',\n');
  buf.writeln('$values;');
  return buf.toString();
}

void main() {
  final buf = StringBuffer();
  buf.writeln('begin;');
  buf.writeln(insertBlock('bmk_breeds', kBmkBreedSeeds));
  buf.writeln(insertBlock('bmk_egg_breakout', kBmkEggBreakoutSeeds));
  buf.writeln('commit;');
  // ignore: avoid_print
  print(buf.toString());
}
