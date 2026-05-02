import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_model.dart';

/// Validates PM Necropsy conditional rules and returns a list of errors.
/// Returns empty list if valid.
List<String> validatePmConditionalRules(AuditModel audit) {
  final errors = <String>[];

  // Rule: When a lesion count > 0, severity is required.
  final lesionPairs = <List<dynamic>>[
    ['Omphalitis', audit.pmOmphalitisCount, audit.pmOmphalitisSeverity],
    ['Gaseous Ceca', audit.pmGaseousCecaCount, audit.pmGaseousCecaSeverity],
    [
      'Unabsorbed Yolk',
      audit.pmUnabsorbedYolkCount,
      audit.pmUnabsorbedYolkSeverity,
    ],
    [
      'Perihepatitis',
      audit.pmPerihepatitisCount,
      audit.pmPerihepatitisSeverity,
    ],
    ['Pericarditis', audit.pmPericarditisCount, audit.pmPericarditisSeverity],
    ['Airsac Acute', audit.pmAirsacAcuteCount, audit.pmAirsacAcuteSeverity],
    [
      'Airsac Chronic',
      audit.pmAirsacChronicCount,
      audit.pmAirsacChronicSeverity,
    ],
    [
      'Pulmonary Granuloma',
      audit.pmPulmonaryGranulomaCount,
      audit.pmPulmonaryGranulomaSeverity,
    ],
    [
      'Swollen Joints',
      audit.pmSwollenJointsCount,
      audit.pmSwollenJointsSeverity,
    ],
    [
      'Stunted Organs',
      audit.pmStuntedOrgansCount,
      audit.pmStuntedOrgansSeverity,
    ],
    [
      'Pulmonary Hemorrhage',
      audit.pmPulmonaryHemorrhageCount,
      audit.pmPulmonaryHemorrhageSeverity,
    ],
  ];

  for (final pair in lesionPairs) {
    final label = pair[0] as String;
    final count = pair[1] as int?;
    final severity = pair[2] as String?;
    if ((count ?? 0) > 0 && (severity == null || severity.isEmpty)) {
      errors.add('$label requires severity when count > 0');
    }
  }

  // Rule: When gasping is present, subtype is required.
  if (audit.pmGaspingPresent == true &&
      (audit.pmGaspingType == null || audit.pmGaspingType!.isEmpty)) {
    errors.add('Gasping subtype is required when gasping is present');
  }

  // Rule: When other deformity count > 0, free-text description is required.
  if ((audit.pmOtherDeformityCount ?? 0) > 0 &&
      (audit.pmOtherDeformityText == null ||
          audit.pmOtherDeformityText!.isEmpty)) {
    errors.add('Other deformity description is required when count > 0');
  }

  return errors;
}

/// Builds an AuditModel with PM fields using a map of overrides.
AuditModel _buildPmAudit(Map<String, dynamic> pmOverrides) {
  final base = AuditModel(
    id: 'pm-test-id',
    auditType: 'Chicks',
    customerId: 'cust-pm',
    flockId: 'flock-pm',
    date: DateTime(2026, 4, 25),
    status: 'active',
    createdBy: 'auditor-pm',
    createdAt: DateTime(2026, 4, 25),
    updatedAt: DateTime(2026, 4, 25),
  );
  final map = base.toMap();
  map.addAll(pmOverrides);
  return AuditModel.fromMap(map);
}

