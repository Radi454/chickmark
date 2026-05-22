import 'dart:convert';

import '../../../data/models/audit_model.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../core/utils/audit_type_labels.dart';

/// Aggregates one audit session with its station audits for dashboard and
/// customer-detail display.
class VisitSessionSummary {
  final AuditSessionModel session;
  final List<AuditModel> stationAudits;
  final List<StationScorecard> scorecards;
  final SessionFindingsSummary? findingsSummary;
  final PmScoreSummary? pmScoreSummary;
  final HatchBudgetSummary? hatchBudgetSummary;

  const VisitSessionSummary({
    required this.session,
    this.stationAudits = const [],
    this.scorecards = const [],
    this.findingsSummary,
    this.pmScoreSummary,
    this.hatchBudgetSummary,
  });

  bool get isCompleted => session.status == 'completed';

  int get completedStationCount => session.stationsCompleted.length;
  List<String> get selectedStationKeys => session.selectedStationKeys;
  int get selectedStationCount => selectedStationKeys.length;

  double get completionFraction {
    if (selectedStationCount == 0) return 0.0;
    return completedStationCount / selectedStationCount;
  }

  /// Builds a summary from raw data.  Safe to call with empty lists.
  factory VisitSessionSummary.fromSession({
    required AuditSessionModel session,
    required List<AuditModel> stationAudits,
  }) {
    final scorecards = _computeScorecards(session, stationAudits);
    final findings = _parseFindings(session.findingsJson);
    final pm = _computePmScore(stationAudits);
    final hatch = _computeHatchBudget(stationAudits);

    return VisitSessionSummary(
      session: session,
      stationAudits: stationAudits,
      scorecards: scorecards,
      findingsSummary: findings,
      pmScoreSummary: pm,
      hatchBudgetSummary: hatch,
    );
  }

  factory VisitSessionSummary.fromPanelRows({
    required AuditSessionModel session,
    required Map<String, List<Map<String, dynamic>>> panelRowsByTable,
  }) {
    final scorecards = _computePanelScorecards(session, panelRowsByTable);
    final findings = _parseFindings(session.findingsJson);
    final pm = PmScoreSummary.fromPanelRows(
      panelRowsByTable['chick_quality'] ?? const [],
    );
    final hatch = HatchBudgetSummary.fromPanelRows(
      panelRowsByTable['residue_breakout'] ?? const [],
    );

    return VisitSessionSummary(
      session: session,
      scorecards: scorecards,
      findingsSummary: findings,
      pmScoreSummary: pm,
      hatchBudgetSummary: hatch,
    );
  }

