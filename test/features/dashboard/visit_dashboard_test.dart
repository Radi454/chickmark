import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/utils/scorecard_formatter.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/visit_session_summary.dart';

void main() {
  group('VisitSessionSummary aggregation', () {
    test('aggregates empty session with no audits or temps', () {
      final session = _makeSession(stationsCompleted: []);
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
        temperatureSummaries: [],
      );

      expect(summary.session.id, 's1');
      expect(summary.stationAudits, isEmpty);
      expect(summary.temperatureSummaries, isEmpty);
      expect(summary.scorecards.length, supportedStationKeys.length);
      expect(summary.findingsSummary, isNull);
      expect(summary.pmScoreSummary, isNull);
      expect(summary.hatchBudgetSummary, isNull);
      expect(summary.isCompleted, false);
      expect(summary.completionFraction, 0.0);
    });

    test('aggregates completed session with all stations', () {
      final session = _makeSession(
        status: 'completed',
        stationsCompleted: supportedStationKeys,
      );
      final audits = [
        _makeAudit(auditType: 'Egg Storage'),
        _makeAudit(auditType: 'Chick Quality'),
        _makeAudit(auditType: 'Hatch Analysis'),
        _makeAudit(auditType: 'Setter Optimizing'),
        _makeAudit(auditType: 'Hatcher Optimizing'),
      ];
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: audits,
        temperatureSummaries: [],
      );

      expect(summary.isCompleted, true);
      expect(summary.completedStationCount, 5);
      expect(summary.completionFraction, 1.0);
      expect(
        summary.scorecards.every((sc) => sc.status == 'green'),
        isTrue,
        reason: 'All stations completed with no critical data => green',
      );
    });

    test('uses selected station subset for progress and scorecards', () {
      final session = _makeSession(
        selectedStationKeys: const ['egg_storage', 'hatch_analysis'],
        stationsCompleted: const ['egg_storage'],
      );
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [_makeAudit(auditType: 'Egg Storage')],
        temperatureSummaries: [],
      );

      expect(summary.selectedStationCount, 2);
      expect(summary.completedStationCount, 1);
      expect(summary.completionFraction, 0.5);
      expect(summary.scorecards.map((scorecard) => scorecard.stationKey), [
        'egg_storage',
        'hatch_analysis',
      ]);
    });

    test('filters persisted scorecards to selected stations', () {
      final session = _makeSession(
        selectedStationKeys: const ['hatch_analysis'],
        scorecardJson:
            '[{"stationKey":"egg_storage","stationLabel":"Egg Storage","status":"green"},{"stationKey":"hatch_analysis","stationLabel":"Hatch Analysis","status":"amber"}]',
      );
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
        temperatureSummaries: [],
      );

      expect(summary.scorecards.length, 1);
      expect(summary.scorecards.first.stationKey, 'hatch_analysis');
      expect(summary.scorecards.first.status, 'amber');
    });

    test('scorecard falls back to persisted JSON when available', () {
      final session = _makeSession(
        scorecardJson:
            '[{"stationKey":"egg_storage","stationLabel":"Egg Storage","status":"amber","detail":"Review"}]',
      );
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
        temperatureSummaries: [],
      );

      final eggSc = summary.scorecards.firstWhere(
        (sc) => sc.stationKey == 'egg_storage',
      );
      expect(eggSc.stationLabel, 'Egg');
      expect(eggSc.status, 'amber');
      expect(eggSc.detail, 'Review');
    });

    test('findings JSON parses into summary counts', () {
      final findingsJson =
          '[{"scope":"session","severity":"green","title":"OK"},{"scope":"session","severity":"red","title":"Hot"}]';
      final session = _makeSession(findingsJson: findingsJson);
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
        temperatureSummaries: [],
      );

      expect(summary.findingsSummary, isNotNull);
      expect(summary.findingsSummary!.greenCount, 1);
      expect(summary.findingsSummary!.redCount, 1);
      expect(summary.findingsSummary!.amberCount, 0);
      expect(summary.findingsSummary!.findings.length, 2);
    });

    test('findings summary is null when JSON is empty', () {
      final session = _makeSession(findingsJson: null);
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
        temperatureSummaries: [],
      );
      expect(summary.findingsSummary, isNull);
    });

    test('PM score summary aggregates lesions and deformities', () {
      final audit = _makeAudit(
        auditType: 'Chick Quality',
        pmOmphalitisCount: 2,
        pmGaseousCecaCount: 1,
        pmExposedBrainCount: 1,
        pmCrossedBeakCount: 1,
        pmGaspingPresent: true,
        pmGaspingType: 'Asphyxia',
      );
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [audit],
        temperatureSummaries: [],
      );

      expect(summary.pmScoreSummary, isNotNull);
      expect(summary.pmScoreSummary!.totalLesions, 3);
      expect(summary.pmScoreSummary!.totalDeformities, 2);
      expect(summary.pmScoreSummary!.gaspingPresent, true);
      expect(summary.pmScoreSummary!.gaspingType, 'Asphyxia');
      expect(summary.pmScoreSummary!.overallSeverity, 'amber');
    });

    test('PM severity is green when no lesions, deformities, or gasping', () {
      final audit = _makeAudit(auditType: 'Chick Quality');
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [audit],
        temperatureSummaries: [],
      );
      expect(summary.pmScoreSummary!.overallSeverity, 'green');
    });

    test('PM severity is red when many lesions or deformities', () {
      final audit = _makeAudit(
        auditType: 'Chick Quality',
        pmOmphalitisCount: 6,
        pmExposedBrainCount: 4,
      );
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [audit],
        temperatureSummaries: [],
      );
      expect(summary.pmScoreSummary!.overallSeverity, 'red');
    });

    test('hatch budget summary reads from hatch analysis audit', () {
      final audit = _makeAudit(
        auditType: 'Hatch Analysis',
        haTotalEggsSet: 10000,
        haHatched: 8500,
        haCulled: 100,
        haDead: 50,
        haHatchability: 85.0,
        haFertility: 94.0,
        haHof: 90.4,
      );
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [audit],
        temperatureSummaries: [],
      );

      expect(summary.hatchBudgetSummary, isNotNull);
      expect(summary.hatchBudgetSummary!.totalEggsSet, 10000);
      expect(summary.hatchBudgetSummary!.healthyHatched, 8500);
      expect(summary.hatchBudgetSummary!.hatchabilityPct, 85.0);
      expect(summary.hatchBudgetSummary!.fertilityPct, 94.0);
      expect(summary.hatchBudgetSummary!.hofPct, 90.4);
    });

    test('temperature summaries map correctly', () {
      final temp = TemperatureSessionModel(
        id: 't1',
        customerId: 'c1',
        hatcheryId: 'h1',
        startedAt: DateTime.now(),
        activePlace: TemperaturePlace.eggStorageRoom,
        status: 'completed',
        tempAvg: 68.5,
        tempMin: 66.0,
        tempMax: 71.0,
        alertCount: 0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [],
        temperatureSummaries: [temp],
      );

      expect(summary.temperatureSummaries.length, 1);
      final chip = TemperatureSummary.fromSession(temp);
      expect(chip.placeLabel, 'Egg storage room');
      expect(chip.avgTempF, 68.5);
      expect(chip.status, 'green');
    });

    test('temperature summary is red when alerts exist', () {
      final temp = TemperatureSessionModel(
        id: 't1',
        customerId: 'c1',
        hatcheryId: 'h1',
        startedAt: DateTime.now(),
        activePlace: TemperaturePlace.incubatorRoom,
        status: 'completed',
        tempAvg: 99.0,
        alertCount: 2,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      );
      final chip = TemperatureSummary.fromSession(temp);
      expect(chip.status, 'red');
    });
  });

  group('ScorecardFormatter', () {
    test('statusColor returns correct colors', () {
      expect(ScorecardFormatter.statusColor('green'), AppColors.statusGood);
      expect(ScorecardFormatter.statusColor('amber'), AppColors.statusWarning);
      expect(ScorecardFormatter.statusColor('red'), AppColors.statusError);
      expect(
        ScorecardFormatter.statusColor('unknown'),
        AppColors.statusNeutralText,
      );
    });

    test('statusLabel returns readable labels', () {
      expect(ScorecardFormatter.statusLabel('green'), 'Good');
      expect(ScorecardFormatter.statusLabel('amber'), 'Review');
      expect(ScorecardFormatter.statusLabel('red'), 'Alert');
      expect(ScorecardFormatter.statusLabel('unknown'), 'Pending');
    });

    test('benchmarkColor maps states to colors', () {
      expect(ScorecardFormatter.benchmarkColor('OK'), AppColors.statusGood);
      expect(
        ScorecardFormatter.benchmarkColor('Medium'),
        AppColors.statusWarning,
      );
      expect(ScorecardFormatter.benchmarkColor('High'), AppColors.statusError);
    });

    test('benchmarkLabel uses new wording', () {
      expect(ScorecardFormatter.benchmarkLabel('OK'), 'On target');
      expect(ScorecardFormatter.benchmarkLabel('Medium'), 'Above target');
      expect(ScorecardFormatter.benchmarkLabel('High'), 'Well above target');
    });

    test('completionLabel formats fraction', () {
      expect(ScorecardFormatter.completionLabel(3, 5), '3 / 5 stations');
      expect(ScorecardFormatter.completionLabel(0, 5), '0 / 5 stations');
    });
  });

  group('StationScorecard heuristic derivation', () {
    test('unknown when station not completed', () {
      final sc = StationScorecard.derive(
        stationKey: 'egg_storage',
        isCompleted: false,
        audit: _makeAudit(auditType: 'Egg Storage'),
      );
      expect(sc.status, 'unknown');
      expect(sc.detail, 'Not completed');
    });

    test('red for egg storage shell temp > 21C', () {
      final sc = StationScorecard.derive(
        stationKey: 'egg_storage',
        isCompleted: true,
        audit: _makeAudit(auditType: 'Egg Storage', esShellTemp: 22.5),
      );
      expect(sc.status, 'red');
    });

    test('amber for setter EST outside optimal range', () {
      final sc = StationScorecard.derive(
        stationKey: 'setter_optimizing',
        isCompleted: true,
        audit: _makeAudit(auditType: 'Setter Optimizing', soEstAvg: 99.5),
      );
      expect(sc.status, 'amber');
    });

    test('green when no critical alerts', () {
      final sc = StationScorecard.derive(
        stationKey: 'egg_storage',
        isCompleted: true,
        audit: _makeAudit(auditType: 'Egg Storage', esShellTemp: 20.0),
      );
      expect(sc.status, 'green');
    });
  });
}

