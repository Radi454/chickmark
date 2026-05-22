import 'dart:convert';

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
      'Gizzard Erosions',
      audit.pmGizzardErosionsCount,
      audit.pmGizzardErosionsSeverity,
    ],
    [
      'Air Sac Caseations',
      audit.pmAirSacCaseationsCount,
      audit.pmAirSacCaseationsSeverity,
    ],
    [
      'Urolithiasis (Urate Deposits)',
      audit.toMap()['pm_urolithiasisCount'],
      audit.toMap()['pm_urolithiasisSeverity'],
    ],
    ['Nephritis', audit.pmNephritisCount, audit.pmNephritisSeverity],
    [
      'General Septicemia',
      audit.pmGeneralSepticemiaCount,
      audit.pmGeneralSepticemiaSeverity,
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

  final otherLesions = _decodeOtherLesions(audit.pmOtherLesionsJson);
  for (final lesion in otherLesions) {
    final name = (lesion['name'] as String? ?? '').trim();
    final count = _parseCount(lesion['count']);
    final severity = (lesion['severity'] as String? ?? '').trim();
    if ((count ?? 0) > 0) {
      if (name.isEmpty) {
        errors.add('Other lesion name is required when count > 0');
      }
      if (severity.isEmpty) {
        final label = name.isEmpty ? 'Other lesion' : name;
        errors.add('$label requires severity when count > 0');
      }
    }
  }

  return errors;
}

List<Map<String, dynamic>> _decodeOtherLesions(String? source) {
  if (source == null || source.trim().isEmpty) return const [];
  try {
    final decoded = jsonDecode(source);
    if (decoded is! List) return const [];
    return decoded
        .whereType<Map>()
        .map((item) => Map<String, dynamic>.from(item))
        .toList();
  } catch (_) {
    return const [];
  }
}

int? _parseCount(Object? value) {
  if (value == null) return null;
  if (value is int) return value;
  if (value is num) return value.round();
  return int.tryParse(value.toString());
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
    test('valid when no lesions are present', () {
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
        'pm_gizzardErosionsCount': 2,
        'pm_gizzardErosionsSeverity': 'Severe',
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
        'pm_gizzardErosionsCount': 2,
        'pm_urolithiasisCount': 1,
        'pm_airSacCaseationsCount': 1,
        'pm_airSacCaseationsSeverity': 'Mild',
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors.length, 3);
      expect(errors.any((e) => e.contains('Omphalitis')), true);
      expect(errors.any((e) => e.contains('Gizzard Erosions')), true);
      expect(errors.any((e) => e.contains('Urolithiasis')), true);
    });

    test('validates custom other lesion rows', () {
      final audit = _buildPmAudit({
        'pm_otherLesionsJson': jsonEncode([
          {'name': 'Retained shell', 'count': 2},
          {'name': '', 'count': 1, 'severity': 'Mild'},
        ]),
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors.any((e) => e.contains('Retained shell')), true);
      expect(errors.any((e) => e.contains('Other lesion name')), true);
    });

    test('allows custom other lesion rows with name count and severity', () {
      final audit = _buildPmAudit({
        'pm_otherLesionsJson': jsonEncode([
          {'name': 'Retained shell', 'count': 2, 'severity': 'Mild'},
        ]),
      });

      final errors = validatePmConditionalRules(audit);
      expect(errors, isEmpty);
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

    test('returns lesion error without removed PM sector rules', () {
      final audit = _buildPmAudit({'pm_nephritisCount': 5});

      final errors = validatePmConditionalRules(audit);
      expect(errors, hasLength(1));
      expect(errors.any((e) => e.contains('Nephritis')), true);
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
        'pm_gizzardErosionsCount': 5,
        'pm_gizzardErosionsSeverity': 'Moderate',
        'pm_perihepatitisCount': 0,
        'pm_pericarditisCount': 2,
        'pm_pericarditisSeverity': 'Severe',
        'pm_airSacCaseationsCount': 1,
        'pm_airSacCaseationsSeverity': 'Mild',
        'pm_urolithiasisCount': 2,
        'pm_urolithiasisSeverity': 'Moderate',
        'pm_airsacChronicCount': 0,
        'pm_pulmonaryGranulomaCount': 0,
        'pm_swollenJointsCount': 1,
        'pm_swollenJointsSeverity': 'Mild',
        'pm_stuntedOrgansCount': 0,
        'pm_nephritisCount': 2,
        'pm_nephritisSeverity': 'Moderate',
        'pm_generalSepticemiaCount': 4,
        'pm_generalSepticemiaSeverity': 'Severe',
        'pm_suspectedCauseAuto': 'Omphalitis + Gizzard Erosions',
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
      expect(restored.pmGizzardErosionsCount, 5);
      expect(restored.pmGizzardErosionsSeverity, 'Moderate');
      expect(restored.pmPericarditisCount, 2);
      expect(restored.pmPericarditisSeverity, 'Severe');
      expect(restored.pmAirSacCaseationsCount, 1);
      expect(restored.pmAirSacCaseationsSeverity, 'Mild');
      expect(restored.toMap()['pm_urolithiasisCount'], 2);
      expect(restored.toMap()['pm_urolithiasisSeverity'], 'Moderate');
      expect(restored.pmNephritisCount, 2);
      expect(restored.pmNephritisSeverity, 'Moderate');
      expect(restored.pmGeneralSepticemiaCount, 4);
      expect(restored.pmGeneralSepticemiaSeverity, 'Severe');
      expect(restored.pmSuspectedCauseAuto, 'Omphalitis + Gizzard Erosions');
      expect(restored.pmSuspectedCauseManual, 'Poor hatchery sanitation');
      expect(restored.pmPhotosJson, '["pm_photo1.jpg","pm_photo2.jpg"]');
    });
  });
}
