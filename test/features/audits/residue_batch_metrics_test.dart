import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_sample.dart';
import 'package:hatchaudit/features/audits/models/residue_batch_metrics.dart';

import 'session_test_helpers.dart';

void main() {
  group('ResidueBatchMetrics', () {
    test(
      'calculates hatchability, unweighted tray-average fertility, and HOF',
      () {
        final audit = makeStationAudit(
          id: 'residue-1',
          auditType: 'Hatch Analysis & Egg Breakouts',
          haTotalEggsSet: 1000,
          haHatched: 850,
          haCulled: 10,
          haDead: 5,
          ebTrayBreakoutJson: jsonEncode([
            EggBreakoutSampleEntry.tray(
              id: 'tray-1',
              label: 'Tray 1',
              traySize: 100,
              breakoutType: EggBreakoutType.residueHatchDay,
              counts: {'infertile': 10},
            ).toJson(),
            EggBreakoutSampleEntry.tray(
              id: 'tray-2',
              label: 'Tray 2',
              traySize: 50,
              breakoutType: EggBreakoutType.residueHatchDay,
              counts: {'infertile': 10},
            ).toJson(),
          ]),
        );

        final metrics = ResidueBatchMetrics.fromAudit(audit);

        expect(metrics.hatchabilityPct, 85.0);
        expect(metrics.fertilityPct, 85.0);
        expect(metrics.hofPct, 100.0);
        expect(metrics.culledPct, 1.0);
        expect(metrics.deadPct, 0.5);
      },
    );

    test(
      'returns null for impossible counts instead of percentages above 100',
      () {
        final audit = makeStationAudit(
          id: 'residue-2',
          auditType: 'Hatch Analysis & Egg Breakouts',
          haTotalEggsSet: 100,
          haHatched: 101,
          haCulled: -1,
          haDead: 5,
          ebTrayBreakoutJson: jsonEncode([
            EggBreakoutSampleEntry.tray(
              id: 'tray-1',
              label: 'Tray 1',
              traySize: 100,
              breakoutType: EggBreakoutType.residueHatchDay,
              counts: {'infertile': 101},
            ).toJson(),
          ]),
        );

        final metrics = ResidueBatchMetrics.fromAudit(audit);

        expect(metrics.hatchabilityPct, isNull);
        expect(metrics.fertilityPct, isNull);
        expect(metrics.hofPct, isNull);
        expect(metrics.culledPct, isNull);
        expect(metrics.deadPct, 5.0);
      },
    );
  });
}
