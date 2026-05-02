import 'dart:convert';

import 'package:hatchaudit/data/models/audit_model.dart';

/// Shared constants and fixture builders for upcoming audit-session tests.
///
/// These helpers intentionally work with the current codebase state:
/// - session-level metadata is represented as plain maps until a dedicated
///   `AuditSessionModel` exists in the app code.
/// - station audits use the existing `AuditModel` constructor only.
class SessionTestFixtures {
  SessionTestFixtures._();

  static const String testCustomerId = 'test-customer-1';
  static const String testHatcheryId = 'test-hatchery-1';
  static const String testFlockId = 'test-flock-1';
  static const String testSessionId = 'test-session-1';
  static const String testBreed = 'Ross 308';
  static const String testCreatedBy = 'test-auditor';

  static final DateTime testVisitDate = DateTime(2026, 4, 24, 8);
  static final DateTime testCreatedAt = DateTime(2026, 4, 24, 7, 55);
  static final DateTime testUpdatedAt = DateTime(2026, 4, 24, 8);

  static const String stationEggStorage = 'egg';
  static const String stationChickQuality = 'chicks';
  static const String stationHatchAnalysis = 'hatch_analysis_egg_breakouts';
  static const String stationSetter = 'setters';
  static const String stationHatcher = 'hatchers';

  static const List<String> allStationKeys = [
    stationEggStorage,
    stationChickQuality,
    stationHatchAnalysis,
    stationSetter,
    stationHatcher,
  ];
}

/// Session metadata fixture represented as the future `audit_sessions` row shape.
Map<String, dynamic> makeAuditSessionRow({
  String id = SessionTestFixtures.testSessionId,
  String customerId = SessionTestFixtures.testCustomerId,
  String hatcheryId = SessionTestFixtures.testHatcheryId,
  String flockId = SessionTestFixtures.testFlockId,
  DateTime? date,
  String breed = SessionTestFixtures.testBreed,
  int flockAgeWeeks = 42,
  String status = 'in_progress',
  List<String>? selectedStationKeys,
  List<String>? stationsCompleted,
  String? findingsJson,
  String? scorecardJson,
  String? notes,
  String createdBy = SessionTestFixtures.testCreatedBy,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? completedAt,
}) {
  final visitDate = date ?? SessionTestFixtures.testVisitDate;
  return {
    'id': id,
    'customerId': customerId,
    'flockId': flockId,
    'hatcheryId': hatcheryId,
    'date': visitDate.toIso8601String(),
    'breed': breed,
    'flockAgeWeeks': flockAgeWeeks,
    'status': status,
    'selectedStationKeys': selectedStationKeys == null
        ? null
        : jsonEncode(selectedStationKeys),
    'stationsCompleted': stationsCompleted == null
        ? null
        : jsonEncode(stationsCompleted),
    'findingsJson': findingsJson,
    'scorecardJson': scorecardJson,
    'notes': notes,
    'createdBy': createdBy,
    'createdAt': (createdAt ?? SessionTestFixtures.testCreatedAt)
        .toIso8601String(),
    'updatedAt': (updatedAt ?? SessionTestFixtures.testUpdatedAt)
        .toIso8601String(),
    'completedAt': completedAt?.toIso8601String(),
  };
}

