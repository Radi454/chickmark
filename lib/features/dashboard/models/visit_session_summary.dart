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
  final int totalDeformities;
  final bool gaspingPresent;
  final String? gaspingType;
  final String? overallSeverity;

  const PmScoreSummary({
    this.totalLesions = 0,
    this.totalDeformities = 0,
    this.gaspingPresent = false,
    this.gaspingType,
    this.overallSeverity,
  });

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

    int deformities = 0;
    deformities += audit.pmExposedBrainCount ?? 0;
    deformities += audit.pmEctopicVisceraCount ?? 0;
    deformities += audit.pmExtraLegsCount ?? 0;
    deformities += audit.pmCrossedBeakCount ?? 0;
    deformities += audit.pmAbsentEyeBothCount ?? 0;
    deformities += audit.pmAbsentEyeOneCount ?? 0;
    deformities += audit.pmSmallEyeCount ?? 0;
    deformities += audit.pmHydrocephalyCount ?? 0;
    deformities += audit.pmStarGazerCount ?? 0;
    deformities += audit.pmCurledToesCount ?? 0;
    deformities += audit.pmShortLegsCount ?? 0;
    deformities += audit.pmSpinalDeformityCount ?? 0;
    deformities += audit.pmCardiacAnomalyCount ?? 0;
    deformities += audit.pmConjoinedCount ?? 0;
    deformities += audit.pmOtherDeformityCount ?? 0;

    String? severity;
    if (lesions == 0 &&
        deformities == 0 &&
        !(audit.pmGaspingPresent ?? false)) {
      severity = 'green';
    } else if (lesions > 5 || deformities > 3) {
      severity = 'red';
    } else {
      severity = 'amber';
    }

    return PmScoreSummary(
      totalLesions: lesions,
      totalDeformities: deformities,
      gaspingPresent: audit.pmGaspingPresent ?? false,
      gaspingType: audit.pmGaspingType,
      overallSeverity: severity,
    );
  }
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
}
