import 'dart:convert';

import '../../core/utils/calculation_utils.dart';

class PanelAggregateResult {
  const PanelAggregateResult({
    required this.row,
    this.qualityFlags = const <String>{},
  });

  final Map<String, Object?> row;
  final Set<String> qualityFlags;
}

/// Canonical raw-to-summary derivation used by every local panel write.
class PanelAggregateDeriver {
  const PanelAggregateDeriver._();

  static PanelAggregateResult derive(
    String table,
    Map<String, Object?> source,
  ) {
    final row = Map<String, Object?>.from(source);
    final flags = <String>{};

    switch (table) {
      case 'egg_storage':
        _deriveSeries(row, 'estReadingsJson', 'estAvg', 'estCvPct', flags);
      case 'egg_quality':
        _deriveWeights(
          row,
          jsonKey: 'eggWeightsJson',
          sizeKey: 'eggSampleSize',
          avgKey: 'eggAvgWeight',
          uniformityKey: 'eggUniformityPct',
          cvKey: 'eggCvPct',
          flags: flags,
        );
        _deriveRatio(
          row,
          'uvAffectedCount',
          'uvTrayEggCount',
          'uvAffectedPct',
          flags,
        );
        _deriveRatio(
          row,
          'uvCuticleDamageCount',
          'uvTrayEggCount',
          'uvCuticleDamagePct',
          flags,
        );
        _deriveRatio(
          row,
          'uvWashedCount',
          'uvTrayEggCount',
          'uvWashedPct',
          flags,
        );
        _deriveRatio(
          row,
          'uvDirtyCount',
          'uvTrayEggCount',
          'uvDirtyPct',
          flags,
        );
      case 'chick_quality':
        _derivePasgar(row, flags);
        _deriveSeries(
          row,
          'cvtReadingsJson',
          'cvtAvgTemp',
          'cvtCvPct',
          flags,
          sampleSizeKey: 'cvtSampleSize',
        );
      case 'chick_weights':
        _deriveWeights(
          row,
          jsonKey: 'weightsJson',
          sizeKey: 'sampleSize',
          avgKey: 'avgWeight',
          uniformityKey: 'uniformityPct',
          cvKey: 'cvPct',
          flags: flags,
        );
      case 'setter_optimizing':
        _deriveSeries(
          row,
          'estReadingsJson',
          'estAvg',
          'estCvPct',
          flags,
          sampleSizeKey: 'estSampleSize',
        );
      case 'hatcher_optimizing':
        _deriveSeries(
          row,
          'cvtReadingsJson',
          'cvtAvg',
          'cvtCvPct',
          flags,
          sampleSizeKey: 'cvtSampleSize',
        );
      case 'fresh_egg_breakout':
      case 'candled_egg_breakout':
      case 'residue_breakout':
        _deriveBreakout(row, flags);
    }

    return PanelAggregateResult(row: row, qualityFlags: flags);
  }

  static void _deriveSeries(
    Map<String, Object?> row,
    String rawKey,
    String avgKey,
    String cvKey,
    Set<String> flags, {
    String? sampleSizeKey,
  }) {
    if (!row.containsKey(rawKey) || row[rawKey] == null) return;
    final values = _numberList(row[rawKey]);
    if (values.isEmpty) {
      row[avgKey] = null;
      row[cvKey] = null;
      if (sampleSizeKey != null) row[sampleSizeKey] = 0;
      flags.add('missing_raw_values');
      return;
    }
    row[avgKey] = CalculationUtils.roundTo(CalculationUtils.average(values));
    row[cvKey] = CalculationUtils.cvPercent(values);
    if (sampleSizeKey != null) row[sampleSizeKey] = values.length;
  }

  static void _deriveWeights(
    Map<String, Object?> row, {
    required String jsonKey,
    required String sizeKey,
    required String avgKey,
    required String uniformityKey,
    required String cvKey,
    required Set<String> flags,
  }) {
    if (!row.containsKey(jsonKey) || row[jsonKey] == null) return;
    final values = _numberList(row[jsonKey]);
    if (values.isEmpty) {
      row[sizeKey] = 0;
      row[avgKey] = null;
      row[uniformityKey] = null;
      row[cvKey] = null;
      flags.add('missing_raw_values');
      return;
    }
    final avg = CalculationUtils.average(values);
    row[sizeKey] = values.length;
    row[avgKey] = CalculationUtils.roundTo(avg);
    row[uniformityKey] = CalculationUtils.uniformityPercent(
      values,
      avg * 0.9,
      avg * 1.1,
    );
    row[cvKey] = CalculationUtils.cvPercent(values);
  }