AuditModel makeStationAudit({
  required String id,
  required String auditType,
  String customerId = SessionTestFixtures.testCustomerId,
  String flockId = SessionTestFixtures.testFlockId,
  DateTime? date,
  int hatchNumber = 1,
  String status = 'active',
  String createdBy = SessionTestFixtures.testCreatedBy,
  DateTime? createdAt,
  DateTime? updatedAt,
  String? setterId,
  String? hatcherId,
  String? notes,
  String? sampleMode,
  String? compareGroupKey,
  bool? esGoveeConnected,
  double? esGoveeTemp,
  double? esGoveeHumidity,
  double? esCo2,
  double? esShellTemp,
  int? esTurningTimes,
  String? esUvTrays,
  int? esEggStorageDays,
  int? esEggSampleSize,
  double? esEggAvgWeight,
  int? pasgarSampleSize,
  int? pasgarReflexes,
  int? pasgarBeak,
  int? pasgarNavel,
  int? pasgarBelly,
  int? pasgarLeg,
  int? pasgarFeatherDev,
  double? pasgarFinalScore,
  int? chickSampleSize,
  double? chickAvgWeight,
  double? chickUniformityPct,
  double? chickCvPct,
  int? cvtSampleSize,
  double? cvtTopTemp,
  double? cvtMiddleTemp,
  double? cvtBottomTemp,
  double? cvtAvg,
  double? cvtCvPct,
  int? haStorageDays,
  int? haTotalEggsSet,
  int? haHatched,
  int? haCulled,
  int? haDead,
  double? haHatchability,
  double? haFertility,
  double? haHof,
  String? ebTrayBreakoutJson,
  String? soBreed,
  String? soSetterId,
  int? soIncubationAge,
  bool? soGoveeConnected,
  double? soGoveeTemp,
  double? soGoveeHumidity,
  double? soCo2,
  double? soEstAvg,
  double? soEstCv,
  String? hoBreed,
  String? hoHatcherId,
  int? hoIncubationAge,
  bool? hoGoveeConnected,
  double? hoGoveeTemp,
  double? hoGoveeHumidity,
  double? hoCo2,
  double? hoCvtAvg,
  double? hoCvtCv,
  bool? hoChickPanting,
}) {
  return AuditModel(
    id: id,
    auditType: auditType,
    customerId: customerId,
    flockId: flockId,
    setterId: setterId,
    hatcherId: hatcherId,
    date: date ?? SessionTestFixtures.testVisitDate,
    hatchNumber: hatchNumber,
    status: status,
    createdBy: createdBy,
    createdAt: createdAt ?? SessionTestFixtures.testCreatedAt,
    updatedAt: updatedAt ?? SessionTestFixtures.testUpdatedAt,
    notes: notes,
    sampleMode: sampleMode,
    compareGroupKey: compareGroupKey,
    esGoveeConnected: esGoveeConnected,
    esGoveeTemp: esGoveeTemp,
    esGoveeHumidity: esGoveeHumidity,
    esCo2: esCo2,
    esShellTemp: esShellTemp,
    esTurningTimes: esTurningTimes,
    esUvTrays: esUvTrays,
    esEggStorageDays: esEggStorageDays,
    esEggSampleSize: esEggSampleSize,
    esEggAvgWeight: esEggAvgWeight,
    pasgarSampleSize: pasgarSampleSize,
    pasgarReflexes: pasgarReflexes,
    pasgarBeak: pasgarBeak,
    pasgarNavel: pasgarNavel,
    pasgarBelly: pasgarBelly,
    pasgarLeg: pasgarLeg,
    pasgarFeatherDev: pasgarFeatherDev,
    pasgarFinalScore: pasgarFinalScore,
    chickSampleSize: chickSampleSize,
    chickAvgWeight: chickAvgWeight,
    chickUniformityPct: chickUniformityPct,
    chickCvPct: chickCvPct,
    cvtSampleSize: cvtSampleSize,
    cvtTopTemp: cvtTopTemp,
    cvtMiddleTemp: cvtMiddleTemp,
    cvtBottomTemp: cvtBottomTemp,
    cvtAvg: cvtAvg,
    cvtCvPct: cvtCvPct,
    haStorageDays: haStorageDays,
    haTotalEggsSet: haTotalEggsSet,
    haHatched: haHatched,
    haCulled: haCulled,
    haDead: haDead,
    haHatchability: haHatchability,
    haFertility: haFertility,
    haHof: haHof,
    ebTrayBreakoutJson: ebTrayBreakoutJson,
    soBreed: soBreed,
    soSetterId: soSetterId,
    soIncubationAge: soIncubationAge,
    soGoveeConnected: soGoveeConnected,
    soGoveeTemp: soGoveeTemp,
    soGoveeHumidity: soGoveeHumidity,
    soCo2: soCo2,
    soEstAvg: soEstAvg,
    soEstCv: soEstCv,
    hoBreed: hoBreed,
    hoHatcherId: hoHatcherId,
    hoIncubationAge: hoIncubationAge,
    hoGoveeConnected: hoGoveeConnected,
    hoGoveeTemp: hoGoveeTemp,
    hoGoveeHumidity: hoGoveeHumidity,
    hoCo2: hoCo2,
    hoCvtAvg: hoCvtAvg,
    hoCvtCv: hoCvtCv,
    hoChickPanting: hoChickPanting,
  );
}

