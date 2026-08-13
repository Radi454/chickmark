import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';
import 'package:hatchaudit/features/audits/logic/breakout_value_builders.dart';

void main() {
  group('isEggBreakoutPanelTable', () {
    test('accepts the three real egg-breakout panel tables', () {
      // Real table names declared in `PanelSampleSchema.panels`, the same
      // registry `database_schema.dart` iterates to create panel tables.
      expect(isEggBreakoutPanelTable('fresh_egg_breakout'), isTrue);
      expect(isEggBreakoutPanelTable('candled_egg_breakout'), isTrue);
      expect(isEggBreakoutPanelTable('residue_breakout'), isTrue);
    });

    test('rejects every other real panel table', () {
      final breakoutTables = {
        'fresh_egg_breakout',
        'candled_egg_breakout',
        'residue_breakout',
      };
      final nonBreakoutTables = PanelSampleSchema.panels
          .map((panel) => panel.tableName)
          .where((tableName) => !breakoutTables.contains(tableName));

      // Sanity check: the schema still declares non-breakout tables, so this
      // test isn't vacuously true.
      expect(nonBreakoutTables, isNotEmpty);
      for (final tableName in nonBreakoutTables) {
        expect(
          isEggBreakoutPanelTable(tableName),
          isFalse,
          reason: '$tableName should not be treated as an egg-breakout table',
        );
      }
    });

    test('rejects an unknown table name', () {
      expect(isEggBreakoutPanelTable('not_a_real_table'), isFalse);
    });
  });

  group('breakoutBmkColumnForCountKey', () {
    test('maps every known count key to its benchmark column', () {
      expect(
        breakoutBmkColumnForCountKey('early72hBloodRing'),
        'bloodRingPct',
      );
      expect(breakoutBmkColumnForCountKey('externalPip'), 'externalPipPct');
      expect(breakoutBmkColumnForCountKey('contaminated'), 'contamPct');
      expect(breakoutBmkColumnForCountKey('infertile'), 'infertilePct');
      expect(breakoutBmkColumnForCountKey('early24h'), 'early24hPct');
      expect(breakoutBmkColumnForCountKey('early48h'), 'early48hPct');
      expect(breakoutBmkColumnForCountKey('blackEye'), 'blackEyePct');
      expect(breakoutBmkColumnForCountKey('earlyDead'), 'earlyDeadPct');
      expect(breakoutBmkColumnForCountKey('midDead'), 'midDeadPct');
      expect(breakoutBmkColumnForCountKey('lateDead'), 'lateDeadPct');
      expect(breakoutBmkColumnForCountKey('cracked'), 'crackedPct');
    });

    test('returns null for an unknown count key', () {
      expect(breakoutBmkColumnForCountKey('somethingElse'), isNull);
      expect(breakoutBmkColumnForCountKey(''), isNull);
    });
  });

  group('breakoutDiffPct', () {
    const benchmark = <String, Object?>{
      'infertilePct': 5.0,
      'blackEyePct': 2.5,
    };

    test('returns the signed difference when both sides are available', () {
      expect(breakoutDiffPct(benchmark, 'infertile', 7.5), 2.5);
      expect(breakoutDiffPct(benchmark, 'infertile', 5.0), 0.0);
      expect(breakoutDiffPct(benchmark, 'blackEye', 1.0), closeTo(-1.5, 1e-9));
    });

    test('returns null when the benchmark map is null', () {
      expect(breakoutDiffPct(null, 'infertile', 7.5), isNull);
    });

    test('returns null when the current percentage is null', () {
      expect(breakoutDiffPct(benchmark, 'infertile', null), isNull);
    });

    test('returns null when the count key has no benchmark column', () {
      expect(breakoutDiffPct(benchmark, 'notARealKey', 7.5), isNull);
    });

    test('returns null when the benchmark map has no value for the column', () {
      expect(breakoutDiffPct(benchmark, 'earlyDead', 7.5), isNull);
    });
  });
}
