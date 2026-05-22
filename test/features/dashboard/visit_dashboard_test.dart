import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/utils/scorecard_formatter.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/govee_capture_model.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/data/repositories/govee_capture_repository.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/models/visit_session_summary.dart';
import 'package:mocktail/mocktail.dart';

class _MockGoveeCaptureRepository extends Mock
    implements GoveeCaptureRepository {}

void main() {
  group('DashboardProvider Govee captures', () {
    late _MockGoveeCaptureRepository mockGoveeRepo;
    late DashboardProvider provider;

    setUp(() {
      mockGoveeRepo = _MockGoveeCaptureRepository();
      provider = DashboardProvider(goveeCaptureRepository: mockGoveeRepo);
    });

    test('loads Govee captures by customer hatchery and visit date', () async {
      final capture = _makeGoveeCapture();
      final readings = _makeGoveeReadings();

      when(
        () => mockGoveeRepo.getCapturesForDashboard(
          customerId: 'c1',
          hatcheryId: 'h1',
          captureDate: '2026-05-02',
        ),
      ).thenAnswer((_) async => [capture]);
      when(
        () => mockGoveeRepo.getReadingsForCapture('capture-1'),
      ).thenAnswer((_) async => readings);

      await provider.selectVisitSession(
        VisitSessionSummary.fromSession(
          session: _makeSession(date: DateTime(2026, 5, 2)),
          stationAudits: [],
        ),
      );

      expect(provider.goveeCaptures, hasLength(1));
      expect(provider.goveeCaptures.single.capture.id, 'capture-1');
      verify(
        () => mockGoveeRepo.getCapturesForDashboard(
          customerId: 'c1',
          hatcheryId: 'h1',
          captureDate: '2026-05-02',
        ),
      ).called(1);
      verifyNever(
        () => mockGoveeRepo.getCapturesForDashboard(
          customerId: any(named: 'customerId'),
          hatcheryId: any(named: 'hatcheryId'),
        ),
      );
    });
  });

  group('VisitSessionSummary aggregation', () {
    test('aggregates empty session with no audits', () {
      final session = _makeSession(stationsCompleted: []);
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
      );

      expect(summary.session.id, 's1');
      expect(summary.stationAudits, isEmpty);
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
        _makeAudit(auditType: 'Egg'),
        _makeAudit(auditType: 'Chicks'),
        _makeAudit(auditType: 'Hatch Analysis & Egg Breakouts'),
        _makeAudit(auditType: 'Setters'),
        _makeAudit(auditType: 'Hatchers'),
      ];
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: audits,
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
        selectedStationKeys: const ['egg', 'hatch_analysis_egg_breakouts'],
        stationsCompleted: const ['egg'],
      );
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [_makeAudit(auditType: 'Egg')],
      );

      expect(summary.selectedStationCount, 2);
      expect(summary.completedStationCount, 1);
      expect(summary.completionFraction, 0.5);
      expect(summary.scorecards.map((scorecard) => scorecard.stationKey), [
        'egg',
        'hatch_analysis_egg_breakouts',
      ]);
    });

    test('filters persisted scorecards to selected stations', () {
      final session = _makeSession(
        selectedStationKeys: const ['hatch_analysis_egg_breakouts'],
        scorecardJson:
            '[{"stationKey":"egg","stationLabel":"Egg","status":"green"},{"stationKey":"hatch_analysis_egg_breakouts","stationLabel":"Hatch Analysis & Egg Breakouts","status":"amber"}]',
      );
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
      );

      expect(summary.scorecards.length, 1);
      expect(
        summary.scorecards.first.stationKey,
        'hatch_analysis_egg_breakouts',
      );
      expect(summary.scorecards.first.status, 'amber');
    });

    test('scorecard falls back to persisted JSON when available', () {
      final session = _makeSession(
        scorecardJson:
            '[{"stationKey":"egg","stationLabel":"Egg","status":"amber","detail":"Review"}]',
      );
      final summary = VisitSessionSummary.fromSession(
        session: session,
        stationAudits: [],
      );

      final eggSc = summary.scorecards.firstWhere(
        (sc) => sc.stationKey == 'egg',
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
      );
      expect(summary.findingsSummary, isNull);
    });

    test('PM score summary aggregates lesions', () {
      final audit = _makeAudit(
        auditType: 'Chicks',
        pmOmphalitisCount: 2,
        pmGaseousCecaCount: 1,
      );
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [audit],
      );

      expect(summary.pmScoreSummary, isNotNull);
      expect(summary.pmScoreSummary!.totalLesions, 3);
      expect(summary.pmScoreSummary!.overallSeverity, 'amber');
    });

    test('PM severity is green when no lesions are present', () {
      final audit = _makeAudit(auditType: 'Chicks');
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [audit],
      );
      expect(summary.pmScoreSummary!.overallSeverity, 'green');
    });

    test('PM severity is red when many lesions are present', () {
      final audit = _makeAudit(auditType: 'Chicks', pmOmphalitisCount: 6);
      final summary = VisitSessionSummary.fromSession(
        session: _makeSession(),
        stationAudits: [audit],
      );
      expect(summary.pmScoreSummary!.overallSeverity, 'red');
    });

    test('hatch budget summary reads from hatch analysis audit', () {
      final audit = _makeAudit(
        auditType: 'Hatch Analysis & Egg Breakouts',
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
      );

      expect(summary.hatchBudgetSummary, isNotNull);
      expect(summary.hatchBudgetSummary!.totalEggsSet, 10000);
      expect(summary.hatchBudgetSummary!.healthyHatched, 8500);
      expect(summary.hatchBudgetSummary!.hatchabilityPct, 85.0);
      expect(summary.hatchBudgetSummary!.fertilityPct, 94.0);
      expect(summary.hatchBudgetSummary!.hofPct, 90.4);
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
        stationKey: 'egg',
        isCompleted: false,
        audit: _makeAudit(auditType: 'Egg'),
      );
      expect(sc.status, 'unknown');
      expect(sc.detail, 'Not completed');
    });

    test('red for egg storage shell temp > 21C', () {
      final sc = StationScorecard.derive(
        stationKey: 'egg',
        isCompleted: true,
        audit: _makeAudit(auditType: 'Egg', esShellTemp: 22.5),
      );
      expect(sc.status, 'red');
    });

    test('amber for setter EST outside optimal range', () {
      final sc = StationScorecard.derive(
        stationKey: 'setters',
        isCompleted: true,
        audit: _makeAudit(auditType: 'Setters', soEstAvg: 99.5),
      );
      expect(sc.status, 'amber');
    });

    test('green when no critical alerts', () {
      final sc = StationScorecard.derive(
        stationKey: 'egg',
        isCompleted: true,
        audit: _makeAudit(auditType: 'Egg', esShellTemp: 20.0),
      );
      expect(sc.status, 'green');
    });
  });
}