// ─── test helpers ───────────────────────────────────────────────────────────

AuditSessionModel _makeSession({
  String id = 's1',
  String status = 'in_progress',
  List<String> selectedStationKeys = supportedStationKeys,
  List<String> stationsCompleted = const [],
  String? findingsJson,
  String? scorecardJson,
}) {
  return AuditSessionModel(
    id: id,
    customerId: 'c1',
    flockId: 'f1',
    hatcheryId: 'h1',
    date: DateTime(2026, 4, 20),
    status: status,
    selectedStationKeys: selectedStationKeys,
    stationsCompleted: stationsCompleted,
    findingsJson: findingsJson,
    scorecardJson: scorecardJson,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

AuditModel _makeAudit({
  required String auditType,
  double? esShellTemp,
  double? soEstAvg,
  double? hoCvtAvg,
  int? pmOmphalitisCount,
  int? pmGaseousCecaCount,
  int? pmExposedBrainCount,
  int? pmCrossedBeakCount,
  bool? pmGaspingPresent,
  String? pmGaspingType,
  int? haTotalEggsSet,
  int? haHatched,
  int? haCulled,
  int? haDead,
  double? haHatchability,
  double? haFertility,
  double? haHof,
}) {
  return AuditModel(
    id: 'a1',
    auditType: auditType,
    customerId: 'c1',
    flockId: 'f1',
    date: DateTime.now(),
    status: 'active',
    createdBy: 'u1',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    esShellTemp: esShellTemp,
    soEstAvg: soEstAvg,
    hoCvtAvg: hoCvtAvg,
    pmOmphalitisCount: pmOmphalitisCount,
    pmGaseousCecaCount: pmGaseousCecaCount,
    pmExposedBrainCount: pmExposedBrainCount,
    pmCrossedBeakCount: pmCrossedBeakCount,
    pmGaspingPresent: pmGaspingPresent,
    pmGaspingType: pmGaspingType,
    haTotalEggsSet: haTotalEggsSet,
    haHatched: haHatched,
    haCulled: haCulled,
    haDead: haDead,
    haHatchability: haHatchability,
    haFertility: haFertility,
    haHof: haHof,
  );
}