AuditModel makeEggStorageAudit({String id = 'audit-egg-storage-1'}) =>
    makeStationAudit(
      id: id,
      auditType: 'Egg',
      esGoveeConnected: true,
      esGoveeTemp: 72.5,
      esGoveeHumidity: 65,
      esCo2: 450,
      esShellTemp: 70.1,
      esTurningTimes: 4,
      esUvTrays: '3',
      esEggStorageDays: 5,
      esEggSampleSize: 30,
      esEggAvgWeight: 62.5,
    );

AuditModel makeChickQualityAudit({String id = 'audit-chick-quality-1'}) =>
    makeStationAudit(
      id: id,
      auditType: 'Chicks',
      pasgarSampleSize: 40,
      pasgarReflexes: 2,
      pasgarBeak: 1,
      pasgarNavel: 0,
      pasgarBelly: 1,
      pasgarLeg: 1,
      pasgarFeatherDev: 2,
      pasgarFinalScore: 9.5,
      chickSampleSize: 50,
      chickAvgWeight: 42.5,
      chickUniformityPct: 92.0,
      chickCvPct: 4.2,
      cvtSampleSize: 3,
      cvtTopTemp: 104.2,
      cvtMiddleTemp: 104.0,
      cvtBottomTemp: 103.8,
      cvtAvg: 104.0,
      cvtCvPct: 0.5,
    );

AuditModel makeHatchAnalysisAudit({
  String id = 'audit-hatch-analysis-1',
  int hatchNumber = 1,
}) => makeStationAudit(
  id: id,
  auditType: 'Hatch Analysis & Egg Breakouts',
  hatchNumber: hatchNumber,
  haStorageDays: 7,
  haTotalEggsSet: 10000,
  haHatched: 8900,
  haCulled: 80,
  haDead: 100,
  haHatchability: 89.0,
  haFertility: 94.0,
  haHof: 94.7,
);

AuditModel makeSetterAudit({String id = 'audit-setter-1'}) => makeStationAudit(
  id: id,
  auditType: 'Setters',
  setterId: 'setter-1',
  soSetterId: 'setter-1',
  soBreed: SessionTestFixtures.testBreed,
  soIncubationAge: 10,
  soGoveeConnected: true,
  soGoveeTemp: 100.0,
  soGoveeHumidity: 55.0,
  soCo2: 3800.0,
  soEstAvg: 99.7,
  soEstCv: 0.3,
);

AuditModel makeHatcherAudit({String id = 'audit-hatcher-1'}) =>
    makeStationAudit(
      id: id,
      auditType: 'Hatchers',
      hatcherId: 'hatcher-1',
      hoHatcherId: 'hatcher-1',
      hoBreed: SessionTestFixtures.testBreed,
      hoIncubationAge: 18,
      hoGoveeConnected: true,
      hoGoveeTemp: 99.2,
      hoGoveeHumidity: 65.0,
      hoCo2: 4200.0,
      hoCvtAvg: 104.1,
      hoCvtCv: 0.6,
      hoChickPanting: false,
    );

AuditModel makeHistoricalAudit({
  String id = 'audit-historical-1',
  required String auditType,
  String customerId = SessionTestFixtures.testCustomerId,
  String flockId = SessionTestFixtures.testFlockId,
  DateTime? date,
}) {
  final oldDate = DateTime(2026, 3, 15, 9);
  return AuditModel(
    id: id,
    auditType: auditType,
    customerId: customerId,
    flockId: flockId,
    date: date ?? oldDate,
    status: 'completed',
    createdBy: SessionTestFixtures.testCreatedBy,
    createdAt: oldDate,
    updatedAt: oldDate,
  );
}

List<AuditModel> makeCompleteVisitStations() {
  return [
    makeEggStorageAudit(id: 'audit-es-1'),
    makeChickQualityAudit(id: 'audit-cq-1'),
    makeHatchAnalysisAudit(id: 'audit-ha-1'),
    makeSetterAudit(id: 'audit-so-1'),
    makeHatcherAudit(id: 'audit-ho-1'),
  ];
}

List<AuditModel> makePartialVisitStations() {
  return [
    makeEggStorageAudit(id: 'audit-es-partial-1'),
    makeChickQualityAudit(id: 'audit-cq-partial-1'),
  ];
}