void main() {
  group('PM Necropsy conditional validation', () {
    test('valid when no lesions are present and no gasping', () {
      final audit = _buildPmAudit({
        'pm_sampleSize': 40,
        'pm_collectionPoint': 'Receiving',
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors, isEmpty);
    });

    test('valid when lesions have counts AND severities', () {
      final audit = _buildPmAudit({
        'pm_sampleSize': 40,
        'pm_omphalitisCount': 3,
        'pm_omphalitisSeverity': 'Moderate',
        'pm_gaseousCecaCount': 1,
        'pm_gaseousCecaSeverity': 'Mild',
        'pm_unabsorbedYolkCount': 2,
        'pm_unabsorbedYolkSeverity': 'Severe',
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors, isEmpty);
    });

    test('returns error when lesion count > 0 but severity is missing', () {
      final audit = _buildPmAudit({'pm_omphalitisCount': 3});

      final errors = validatePmConditionalRules(audit);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Omphalitis')), true);
    });

    test(
      'returns error when lesion count > 0 but severity is empty string',
      () {
        final audit = _buildPmAudit({
          'pm_omphalitisCount': 3,
          'pm_omphalitisSeverity': '',
        });

        final errors = validatePmConditionalRules(audit);
        expect(errors, isNotEmpty);
        expect(errors.any((e) => e.contains('Omphalitis')), true);
      },
    );

    test('returns multiple errors for multiple lesions missing severity', () {
      final audit = _buildPmAudit({
        'pm_omphalitisCount': 3,
        'pm_pericarditisCount': 2,
        'pm_airsacAcuteCount': 1,
        'pm_airsacAcuteSeverity': 'Mild',
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors.length, 2);
      expect(errors.any((e) => e.contains('Omphalitis')), true);
      expect(errors.any((e) => e.contains('Pericarditis')), true);
    });

    test('no error when lesion count is 0 and severity is null', () {
      final audit = _buildPmAudit({'pm_omphalitisCount': 0});

      final errors = validatePmConditionalRules(audit);
      expect(errors.any((e) => e.contains('Omphalitis')), false);
    });

    test('no error when lesion count is null', () {
      final audit = _buildPmAudit({});
      final errors = validatePmConditionalRules(audit);
      expect(errors, isEmpty);
    });

    test('valid when gasping is present and subtype provided', () {
      final audit = _buildPmAudit({
        'pm_gaspingPresent': 1,
        'pm_gaspingType': 'Abdominal',
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors, isEmpty);
    });

    test('returns error when gasping is present but subtype missing', () {
      final audit = _buildPmAudit({'pm_gaspingPresent': 1});

      final errors = validatePmConditionalRules(audit);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Gasping')), true);
    });

    test('returns error when gasping is present but subtype empty', () {
      final audit = _buildPmAudit({
        'pm_gaspingPresent': 1,
        'pm_gaspingType': '',
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Gasping')), true);
    });

    test('no error when gasping is not present', () {
      final audit = _buildPmAudit({'pm_gaspingPresent': 0});

      final errors = validatePmConditionalRules(audit);
      expect(errors.any((e) => e.contains('Gasping')), false);
    });

    test('valid when other deformity count has description', () {
      final audit = _buildPmAudit({
        'pm_otherDeformityCount': 3,
        'pm_otherDeformityText': 'Missing wing feather',
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors, isEmpty);
    });

    test('returns error when other deformity count > 0 but no description', () {
      final audit = _buildPmAudit({'pm_otherDeformityCount': 3});

      final errors = validatePmConditionalRules(audit);
      expect(errors, isNotEmpty);
      expect(errors.any((e) => e.contains('Other deformity')), true);
    });

    test('no error when other deformity count is 0 and description null', () {
      final audit = _buildPmAudit({'pm_otherDeformityCount': 0});

      final errors = validatePmConditionalRules(audit);
      expect(errors.any((e) => e.contains('Other deformity')), false);
    });

    test('compound: gasping missing subtype AND lesion missing severity', () {
      final audit = _buildPmAudit({
        'pm_gaspingPresent': 1,
        'pm_pericarditisCount': 5,
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors.length, 2);
      expect(errors.any((e) => e.contains('Gasping')), true);
      expect(errors.any((e) => e.contains('Pericarditis')), true);
    });
  });

  group('PM Necropsy round-trip serialization', () {
    test('all PM fields serialize and deserialize correctly', () {
      final audit = _buildPmAudit({
        'pm_sampleSize': 50,
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
        'pm_suspectedCauseAuto': 'Omphalitis + Unabsorbed Yolk',
        'pm_suspectedCauseManual': 'Poor hatchery sanitation',
        'pm_photosJson': '["pm_photo1.jpg","pm_photo2.jpg"]',
      });

      final map = audit.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.pmSampleSize, 50);
      expect(restored.pmCollectionPoint, 'Hatchery');
      expect(restored.pmOmphalitisCount, 3);
      expect(restored.pmOmphalitisSeverity, 'Moderate');
      expect(restored.pmGaseousCecaCount, 1);
      expect(restored.pmGaseousCecaSeverity, 'Mild');
      expect(restored.pmUnabsorbedYolkCount, 5);
      expect(restored.pmUnabsorbedYolkSeverity, 'Moderate');
      expect(restored.pmPericarditisCount, 2);
      expect(restored.pmPericarditisSeverity, 'Severe');
      expect(restored.pmAirsacAcuteCount, 1);
      expect(restored.pmAirsacAcuteSeverity, 'Mild');
      expect(restored.pmGaspingPresent, true);
      expect(restored.pmGaspingType, 'Abdominal');
      expect(restored.pmExposedBrainCount, 1);
      expect(restored.pmCrossedBeakCount, 2);
      expect(restored.pmAbsentEyeOneCount, 1);
      expect(restored.pmHydrocephalyCount, 1);
      expect(restored.pmCurledToesCount, 1);
      expect(restored.pmOtherDeformityCount, 3);
      expect(restored.pmOtherDeformityText, 'Missing wing feather');
      expect(restored.pmSuspectedCauseAuto, 'Omphalitis + Unabsorbed Yolk');
      expect(restored.pmSuspectedCauseManual, 'Poor hatchery sanitation');
      expect(restored.pmPhotosJson, '["pm_photo1.jpg","pm_photo2.jpg"]');
    });

    test('pmGaspingPresent false serializes correctly', () {
      final audit = _buildPmAudit({'pm_gaspingPresent': 0});

      final map = audit.toMap();
      final restored = AuditModel.fromMap(map);

      expect(restored.pmGaspingPresent, false);
      expect(map['pm_gaspingPresent'], 0);
    });
  });
}
