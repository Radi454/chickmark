import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';

void main() {
  group('AuditModel round-trip serialization', () {
    late DateTime fixedDate;

    setUp(() {
      fixedDate = DateTime(2026, 4, 24, 8, 0, 0);
    });

    AuditModel baseEggStorage() {
      return AuditModel(
        id: 'test-id',
        auditType: 'Egg',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel baseSetter() {
      return AuditModel(
        id: 'test-setter',
        auditType: 'Setters',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel baseHatcher() {
      return AuditModel(
        id: 'test-hatcher',
        auditType: 'Hatchers',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel baseChickQuality() {
      return AuditModel(
        id: 'test-pm',
        auditType: 'Chicks',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel fromMapWith(AuditModel base, Map<String, dynamic> overrides) {
      final map = base.toMap();
      map.addAll(overrides);
      map['updatedAt'] = DateTime.now().toIso8601String();
      return AuditModel.fromMap(map);
    }

    test('Egg expanded EST grid fields round-trip', () {
      final original = fromMapWith(baseEggStorage(), {
        'es_estReadingsJson':
            '{"door_top":19.5,"door_middle":20.1,"door_bottom":20.3,"middle_top":19.8,"middle_middle":20.0,"middle_bottom":20.2,"back_top":19.7,"back_middle":19.9,"back_bottom":20.4}',
        'es_estPhotosJson': '{"front_top":"/photos/front-top.jpg"}',
        'es_estAvg': 19.9,
        'es_estCv': 1.2,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esEstReadingsJson, original.esEstReadingsJson);
      expect(restored.esEstPhotosJson, original.esEstPhotosJson);
      expect(restored.esEstAvg, original.esEstAvg);
      expect(restored.esEstCv, original.esEstCv);
    });

    test('Egg expanded UV inspection fields round-trip', () {
      final original = fromMapWith(baseEggStorage(), {
        'es_uvSampleSize': 50,
        'es_uvCuticleDamageCount': 3,
        'es_uvWashingEvidenceCount': 2,
        'es_uvFecalCount': 1,
        'es_uvMottledCount': 4,
        'es_uvOtherCount': 0,
        'es_uvPhotosJson': '["photo1.jpg","photo2.jpg"]',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esUvSampleSize, original.esUvSampleSize);
      expect(restored.esUvCuticleDamageCount, original.esUvCuticleDamageCount);
      expect(
        restored.esUvWashingEvidenceCount,
        original.esUvWashingEvidenceCount,
      );
      expect(restored.esUvFecalCount, original.esUvFecalCount);
      expect(restored.esUvMottledCount, original.esUvMottledCount);
      expect(restored.esUvOtherCount, original.esUvOtherCount);
      expect(restored.esUvPhotosJson, original.esUvPhotosJson);
    });

    test('Egg expanded egg quality fields round-trip', () {
      final original = fromMapWith(baseEggStorage(), {
        'es_crackPct': 2.5,
        'es_brokenPct': 1.0,
        'es_misshapedPct': 3.2,
        'es_paleShellPct': 4.1,
        'es_roughTexturePct': 1.8,
        'es_floorEggPct': 0.5,
        'es_eggColorDistJson': '{"brown":60,"tinted":30,"white":10}',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esCrackPct, original.esCrackPct);
      expect(restored.esBrokenPct, original.esBrokenPct);
      expect(restored.esMisshapedPct, original.esMisshapedPct);
      expect(restored.esPaleShellPct, original.esPaleShellPct);
      expect(restored.esRoughTexturePct, original.esRoughTexturePct);
      expect(restored.esFloorEggPct, original.esFloorEggPct);
      expect(restored.esEggColorDistJson, original.esEggColorDistJson);
    });

    test('Egg expanded storage checklist fields round-trip', () {
      final original = fromMapWith(baseEggStorage(), {
        'es_eggOrientation': 'Point Down',
        'es_traySpacing': 'Adequate',
        'es_coolerProximity': 'Near',
        'es_wallProximity': 'Far',
        'es_condensation': 1,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esEggOrientation, 'Point Down');
      expect(restored.esTraySpacing, 'Adequate');
      expect(restored.esCoolerProximity, 'Near');
      expect(restored.esWallProximity, 'Far');
      expect(restored.esCondensation, true);
    });

    test('Egg condensation false round-trip', () {
      final original = fromMapWith(baseEggStorage(), {'es_condensation': 0});
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esCondensation, false);
    });

    test('Setters expanded machine type and turning angle round-trip', () {
      final original = fromMapWith(baseSetter(), {
        'so_machineType': 'Single',
        'so_turningAngle': 45.0,
        'so_setpointF': 100.0,
        'so_actualF': 100.4,
        'so_machineScreenPhoto': '/photos/setter-screen.jpg',
        'so_batchSize': 19200,
        'so_batchCount': 3,
        'so_totalEggsSet': 57600,
        'so_estSamplesJson':
            '[{"id":"sample-1","breed":"Ross308","incubationAge":7,"incubationHours":4,"estReadings":{"front_top":100.5},"estPhotos":{"front_top":"/photos/front.jpg"},"estAvg":100.5,"estCv":0.0}]',
        'soEstAvg': 100.5,
        'soEstCv': 0.3,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.soMachineType, 'Single');
      expect(restored.soTurningAngle, 45.0);
      expect(restored.soSetpointF, 100.0);
      expect(restored.soActualF, 100.4);
      expect(restored.soMachineScreenPhoto, '/photos/setter-screen.jpg');
      expect(restored.soBatchSize, 19200);
      expect(restored.soBatchCount, 3);
      expect(restored.soTotalEggsSet, 57600);
      expect(restored.soEstSamplesJson, contains('"breed":"Ross308"'));
      expect(restored.soEstAvg, 100.5);
      expect(restored.soEstCv, 0.3);
    });

    test('Hatchers expanded meconium and transfer day round-trip', () {
      final original = fromMapWith(baseHatcher(), {
        'ho_meconium': 'Normal',
        'ho_transferDay': 18,
        'hoCvtAvg': 104.2,
        'hoCvtCv': 0.5,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.hoMeconium, 'Normal');
      expect(restored.hoTransferDay, 18);
      expect(restored.hoCvtAvg, 104.2);
      expect(restored.hoCvtCv, 0.5);
    });

    test('PM Necropsy lesion and severity fields round-trip', () {
      final original = fromMapWith(baseChickQuality(), {
        'pm_sampleSize': 40,
        'pm_collectionPoint': 'Hatchery',
        'pm_omphalitisCount': 3,
        'pm_omphalitisSeverity': 'Moderate',
        'pm_gaseousCecaCount': 1,
        'pm_gaseousCecaSeverity': 'Mild',
        'pm_unabsorbedYolkCount': 5,
        'pm_unabsorbedYolkSeverity': 'Moderate',
        'pm_perihepatitisCount': 0,
        'pm_pericarditisCount': 2,
        'pm_pericarditisSeverity': 'Severe',
        'pm_airsacAcuteCount': 1,
        'pm_airsacAcuteSeverity': 'Mild',
        'pm_airsacChronicCount': 0,
        'pm_pulmonaryGranulomaCount': 0,
        'pm_swollenJointsCount': 1,
        'pm_swollenJointsSeverity': 'Mild',
        'pm_stuntedOrgansCount': 0,
        'pm_pulmonaryHemorrhageCount': 2,
        'pm_pulmonaryHemorrhageSeverity': 'Moderate',
        'pm_gizzardErosionsCount': 4,
        'pm_gizzardErosionsSeverity': 'Severe',
        'pm_airSacCaseationsCount': 5,
        'pm_airSacCaseationsSeverity': 'Moderate',
        'pm_nephritisCount': 6,
        'pm_nephritisSeverity': 'Mild',
        'pm_generalSepticemiaCount': 7,
        'pm_generalSepticemiaSeverity': 'Severe',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.pmSampleSize, 40);
      expect(restored.pmCollectionPoint, 'Hatchery');
      expect(restored.pmOmphalitisCount, 3);
      expect(restored.pmOmphalitisSeverity, 'Moderate');
      expect(restored.pmGaseousCecaCount, 1);
      expect(restored.pmGaseousCecaSeverity, 'Mild');
      expect(restored.pmUnabsorbedYolkCount, 5);
      expect(restored.pmPericarditisCount, 2);
      expect(restored.pmPericarditisSeverity, 'Severe');
      expect(restored.pmGizzardErosionsCount, 4);
      expect(restored.pmGizzardErosionsSeverity, 'Severe');
      expect(restored.pmAirSacCaseationsCount, 5);
      expect(restored.pmAirSacCaseationsSeverity, 'Moderate');
      expect(restored.pmNephritisCount, 6);
      expect(restored.pmNephritisSeverity, 'Mild');
      expect(restored.pmGeneralSepticemiaCount, 7);
      expect(restored.pmGeneralSepticemiaSeverity, 'Severe');
    });

    test('PM Necropsy gasping and deformity fields round-trip', () {
      final original = fromMapWith(baseChickQuality(), {
        'pm_gaspingPresent': 1,
        'pm_gaspingType': 'Abdominal',
        'pm_exposedBrainCount': 1,
        'pm_ectopicVisceraCount': 0,
        'pm_extraLegsCount': 0,
        'pm_crossedBeakCount': 2,
        'pm_absentEyeBothCount': 0,
        'pm_absentEyeOneCount': 1,
        'pm_smallEyeCount': 0,
        'pm_hydrocephalyCount': 1,
        'pm_starGazerCount': 0,
        'pm_curledToesCount': 1,
        'pm_shortLegsCount': 0,
        'pm_spinalDeformityCount': 0,
        'pm_cardiacAnomalyCount': 0,
        'pm_conjoinedCount': 0,
        'pm_otherDeformityCount': 3,
        'pm_otherDeformityText': 'Missing wing feather',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.pmGaspingPresent, true);
      expect(restored.pmGaspingType, 'Abdominal');
      expect(restored.pmExposedBrainCount, 1);
      expect(restored.pmCrossedBeakCount, 2);
      expect(restored.pmAbsentEyeOneCount, 1);
      expect(restored.pmHydrocephalyCount, 1);
      expect(restored.pmCurledToesCount, 1);
      expect(restored.pmOtherDeformityCount, 3);
      expect(restored.pmOtherDeformityText, 'Missing wing feather');
    });

    test('PM Necropsy cause and photo fields round-trip', () {
      final original = fromMapWith(baseChickQuality(), {
        'pm_suspectedCauseAuto': 'Omphalitis + Gizzard Erosions',
        'pm_suspectedCauseManual': 'Poor sanitation',
        'pm_photosJson': '["pm_photo1.jpg","pm_photo2.jpg"]',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.pmSuspectedCauseAuto, 'Omphalitis + Gizzard Erosions');
      expect(restored.pmSuspectedCauseManual, 'Poor sanitation');
      expect(restored.pmPhotosJson, '["pm_photo1.jpg","pm_photo2.jpg"]');
    });

    test('Chicks CVT grid fields round-trip', () {
      final original = fromMapWith(baseChickQuality(), {
        'cvtReadingsJson':
            '{"front_top":104.0,"front_middle":103.8,"front_bottom":103.6}',
        'cvtPhotosJson': '{"front_top":"/photos/cvt-front-top.jpg"}',
        'cvtAvg': 103.8,
        'cvtCvPct': 0.2,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.cvtReadingsJson, original.cvtReadingsJson);
      expect(restored.cvtPhotosJson, original.cvtPhotosJson);
      expect(restored.cvtAvg, original.cvtAvg);
      expect(restored.cvtCvPct, original.cvtCvPct);
    });

    test('null new fields do not break round-trip', () {
      final original = baseEggStorage();
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esEstReadingsJson, isNull);
      expect(restored.esEstAvg, isNull);
      expect(restored.esEstCv, isNull);
      expect(restored.esUvSampleSize, isNull);
      expect(restored.esUvCuticleDamageCount, isNull);
      expect(restored.esUvWashingEvidenceCount, isNull);
      expect(restored.esUvFecalCount, isNull);
      expect(restored.esUvMottledCount, isNull);
      expect(restored.esUvOtherCount, isNull);
      expect(restored.esUvPhotosJson, isNull);
      expect(restored.esCrackPct, isNull);
      expect(restored.esBrokenPct, isNull);
      expect(restored.esMisshapedPct, isNull);
      expect(restored.esPaleShellPct, isNull);
      expect(restored.esRoughTexturePct, isNull);
      expect(restored.esFloorEggPct, isNull);
      expect(restored.esEggColorDistJson, isNull);
      expect(restored.esEggOrientation, isNull);
      expect(restored.esTraySpacing, isNull);
      expect(restored.esCoolerProximity, isNull);
      expect(restored.esWallProximity, isNull);
      expect(restored.esCondensation, isFalse);
      expect(restored.soMachineType, isNull);
      expect(restored.soTurningAngle, isNull);
      expect(restored.hoMeconium, isNull);
      expect(restored.hoTransferDay, isNull);
      expect(restored.cvtReadingsJson, isNull);
      expect(restored.cvtPhotosJson, isNull);
      expect(restored.pmSampleSize, isNull);
      expect(restored.pmGaspingPresent, isFalse);
      expect(restored.pmPhotosJson, isNull);
    });

    test('sessionId round-trip for session-linked audits', () {
      final original = fromMapWith(baseEggStorage(), {
        'sessionId': 'session-abc-123',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.sessionId, 'session-abc-123');
    });

    test('sessionId null for historical audits', () {
      final original = baseEggStorage();
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.sessionId, isNull);
    });

    test('sample mode and breakout tray JSON fields round-trip', () {
      final original = fromMapWith(baseChickQuality(), {
        'sampleMode': 'compare',
        'compareGroupKey': 'compare-visit-1',
        'ebTrayBreakoutJson':
            '[{"id":"tray-1","label":"Tray 1","position":"Top","traySize":150,"breakoutType":"Hatch Residue","counts":{"infertile":3}}]',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.sampleMode, 'compare');
      expect(restored.compareGroupKey, 'compare-visit-1');
      expect(restored.ebTrayBreakoutJson, original.ebTrayBreakoutJson);
    });

    test('unknown sample mode normalizes to pool', () {
      final restored = fromMapWith(baseChickQuality(), {
        'sampleMode': 'unexpected',
      });

      expect(restored.sampleMode, 'pool');
    });
  });
}
