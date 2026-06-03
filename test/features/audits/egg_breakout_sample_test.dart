import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';

void main() {
  group('EggBreakoutType', () {
    test('calculates BMK age days by breakout workflow', () {
      expect(
        EggBreakoutType.freshEggBreakout.calculateBmkAgeDays(
          currentFlockAgeDays: 294,
          storageDays: 5,
        ),
        289,
      );
      expect(
        EggBreakoutType.candledEggBreakout.calculateBmkAgeDays(
          currentFlockAgeDays: 294,
          storageDays: 5,
          candlingDay: 10,
        ),
        279,
      );
      expect(
        EggBreakoutType.residueHatchDay.calculateBmkAgeDays(
          currentFlockAgeDays: 294,
          storageDays: 5,
        ),
        268,
      );
    });

    test('defaults missing storage days to zero for BMK age', () {
      expect(
        EggBreakoutType.freshEggBreakout.calculateBmkAgeDays(
          currentFlockAgeDays: 294,
          storageDays: null,
        ),
        294,
      );
      expect(
        EggBreakoutType.residueHatchDay.calculateBmkAgeDays(
          currentFlockAgeDays: 294,
          storageDays: null,
        ),
        273,
      );
    });

    test(
      'returns unavailable BMK age when current age is missing or storage is invalid',
      () {
        expect(
          EggBreakoutType.residueHatchDay.calculateBmkAgeDays(
            currentFlockAgeDays: null,
            storageDays: 5,
          ),
          isNull,
        );
        expect(
          EggBreakoutType.candledEggBreakout.calculateBmkAgeDays(
            currentFlockAgeDays: 294,
            storageDays: -1,
          ),
          isNull,
        );
      },
    );

    test('uses type-specific breakout item sets', () {
      expect(EggBreakoutType.freshEggBreakout.countFields.map((f) => f.key), [
        'infertile',
        'early24h',
        'early48h',
        'early72hBloodRing',
      ]);
      expect(EggBreakoutType.candledEggBreakout.countFields.map((f) => f.key), [
        'infertile',
        'early24h',
        'early48h',
        'early72hBloodRing',
        'blackEye',
      ]);
      expect(EggBreakoutType.residueHatchDay.countFields.map((f) => f.key), [
        'infertile',
        'earlyDead',
        'midDead',
        'lateDead',
        'externalPip',
        'cracked',
        'contaminated',
      ]);
    });
  });

  group('EggBreakoutSampleEntry', () {
    test('calculates tray sample totals and percentages', () {
      final sample = EggBreakoutSampleEntry.tray(
        id: 'sample-1',
        label: 'Tray 1',
        position: 'top',
        traySize: 150,
        counts: {'infertile': 15},
      );

      expect(sample.sampleMode, EggBreakoutSampleMode.tray);
      expect(sample.totalSample, 150);
      expect(sample.percentageFor('infertile'), 10);
    });

    test('rejects impossible count percentages above sample total', () {
      final sample = EggBreakoutSampleEntry.tray(
        id: 'sample-1',
        label: 'Tray 1',
        traySize: 150,
        counts: {'infertile': 151},
      );

      expect(sample.percentageFor('infertile'), isNull);
    });

    test('calculates pool sample totals and percentages', () {
      final sample = EggBreakoutSampleEntry.pool(
        id: 'sample-1',
        label: 'Pool 1',
        numberOfTrays: 4,
        traySize: 150,
        counts: {'infertile': 30},
      );

      expect(sample.sampleMode, EggBreakoutSampleMode.pool);
      expect(sample.totalSample, 600);
      expect(sample.percentageFor('infertile'), 5);
    });

    test('returns null percentage for invalid totals without crashing', () {
      final sample = EggBreakoutSampleEntry.tray(
        id: 'sample-1',
        label: 'Tray 1',
        traySize: 0,
        counts: {'infertile': 30},
      );

      expect(sample.totalSample, isNull);
      expect(sample.percentageFor('infertile'), isNull);
    });

    test('round-trips tray and pool samples through persisted JSON', () {
      final source = [
        EggBreakoutSampleEntry.tray(
          id: 'tray-1',
          label: 'Tray 1',
          position: 'top',
          traySize: 150,
          breakoutType: EggBreakoutType.freshEggBreakout,
          counts: {'infertile': 3, 'early24h': 2},
        ),
        EggBreakoutSampleEntry.pool(
          id: 'pool-1',
          label: 'Pool 1',
          numberOfTrays: 3,
          traySize: 150,
          breakoutType: EggBreakoutType.candledEggBreakout,
          counts: {'blackEye': 4, 'midDead': 5},
        ),
      ];

      final encoded = jsonEncode(
        source.map((sample) => sample.toJson()).toList(),
      );
      final restored = EggBreakoutSampleEntry.decodeList(encoded);

      expect(restored, hasLength(2));
      expect(restored.first.sampleMode, EggBreakoutSampleMode.tray);
      expect(restored.first.label, 'Tray 1');
      expect(restored.first.position, 'top');
      expect(restored.first.totalSample, 150);
      expect(restored.last.sampleMode, EggBreakoutSampleMode.pool);
      expect(restored.last.numberOfTrays, 3);
      expect(restored.last.totalSample, 450);
      expect(restored.last.counts['blackEye'], 4);
    });

    test('does not default cleaned residue count fields to zero', () {
      final sample = EggBreakoutSampleEntry.fromJson({
        'id': 'tray-1',
        'sampleMode': 'tray',
        'breakoutType': 'residueHatchDay',
        'counts': {'earlyDead': 0, 'early24h': 0},
      }, index: 1);

      expect(sample.counts.containsKey('earlyDead'), isFalse);
      expect(sample.counts.containsKey('early24h'), isFalse);
    });
  });
}