  static void _derivePasgar(Map<String, Object?> row, Set<String> flags) {
    final sample = _asInt(row['pasgarSampleSize']);
    if (sample == null) return;
    const countKeys = [
      'pasgarReflexesCount',
      'pasgarBeakCount',
      'pasgarNavelCount',
      'pasgarBellyCount',
      'pasgarLegCount',
      'pasgarFeatherDevCount',
    ];
    const pctKeys = [
      'pasgarReflexesPct',
      'pasgarBeakPct',
      'pasgarNavelPct',
      'pasgarBellyPct',
      'pasgarLegPct',
      'pasgarFeatherDevPct',
    ];
    final counts = <int>[];
    for (var i = 0; i < countKeys.length; i++) {
      final count = _asInt(row[countKeys[i]]) ?? 0;
      counts.add(count);
      final pct = CalculationUtils.percentOf(count, sample);
      row[pctKeys[i]] = pct;
      if (pct == null && count != 0) flags.add('invalid_denominator');
    }
    row['pasgarFinalScore'] = CalculationUtils.pasgarScore(sample, counts);
  }

  static void _deriveBreakout(Map<String, Object?> row, Set<String> flags) {
    final traySize = _asInt(row['traySize']);
    if (traySize == null) return;
    const pairs = {
      'infertileCount': 'infertilePct',
      'early24hCount': 'early24hPct',
      'early48hCount': 'early48hPct',
      'bloodRingCount': 'bloodRingPct',
      'blackEyeCount': 'blackEyePct',
      'earlyDeadCount': 'earlyDeadPct',
      'midDeadCount': 'midDeadPct',
      'lateDeadCount': 'lateDeadPct',
      'externalPipCount': 'externalPipPct',
      'crackedCount': 'crackedPct',
      'contaminatedCount': 'contaminatedPct',
    };
    for (final entry in pairs.entries) {
      if (!row.containsKey(entry.key)) continue;
      final count = _asInt(row[entry.key]);
      final pct = CalculationUtils.percentOf(count, traySize);
      row[entry.value] = pct;
      if (pct == null && count != null) flags.add('invalid_denominator');
    }
    final total = _asInt(row['totalEggsSet']);
    final hatched = _asInt(row['hatchedCount']);
    if (total != null && hatched != null) {
      final hatchability = CalculationUtils.percentOf(hatched, total);
      row['hatchabilityPct'] = hatchability;
      final infertile = _asInt(row['infertileCount']);
      final fertility = infertile == null
          ? null
          : CalculationUtils.percentOf(total - infertile, total);
      row['fertilityPct'] = fertility;
      row['hofPct'] =
          hatchability == null || fertility == null || fertility == 0
          ? null
          : CalculationUtils.percentOf(
              hatchability,
              fertility,
              allowAbove100: true,
            );
      row['culledPct'] = CalculationUtils.percentOf(
        _asInt(row['culledCount']),
        total,
      );
      row['deadPct'] = CalculationUtils.percentOf(
        _asInt(row['deadCount']),
        total,
      );
    }
  }

  static void _deriveRatio(
    Map<String, Object?> row,
    String numeratorKey,
    String denominatorKey,
    String outputKey,
    Set<String> flags,
  ) {
    if (!row.containsKey(numeratorKey) && !row.containsKey(denominatorKey)) {
      return;
    }
    final numerator = _asInt(row[numeratorKey]);
    final denominator = _asInt(row[denominatorKey]);
    final pct = CalculationUtils.percentOf(numerator, denominator);
    row[outputKey] = pct;
    if (pct == null && numerator != null) flags.add('invalid_denominator');
  }

  static List<double> _numberList(Object? raw) {
    Object? decoded = raw;
    if (raw is String) {
      final text = raw.trim();
      if (text.isEmpty) return const [];
      try {
        decoded = jsonDecode(text);
      } catch (_) {
        return const [];
      }
    }
    final out = <double>[];
    void collect(Object? value) {
      if (value is num) {
        out.add(value.toDouble());
      } else if (value is String) {
        final parsed = double.tryParse(value);
        if (parsed != null) out.add(parsed);
      } else if (value is Iterable) {
        for (final item in value) {
          collect(item);
        }
      } else if (value is Map) {
        for (final item in value.values) {
          collect(item);
        }
      }
    }

    collect(decoded);
    return out;
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '');
  }
}
