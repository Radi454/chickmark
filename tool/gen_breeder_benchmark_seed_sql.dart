// Generates the Supabase seed SQL for one or more benchmark profile assets,
// so cloud and local hold identical values and neither is hand-typed.
//
//   dart run tool/gen_breeder_benchmark_seed_sql.dart \
//     assets/benchmarks/aviagen_indianriver_parent_stock_2021_en.json ... \
//     > supabase/migrations_unapplied/00NN_....sql
//
// Row ids are derived deterministically from the profile key and the row's
// index in the asset file (`profile-<key>-v<n>`), matching 0011's scheme, so
// re-running the emitted migration cannot duplicate rows. Metric definitions
// are emitted from assets/benchmarks/metric_definitions.json with
// `on conflict (code) do nothing`, so a definition 0011 already seeded is
// left alone.
import 'dart:convert';
import 'dart:io';

String sqlString(Object? value) {
  if (value == null) return 'null';
  return "'${value.toString().replaceAll("'", "''")}'";
}

String sqlNumber(Object? value) => value == null ? 'null' : '$value';

void main(List<String> args) {
  if (args.isEmpty) {
    stderr.writeln(
      'usage: gen_breeder_benchmark_seed_sql.dart <profile.json>...',
    );
    exitCode = 64;
    return;
  }

  final buffer = StringBuffer();

  final metrics =
      (jsonDecode(
                File(
                  'assets/benchmarks/metric_definitions.json',
                ).readAsStringSync(),
              )
              as Map<String, dynamic>)['metrics']
          as List;
  buffer.writeln('insert into public.breeder_metric_definitions');
  buffer.writeln(
    '  (id, code, label, unit, sex_scope, period_type, aggregation_method, display_precision)',
  );
  buffer.writeln('values');
  final metricRows = metrics.cast<Map<String, dynamic>>().map((m) {
    return "  ('metric-${m['code']}', ${sqlString(m['code'])}, "
        '${sqlString(m['label'])}, ${sqlString(m['unit'])}, '
        '${sqlString(m['sexScope'])}, ${sqlString(m['periodType'])}, '
        '${sqlString(m['aggregationMethod'])}, ${m['displayPrecision']})';
  });
  buffer.writeln(metricRows.join(',\n'));
  buffer.writeln('on conflict (code) do nothing;');

  for (final path in args) {
    final profile =
        jsonDecode(File(path).readAsStringSync()) as Map<String, dynamic>;
    final key = profile['profileKey'] as String;
    final profileId = 'profile-$key';

    buffer.writeln();
    buffer.writeln('-- $path');
    buffer.writeln('insert into public.breeder_benchmark_profiles');
    buffer.writeln(
      '  (id, profile_key, company, breed, product, guide_version, publication_date, source_url,\n'
      '   effective_age_start_days, effective_age_end_days, lifecycle_coverage, state)',
    );
    buffer.writeln('values');
    buffer.writeln(
      "  (${sqlString(profileId)}, ${sqlString(key)}, ${sqlString(profile['company'])}, "
      "${sqlString(profile['breed'])}, ${sqlString(profile['product'])}, "
      "${sqlString(profile['guideVersion'])}, ${sqlString(profile['publicationDate'])}, "
      "${sqlString(profile['sourceUrl'])}, ${profile['effectiveAgeStartDays']}, "
      "${sqlNumber(profile['effectiveAgeEndDays'])}, "
      "${sqlString(profile['lifecycleCoverage'])}, 'draft')",
    );
    buffer.writeln('on conflict (profile_key) do nothing;');
    buffer.writeln();

    final values = (profile['values'] as List).cast<Map<String, dynamic>>();
    buffer.writeln('insert into public.breeder_benchmark_values');
    buffer.writeln(
      '  (id, profile_id, metric_id, sex, age_days, age_week, production_week, period_type,\n'
      '   target_value, lower_bound, upper_bound)',
    );
    buffer.writeln(
      'select v.id, v.profile_id, v.metric_id, v.sex, v.age_days, v.age_week, v.production_week,\n'
      '       v.period_type, v.target_value, v.lower_bound, v.upper_bound',
    );
    buffer.writeln('from (values');
    final rows = <String>[];
    for (var i = 0; i < values.length; i++) {
      final v = values[i];
      rows.add(
        "  ('$profileId-v$i', ${sqlString(profileId)}, "
        "'metric-${v['metricCode']}', ${sqlString(v['sex'])}, "
        "${v['ageDays']}, ${v['ageWeek']}, ${sqlNumber(v['productionWeek'])}, "
        "${sqlString(v['periodType'])}, ${sqlNumber(v['targetValue'])}, "
        "${sqlNumber(v['lowerBound'])}, ${sqlNumber(v['upperBound'])})",
      );
    }
    buffer.writeln(rows.join(',\n'));
    buffer.writeln(
      ') as v(id, profile_id, metric_id, sex, age_days, age_week, production_week, period_type,\n'
      '       target_value, lower_bound, upper_bound)',
    );
    buffer.writeln('where not exists (');
    buffer.writeln(
      '  select 1 from public.breeder_benchmark_values existing where existing.id = v.id',
    );
    buffer.writeln(');');
    buffer.writeln();
    buffer.writeln('update public.breeder_benchmark_profiles');
    buffer.writeln(
      "  set state = ${sqlString(profile['state'])} where id = ${sqlString(profileId)} and state = 'draft';",
    );
  }

  stdout.write(buffer.toString());
}