// ─── test helpers ───────────────────────────────────────────────────────────

AuditSessionModel _makeSession({
  String id = 's1',
  String status = 'in_progress',
  DateTime? date,
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
    date: date ?? DateTime(2026, 4, 20),
    status: status,
    selectedStationKeys: selectedStationKeys,
    stationsCompleted: stationsCompleted,
    findingsJson: findingsJson,
    scorecardJson: scorecardJson,
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
  );
}

GoveeDailyCaptureModel _makeGoveeCapture() {
  final now = DateTime(2026, 5, 2, 12);
  return GoveeDailyCaptureModel(
    id: 'capture-1',
    customerId: 'c1',
    hatcheryId: 'h1',
    place: TemperaturePlace.eggStorageRoom,
    machineId: null,
    captureDate: '2026-05-02',
    deviceId: 'device-1',
    deviceName: 'Govee H5051',
    status: 'completed',
    tempAvg: 72.5,
    tempMin: 71,
    tempMax: 74,
    rhAvg: 58,
    rhMin: 55,
    rhMax: 61,
    readingCount: 180,
    createdAt: now,
    updatedAt: now,
  );
}

List<GoveePlaceReadingModel> _makeGoveeReadings() {
  final startedAt = DateTime(2026, 5, 2, 12);
  return [
    for (var i = 0; i < 180; i++)
      GoveePlaceReadingModel(
        id: 'capture-1-reading-$i',
        captureId: 'capture-1',
        readingIndex: i,
        recordedAt: startedAt.add(Duration(seconds: i)),
        temperatureFahrenheit: 70 + (i / 100),
        humidity: 55 + (i / 100),
        createdAt: startedAt,
      ),
  ];
}

AuditModel _makeAudit({
  required String auditType,
  double? esShellTemp,
  double? soEstAvg,
  double? hoCvtAvg,
  int? pmOmphalitisCount,
  int? pmGaseousCecaCount,
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
    haTotalEggsSet: haTotalEggsSet,
    haHatched: haHatched,
    haCulled: haCulled,
    haDead: haDead,
    haHatchability: haHatchability,
    haFertility: haFertility,
    haHof: haHof,
  );
}
