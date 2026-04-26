import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';

void main() {
  group('AuditModel round-trip serialization', () {
    late DateTime fixedDate;

    setUp(() {
      fixedDate = DateTime(2026, 4, 24, 8, 0, 0);
    });

    AuditModel _baseEggStorage() {
      return AuditModel(
        id: 'test-id',
        auditType: 'Egg Storage',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel _baseSetter() {
      return AuditModel(
        id: 'test-setter',
        auditType: 'Setter Optimizing',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel _baseHatcher() {
      return AuditModel(
        id: 'test-hatcher',
        auditType: 'Hatcher Optimizing',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel _baseChickQuality() {
      return AuditModel(
        id: 'test-pm',
        auditType: 'Chick Quality',
        customerId: 'cust-1',
        flockId: 'flock-1',
        date: fixedDate,
        status: 'active',
        createdBy: 'auditor-1',
        createdAt: fixedDate,
        updatedAt: fixedDate,
      );
    }

    AuditModel _fromMapWith(AuditModel base, Map<String, dynamic> overrides) {
      final map = base.toMap();
      map.addAll(overrides);
      map['updatedAt'] = DateTime.now().toIso8601String();
      return AuditModel.fromMap(map);
    }

    test('Egg Storage expanded EST grid fields round-trip', () {
      final original = _fromMapWith(_baseEggStorage(), {
        'es_estReadingsJson': '{"door_top":19.5,"door_middle":20.1,"door_bottom":20.3,"middle_top":19.8,"middle_middle":20.0,"middle_bottom":20.2,"back_top":19.7,"back_middle":19.9,"back_bottom":20.4}',
        'es_estAvg': 19.9,
        'es_estCv': 1.2,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esEstReadingsJson, original.esEstReadingsJson);
      expect(restored.esEstAvg, original.esEstAvg);
      expect(restored.esEstCv, original.esEstCv);
    });

    test('Egg Storage expanded UV inspection fields round-trip', () {
      final original = _fromMapWith(_baseEggStorage(), {
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
      expect(restored.esUvWashingEvidenceCount, original.esUvWashingEvidenceCount);
      expect(restored.esUvFecalCount, original.esUvFecalCount);
      expect(restored.esUvMottledCount, original.esUvMottledCount);
      expect(restored.esUvOtherCount, original.esUvOtherCount);
      expect(restored.esUvPhotosJson, original.esUvPhotosJson);
    });

    test('Egg Storage expanded egg quality fields round-trip', () {
      final original = _fromMapWith(_baseEggStorage(), {
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

    test('Egg Storage expanded storage checklist fields round-trip', () {
      final original = _fromMapWith(_baseEggStorage(), {
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

    test('Egg Storage condensation false round-trip', () {
      final original = _fromMapWith(_baseEggStorage(), {
        'es_condensation': 0,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.esCondensation, false);
    });

    test('Setter Optimizing expanded machine type and turning angle round-trip', () {
      final original = _fromMapWith(_baseSetter(), {
        'so_machineType': 'Single Stage',
        'so_turningAngle': 45.0,
        'soEstAvg': 100.5,
        'soEstCv': 0.3,
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.soMachineType, 'Single Stage');
      expect(restored.soTurningAngle, 45.0);
      expect(restored.soEstAvg, 100.5);
      expect(restored.soEstCv, 0.3);
    });

    test('Hatcher Optimizing expanded meconium and transfer day round-trip', () {
      final original = _fromMapWith(_baseHatcher(), {
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
      final original = _fromMapWith(_baseChickQuality(), {
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
    });

    test('PM Necropsy gasping and deformity fields round-trip', () {
      final original = _fromMapWith(_baseChickQuality(), {
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
      final original = _fromMapWith(_baseChickQuality(), {
        'pm_suspectedCauseAuto': 'Omphalitis + Unabsorbed Yolk',
        'pm_suspectedCauseManual': 'Poor sanitation',
        'pm_photosJson': '["pm_photo1.jpg","pm_photo2.jpg"]',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.pmSuspectedCauseAuto, 'Omphalitis + Unabsorbed Yolk');
      expect(restored.pmSuspectedCauseManual, 'Poor sanitation');
      expect(restored.pmPhotosJson, '["pm_photo1.jpg","pm_photo2.jpg"]');
    });

    test('null new fields do not break round-trip', () {
      final original = _baseEggStorage();
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
      expect(restored.pmSampleSize, isNull);
      expect(restored.pmGaspingPresent, isFalse);
      expect(restored.pmPhotosJson, isNull);
    });

    test('sessionId round-trip for session-linked audits', () {
      final original = _fromMapWith(_baseEggStorage(), {
        'sessionId': 'session-abc-123',
      });
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.sessionId, 'session-abc-123');
    });

    test('sessionId null for historical audits', () {
      final original = _baseEggStorage();
      final map = original.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.sessionId, isNull);
    });
  });
}