// One-shot: turns tool/bmk_breeds_local.tsv (a dump of the LOCAL sqlite bmk_breeds
// table, dense per-week) into delete-all + insert SQL for the Supabase bmk_breeds
// table. IDs kept verbatim (the local mixed-prefix scheme is intentional here).
//
// Columns (tab-separated, no header):
//   id  breed  ageWeek  hatchabilityPct  fertilityPct  hofPct  productionPct  eggWeightG  chickWeightG
//
// Run:  dart run tool/gen_bmk_breeds_from_tsv.dart
import 'dart:io';

const _columns = [
  'id',
  'breed',
  'age_week',
  'hatchability_pct',
  'fertility_pct',
  'hof_pct',
  'production_pct',
  'egg_weight_g',
  'chick_weight_g',
];

String lit(String raw, {required bool text}) {
  if (text) return "'${raw.replaceAll("'", "''")}'";
  return raw; // numeric / integer verbatim
}

void main() {
  final lines = File('tool/bmk_breeds_local.tsv')
      .readAsLinesSync()
      .where((line) => line.trim().isNotEmpty)
      .toList();

  final byBreed = <String, int>{};
  final values = <String>[];
  final seenIds = <String>{};
  for (final line in lines) {
    final cells = line.split('\t');
    if (cells.length != _columns.length) {
      stderr.writeln('BAD ROW (${cells.length} cells): $line');
      exitCode = 1;
      continue;
    }
    if (!seenIds.add(cells[0])) {
      stderr.writeln('DUPLICATE id: ${cells[0]}');
      exitCode = 1;
    }
    byBreed.update(cells[1], (v) => v + 1, ifAbsent: () => 1);
    final rendered = [
      lit(cells[0], text: true), // id
      lit(cells[1], text: true), // breed
      lit(cells[2], text: false), // age_week (int)
      for (var i = 3; i < cells.length; i++) lit(cells[i], text: false),
    ].join(', ');
    values.add('  ($rendered)');
  }

  final buf = StringBuffer();
  buf.writeln('begin;');
  buf.writeln('delete from public.bmk_breeds;');
  buf.writeln('insert into public.bmk_breeds (${_columns.join(', ')}) values');
  buf.writeln('${values.join(',\n')};');
  buf.writeln('commit;');
  stdout.write(buf.toString());

  stderr.writeln('--- ${values.length} rows ---');
  final breeds = byBreed.keys.toList()..sort();
  for (final breed in breeds) {
    stderr.writeln('  $breed: ${byBreed[breed]}');
  }
}