  static List<StationScorecard> _computeScorecards(
    AuditSessionModel session,
    List<AuditModel> audits,
  ) {
    // Prefer persisted scorecard JSON when available.
    final persisted = _parseScorecards(session.scorecardJson);
    final selected = session.selectedStationKeys;
    if (persisted.isNotEmpty) {
      return persisted
          .where((scorecard) => selected.contains(scorecard.stationKey))
          .toList();
    }

    // Fallback: derive from station completion and simple heuristics.
    final completed = session.stationsCompleted.toSet();
    return selected.map((key) {
      final audit = audits.firstWhere(
        (a) => _auditTypeToStationKey(a.auditType) == key,
        orElse: () => AuditModel(
          id: '',
          auditType: '',
          customerId: '',
          flockId: null,
          date: DateTime.now(),
          status: 'active',
          createdBy: '',
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
      );
      return StationScorecard.derive(
        stationKey: key,
        isCompleted: completed.contains(key),
        audit: audit,
      );
    }).toList();
  }

  static List<StationScorecard> _computePanelScorecards(
    AuditSessionModel session,
    Map<String, List<Map<String, dynamic>>> panelRowsByTable,
  ) {
    final persisted = _parseScorecards(session.scorecardJson);
    final selected = session.selectedStationKeys;
    if (persisted.isNotEmpty) {
      return persisted
          .where((scorecard) => selected.contains(scorecard.stationKey))
          .toList();
    }

    final completed = session.stationsCompleted.toSet();
    return selected.map((key) {
      final alert = completed.contains(key)
          ? StationScorecard._hasPanelCriticalAlert(key, panelRowsByTable)
          : null;
      return StationScorecard(
        stationKey: key,
        stationLabel: StationScorecard._stationLabel(key),
        status: completed.contains(key) ? alert ?? 'green' : 'unknown',
        detail: completed.contains(key)
            ? (alert == null ? 'No alerts' : 'Review required')
            : 'Not completed',
      );
    }).toList();
  }

  static List<StationScorecard> _parseScorecards(String? json) {
    if (json == null || json.isEmpty) return [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .map((e) => StationScorecard.fromMap(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  static SessionFindingsSummary? _parseFindings(String? json) {
    if (json == null || json.isEmpty) return null;
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        final findings = decoded
            .map((e) => SessionFinding.fromMap(e as Map<String, dynamic>))
            .toList();
        return SessionFindingsSummary.fromFindings(findings);
      }
    } catch (_) {}
    return null;
  }

  static PmScoreSummary? _computePmScore(List<AuditModel> audits) {
    final cq = audits.where((a) => a.auditType == 'Chicks').toList();
    if (cq.isEmpty) return null;
    // Use the most recent chick quality audit for PM data.
    final audit = cq.last;
    return PmScoreSummary.fromAudit(audit);
  }

  static HatchBudgetSummary? _computeHatchBudget(List<AuditModel> audits) {
    final ha = audits
        .where((a) => a.auditType == 'Hatch Analysis & Egg Breakouts')
        .toList();
    if (ha.isEmpty) return null;
    final audit = ha.last;
    return HatchBudgetSummary.fromAudit(audit);
  }

  static String _auditTypeToStationKey(String auditType) {
    switch (auditType) {
      case 'Egg':
        return 'egg';
      case 'Chicks':
        return 'chicks';
      case 'Hatch Analysis & Egg Breakouts':
        return 'hatch_analysis_egg_breakouts';
      case 'Setters':
        return 'setters';
      case 'Hatchers':
        return 'hatchers';
      default:
        return '';
    }
  }
}

/// A simple per-station scorecard that can be persisted or derived.
class StationScorecard {
  final String stationKey;
  final String stationLabel;
  final String status; // green, amber, red, unknown
  final String? detail;

  const StationScorecard({
    required this.stationKey,
    required this.stationLabel,
    this.status = 'unknown',
    this.detail,
  });

  factory StationScorecard.fromMap(Map<String, dynamic> map) {
    final stationKey = map['stationKey'] as String? ?? '';
    final storedLabel = map['stationLabel'] as String? ?? '';
    final normalizedLabel = _stationLabel(stationKey);
    return StationScorecard(
      stationKey: stationKey,
      stationLabel: normalizedLabel == stationKey && storedLabel.isNotEmpty
          ? storedLabel
          : normalizedLabel,
      status: map['status'] as String? ?? 'unknown',
      detail: map['detail'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'stationKey': stationKey,
      'stationLabel': stationLabel,
      'status': status,
      'detail': detail,
    };
  }

  factory StationScorecard.derive({
    required String stationKey,
    required bool isCompleted,
    required AuditModel audit,
  }) {
    final label = _stationLabel(stationKey);
    if (!isCompleted) {
      return StationScorecard(
        stationKey: stationKey,
        stationLabel: label,
        status: 'unknown',
        detail: 'Not completed',
      );
    }

    // Simple heuristic: look for critical values that would trigger red/amber.
    final alert = _hasCriticalAlert(stationKey, audit);
    return StationScorecard(
      stationKey: stationKey,
      stationLabel: label,
      status: alert ?? 'green',
      detail: alert == null ? 'No alerts' : 'Review required',
    );
  }

  static String _stationLabel(String key) {
    switch (key) {
      case 'egg':
        return AuditTypeLabels.eggStationLabel;
      case 'chicks':
        return 'Chicks';
      case 'hatch_analysis_egg_breakouts':
        return 'Hatch Analysis & Egg Breakouts';
      case 'setters':
        return 'Setters';
      case 'hatchers':
        return 'Hatchers';
      default:
        return key;
    }
  }

  static String? _hasCriticalAlert(String stationKey, AuditModel audit) {
    // Placeholder heuristic until the diagnostic engine ships.
    // Returns 'red' for clear critical thresholds, 'amber' for marginal,
    // null when clean.
    switch (stationKey) {
      case 'egg':
        if (audit.esShellTemp != null) {
          final t = audit.esShellTemp!;
          if (t > 21) return 'red';
          if (t < 19) return 'amber';
        }
        break;
      case 'chicks':
        if (audit.pasgarFinalScore != null && audit.pasgarFinalScore! < 7) {
          return 'amber';
        }
        if (audit.chickCvPct != null && audit.chickCvPct! > 8) {
          return 'red';
        }
        break;
      case 'hatch_analysis_egg_breakouts':
        if (audit.haHatchability != null && audit.haHatchability! < 75) {
          return 'red';
        }
        break;
      case 'setters':
        if (audit.soEstAvg != null) {
          final t = audit.soEstAvg!;
          if (t < 100 || t > 101) return 'amber';
        }
        break;
      case 'hatchers':
        if (audit.hoCvtAvg != null) {
          final t = audit.hoCvtAvg!;
          if (t < 103 || t > 105) return 'amber';
        }
        break;
    }
    return null;
  }

  static String? _hasPanelCriticalAlert(
    String stationKey,
    Map<String, List<Map<String, dynamic>>> rowsByPanel,
  ) {
    switch (stationKey) {
      case 'egg':
        final temp = _lastDouble(rowsByPanel['egg_storage'], 'shellTemp');
        if (temp != null) {
          if (temp > 21) return 'red';
          if (temp < 19) return 'amber';
        }
        break;
      case 'chicks':
        final pasgar = _lastDouble(
          rowsByPanel['chick_quality'],
          'pasgarFinalScore',
        );
        if (pasgar != null && pasgar < 7) return 'amber';
        final cv = _lastDouble(rowsByPanel['chick_weights'], 'cvPct');
        if (cv != null && cv > 8) return 'red';
        break;
      case 'hatch_analysis_egg_breakouts':
        final hatchability = _lastDouble(
          rowsByPanel['residue_breakout'],
          'hatchabilityPct',
        );
        if (hatchability != null && hatchability < 75) return 'red';
        break;
      case 'setters':
        final estAvg = _lastDouble(rowsByPanel['setter_optimizing'], 'estAvg');
        if (estAvg != null && (estAvg < 100 || estAvg > 101)) return 'amber';
        break;
      case 'hatchers':
        final cvtAvg = _lastDouble(rowsByPanel['hatcher_optimizing'], 'cvtAvg');
        if (cvtAvg != null && (cvtAvg < 103 || cvtAvg > 105)) return 'amber';
        break;
    }
    return null;
  }

  static double? _lastDouble(List<Map<String, dynamic>>? rows, String key) {
    if (rows == null || rows.isEmpty) return null;
    for (final row in rows.reversed) {
      final value = row[key];
      if (value is num) return value.toDouble();
      final parsed = double.tryParse(value?.toString() ?? '');
      if (parsed != null) return parsed;
    }
    return null;
  }
}

/// A session-level findings summary.
class SessionFindingsSummary {
  final List<SessionFinding> findings;
  final int greenCount;
  final int amberCount;
  final int redCount;

  const SessionFindingsSummary({
    this.findings = const [],
    this.greenCount = 0,
    this.amberCount = 0,
    this.redCount = 0,
  });

  bool get isEmpty => findings.isEmpty;

  factory SessionFindingsSummary.fromFindings(List<SessionFinding> findings) {
    int g = 0, a = 0, r = 0;
    for (final f in findings) {
      switch (f.severity) {
        case 'green':
          g++;
        case 'amber':
          a++;
        case 'red':
          r++;
      }
    }
    return SessionFindingsSummary(
      findings: findings,
      greenCount: g,
      amberCount: a,
      redCount: r,
    );
  }
}

/// One actionable finding within a session.
class SessionFinding {
  final String scope;
  final String? stationKey;
  final String severity;
  final String title;
  final String? detail;
  final String? recommendedAction;

  const SessionFinding({
    required this.scope,
    this.stationKey,
    required this.severity,
    required this.title,
    this.detail,
    this.recommendedAction,
  });

  factory SessionFinding.fromMap(Map<String, dynamic> map) {
    return SessionFinding(
      scope: map['scope'] as String? ?? 'session',
      stationKey: map['stationKey'] as String?,
      severity: map['severity'] as String? ?? 'unknown',
      title: map['title'] as String? ?? '',
      detail: map['detail'] as String?,
      recommendedAction: map['recommendedAction'] as String?,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'scope': scope,
      'stationKey': stationKey,
      'severity': severity,
      'title': title,
      'detail': detail,
      'recommendedAction': recommendedAction,
    };
  }
}

/// Aggregated PM necropsy score for display on the dashboard.
class PmScoreSummary {
  final int totalLesions;
  final String? overallSeverity;

  const PmScoreSummary({this.totalLesions = 0, this.overallSeverity});

  factory PmScoreSummary.fromAudit(AuditModel audit) {
    int lesions = 0;
    lesions += audit.pmOmphalitisCount ?? 0;
    lesions += audit.pmGaseousCecaCount ?? 0;
    lesions += audit.pmUnabsorbedYolkCount ?? 0;
    lesions += audit.pmPerihepatitisCount ?? 0;
    lesions += audit.pmPericarditisCount ?? 0;
    lesions += audit.pmAirsacAcuteCount ?? 0;
    lesions += audit.pmAirsacChronicCount ?? 0;
    lesions += audit.pmPulmonaryGranulomaCount ?? 0;
    lesions += audit.pmSwollenJointsCount ?? 0;
    lesions += audit.pmStuntedOrgansCount ?? 0;
    lesions += audit.pmPulmonaryHemorrhageCount ?? 0;
    lesions += audit.pmGizzardErosionsCount ?? 0;
    lesions += audit.pmAirSacCaseationsCount ?? 0;
    lesions += audit.pmUrolithiasisCount ?? 0;
    lesions += audit.pmNephritisCount ?? 0;
    lesions += audit.pmGeneralSepticemiaCount ?? 0;

    String? severity;
    if (lesions == 0) {
      severity = 'green';
    } else if (lesions > 5) {
      severity = 'red';
    } else {
      severity = 'amber';
    }

    return PmScoreSummary(totalLesions: lesions, overallSeverity: severity);
  }

  factory PmScoreSummary.fromPanelRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return nullPm;
    int sum(String key) =>
        rows.fold<int>(0, (total, row) => total + (_asInt(row[key]) ?? 0));

    final lesions =
        sum('pmOmphalitisCount') +
        sum('pmGaseousCecaCount') +
        sum('pmUnabsorbedYolkCount') +
        sum('pmPerihepatitisCount') +
        sum('pmPericarditisCount') +
        sum('pmAirsacAcuteCount') +
        sum('pmAirsacChronicCount') +
        sum('pmPulmonaryGranulomaCount') +
        sum('pmSwollenJointsCount') +
        sum('pmStuntedOrgansCount') +
        sum('pmPulmonaryHemorrhageCount') +
        sum('pmGizzardErosionsCount') +
        sum('pmAirSacCaseationsCount') +
        sum('pmUrolithiasisCount') +
        sum('pmNephritisCount') +
        sum('pmGeneralSepticemiaCount');
    final severity = lesions == 0
        ? 'green'
        : lesions > 5
        ? 'red'
        : 'amber';

    return PmScoreSummary(totalLesions: lesions, overallSeverity: severity);
  }

  static const nullPm = PmScoreSummary();
}

/// A simplified hatch budget summary for dashboard display.
class HatchBudgetSummary {
  final int totalEggsSet;
  final int healthyHatched;
  final int culled;
  final int deadAtHatch;
  final double? hatchabilityPct;
  final double? fertilityPct;
  final double? hofPct;

  const HatchBudgetSummary({
    this.totalEggsSet = 0,
    this.healthyHatched = 0,
    this.culled = 0,
    this.deadAtHatch = 0,
    this.hatchabilityPct,
    this.fertilityPct,
    this.hofPct,
  });

  factory HatchBudgetSummary.fromAudit(AuditModel audit) {
    return HatchBudgetSummary(
      totalEggsSet: audit.haTotalEggsSet ?? 0,
      healthyHatched: audit.haHatched ?? 0,
      culled: audit.haCulled ?? 0,
      deadAtHatch: audit.haDead ?? 0,
      hatchabilityPct: audit.haHatchability,
      fertilityPct: audit.haFertility,
      hofPct: audit.haHof,
    );
  }

  factory HatchBudgetSummary.fromPanelRows(List<Map<String, dynamic>> rows) {
    if (rows.isEmpty) return const HatchBudgetSummary();
    final row = rows.last;
    return HatchBudgetSummary(
      totalEggsSet: _asInt(row['totalEggsSet']) ?? 0,
      healthyHatched: _asInt(row['hatchedCount']) ?? 0,
      culled: _asInt(row['culledCount']) ?? 0,
      deadAtHatch: _asInt(row['deadCount']) ?? 0,
      hatchabilityPct: _asDouble(row['hatchabilityPct']),
      fertilityPct: _asDouble(row['fertilityPct']),
      hofPct: _asDouble(row['hofPct']),
    );
  }
}

int? _asInt(Object? raw) {
  if (raw == null) return null;
  if (raw is int) return raw;
  if (raw is num) return raw.round();
  return int.tryParse(raw.toString());
}

double? _asDouble(Object? raw) {
  if (raw == null) return null;
  if (raw is num) return raw.toDouble();
  return double.tryParse(raw.toString());
}
