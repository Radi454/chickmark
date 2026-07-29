import 'package:supabase_flutter/supabase_flutter.dart';

typedef AgentIntakeRpc =
    Future<dynamic> Function(String function, Map<String, dynamic> params);

abstract interface class AgentIntakeApprovalPort {
  Future<AgentIntakeApprovalResult> approve({
    required String intakeId,
    required int expectedSummaryVersion,
    String? targetSessionId,
  });
}

class AgentIntakeApprovalResult {
  const AgentIntakeApprovalResult({
    required this.intakeId,
    required this.auditSessionId,
    required this.panelRowId,
    required this.alreadyApproved,
  });

  final String intakeId;
  final String auditSessionId;
  final String panelRowId;
  final bool alreadyApproved;
}

class AgentIntakeApprovalException implements Exception {
  const AgentIntakeApprovalException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AgentIntakeApprovalService implements AgentIntakeApprovalPort {
  AgentIntakeApprovalService({AgentIntakeRpc? rpc})
    : _rpc =
          rpc ??
          ((function, params) async {
            final response = await Supabase.instance.client.functions.invoke(
              function,
              body: params,
            );
            return response.data;
          });

  final AgentIntakeRpc _rpc;

  @override
  Future<AgentIntakeApprovalResult> approve({
    required String intakeId,
    required int expectedSummaryVersion,
    String? targetSessionId,
  }) async {
    try {
      final payload = await _rpc('approve-agent-intake', {
        'intakeId': intakeId,
        'targetSessionId': targetSessionId,
        'expectedSummaryVersion': expectedSummaryVersion,
      });
      final row = _singleRow(payload);
      final result = AgentIntakeApprovalResult(
        intakeId: _requiredText(row['intake_id'], 'intake_id'),
        auditSessionId: _requiredText(
          row['audit_session_id'],
          'audit_session_id',
        ),
        panelRowId: _requiredText(row['panel_row_id'], 'panel_row_id'),
        alreadyApproved: _boolean(row['already_approved'], 'already_approved'),
      );
      if (result.intakeId != intakeId) {
        throw const FormatException('Approval response intake mismatch');
      }
      return result;
    } on AgentIntakeApprovalException {
      rethrow;
    } catch (_) {
      throw const AgentIntakeApprovalException(
        'Could not approve this intake. Refresh and try again.',
      );
    }
  }
}

Map<String, dynamic> _singleRow(Object? payload) {
  final candidate = payload is List
      ? (payload.length == 1 ? payload.single : null)
      : payload;
  if (candidate is! Map) {
    throw const FormatException('Approval response must contain one row');
  }
  return candidate.map((key, value) => MapEntry(key.toString(), value));
}

String _requiredText(Object? value, String field) {
  final text = value?.toString().trim();
  if (text == null || text.isEmpty) {
    throw FormatException('$field is required');
  }
  return text;
}

bool _boolean(Object? value, String field) {
  if (value is bool) return value;
  if (value == 1 || value == 'true') return true;
  if (value == 0 || value == 'false') return false;
  throw FormatException('$field is invalid');
}
