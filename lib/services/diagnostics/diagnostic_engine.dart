import 'dart:convert';

import '../../data/models/audit_model.dart';
import '../../data/models/audit_session_model.dart';

/// A diagnostic finding tied to a completed visit or station.
class DiagnosticFinding {
  final String scope;
  final String? stationKey;
  final String severity;
  final String title;
  final String? detail;
  final String? sourceCitation;
  final String? recommendedAction;

  const DiagnosticFinding({
    required this.scope,
    this.stationKey,
    required this.severity,
    required this.title,
    this.detail,
    this.sourceCitation,
    this.recommendedAction,
  });

  Map<String, dynamic> toMap() => {
    'scope': scope,
    'stationKey': stationKey,
    'severity': severity,
    'title': title,
    'detail': detail,
    'sourceCitation': sourceCitation,
    'recommendedAction': recommendedAction,
  };

  factory DiagnosticFinding.fromMap(Map<String, dynamic> map) =>
      DiagnosticFinding(
        scope: map['scope'] as String? ?? 'session',
        stationKey: map['stationKey'] as String?,
        severity: map['severity'] as String? ?? 'unknown',
        title: map['title'] as String? ?? '',
        detail: map['detail'] as String?,
        sourceCitation: map['sourceCitation'] as String?,
        recommendedAction: map['recommendedAction'] as String?,
      );
}

/// Placeholder diagnostic engine.
///
/// Returns an empty findings list for completed sessions.
/// Rule-based logic will be added in a later phase without modifying
/// completed session records.
class DiagnosticEngine {
  const DiagnosticEngine();

  /// Evaluates a completed session and returns structured findings.
  ///
  /// Currently returns a placeholder empty list. Future implementations
  /// will apply rule-based logic against [session] and [stationAudits].
  List<DiagnosticFinding> evaluate({
    required AuditSessionModel session,
    required List<AuditModel> stationAudits,
  }) {
    return const [];
  }

  /// Serializes findings to JSON for storage in [AuditSessionModel.findingsJson].
  String? toJson(List<DiagnosticFinding> findings) {
    if (findings.isEmpty) return null;
    return jsonEncode(findings.map((f) => f.toMap()).toList());
  }

  /// Deserializes findings from stored JSON.
  List<DiagnosticFinding> fromJson(String? json) {
    if (json == null || json.isEmpty) return const [];
    try {
      final decoded = jsonDecode(json);
      if (decoded is List) {
        return decoded
            .map((e) => DiagnosticFinding.fromMap(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return const [];
  }
}
