import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/egg_breakout_tray_rollup.dart';

void main() {
  group('EggBreakoutTrayRollup', () {
    test('recomputes all breakout totals from tray JSON', () {
      final json = jsonEncode([
        {
          'id': 'tray-1',
          'label': 'Tray 1',
          'position': 'Top',
          'traySize': 150,
          'breakoutType': 'Hatch Residue',
          'counts': {
            'infertile': 3,
            'earlyDead': 2,
            'midDead': 1,
            'lateDead': 4,
            'internalPip': 5,
            'externalPip': 6,
            'cracked': 1,
            'contaminated': 2,
            'malposition': 3,
            'exposedBrain': 0,
            'crossedBeak': 1,
            'culledDead': 2,
          },
        },
        {
          'id': 'tray-2',
          'label': 'Tray 2',
          'position': 'Middle',
          'traySize': 150,
          'breakoutType': 'Hatch Residue',
          'counts': {
            'infertile': 4,
            'earlyDead': 1,
            'midDead': 2,
            'lateDead': 3,
            'internalPip': 2,
            'externalPip': 1,
            'cracked': 0,
            'contaminated': 1,
            'malposition': 2,
            'exposedBrain': 1,
            'crossedBeak': 0,
            'culledDead': 3,
          },
        },
      ]);

      final fields = EggBreakoutTrayRollup.fromJson(json).toAuditFields();

      expect(fields['ebTraySize'], 300);
      expect(fields['ebInfertileCount'], 7);
      expect(fields['ebEarlyDeadCount'], 3);
      expect(fields['ebMidDeadCount'], 3);
      expect(fields['ebLateDeadCount'], 7);
      expect(fields['ebInternalPipCount'], 7);
      expect(fields['ebExternalPipCount'], 7);
      expect(fields['ebCrackedCount'], 1);
      expect(fields['ebContaminatedCount'], 3);
      expect(fields['ebMalpositionCount'], 5);
      expect(fields['ebExposedBrainCount'], 1);
      expect(fields['ebCrossedBeakCount'], 1);
      expect(fields['ebCulledDeadCount'], 5);
    });

    test('editing or removing trays recomputes from scratch', () {
      final initial = jsonEncode([
        {
          'id': 'tray-1',
          'label': 'Tray 1',
          'position': 'Top',
          'traySize': 150,
          'breakoutType': 'Hatch Residue',
          'counts': {'infertile': 10, 'lateDead': 5},
        },
        {
          'id': 'tray-2',
          'label': 'Tray 2',
          'position': 'Middle',
          'traySize': 150,
          'breakoutType': 'Hatch Residue',
          'counts': {'infertile': 10, 'lateDead': 5},
        },
      ]);
      final edited = jsonEncode([
        {
          'id': 'tray-2',
          'label': 'Tray 2',
          'position': 'Middle',
          'traySize': 150,
          'breakoutType': 'Hatch Residue',
          'counts': {'infertile': 1, 'lateDead': 2},
        },
      ]);

      expect(
        EggBreakoutTrayRollup.fromJson(
          initial,
        ).toAuditFields()['ebInfertileCount'],
        20,
      );
      final editedFields = EggBreakoutTrayRollup.fromJson(
        edited,
      ).toAuditFields();

      expect(editedFields['ebTraySize'], 150);
      expect(editedFields['ebInfertileCount'], 1);
      expect(editedFields['ebLateDeadCount'], 2);
    });
  });
}
