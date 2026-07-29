import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/supabase/agent_intake_approval_service.dart';

void main() {
  test(
    'calls the authenticated approval function with summary concurrency',
    () async {
      String? functionName;
      Map<String, dynamic>? parameters;
      final service = AgentIntakeApprovalService(
        rpc: (function, params) async {
          functionName = function;
          parameters = params;
          return [
            {
              'intake_id': 'intake-1',
              'audit_session_id': 'audit-1',
              'panel_row_id': 'panel-1',
              'already_approved': false,
            },
          ];
        },
      );

      final result = await service.approve(
        intakeId: 'intake-1',
        targetSessionId: 'audit-target',
        expectedSummaryVersion: 3,
      );

      expect(functionName, 'approve-agent-intake');
      expect(parameters, {
        'intakeId': 'intake-1',
        'targetSessionId': 'audit-target',
        'expectedSummaryVersion': 3,
      });
      expect(result.intakeId, 'intake-1');
      expect(result.auditSessionId, 'audit-1');
      expect(result.panelRowId, 'panel-1');
      expect(result.alreadyApproved, isFalse);
    },
  );

  test('accepts the idempotent single-row response shape', () async {
    final service = AgentIntakeApprovalService(
      rpc: (_, _) async => {
        'intake_id': 'intake-1',
        'audit_session_id': 'audit-1',
        'panel_row_id': 'panel-1',
        'already_approved': true,
      },
    );

    final result = await service.approve(
      intakeId: 'intake-1',
      expectedSummaryVersion: 1,
    );

    expect(result.alreadyApproved, isTrue);
    expect(result.auditSessionId, 'audit-1');
  });

  test('turns backend failures into a safe review error', () async {
    final service = AgentIntakeApprovalService(
      rpc: (_, _) => throw Exception('service key secret and SQL internals'),
    );

    await expectLater(
      service.approve(intakeId: 'intake-1', expectedSummaryVersion: 1),
      throwsA(
        isA<AgentIntakeApprovalException>().having(
          (error) => error.message,
          'message',
          'Could not approve this intake. Refresh and try again.',
        ),
      ),
    );
  });

  test('rejects an incomplete RPC response', () async {
    final service = AgentIntakeApprovalService(
      rpc: (_, _) async => <String, Object?>{'intake_id': 'intake-1'},
    );

    await expectLater(
      service.approve(intakeId: 'intake-1', expectedSummaryVersion: 1),
      throwsA(isA<AgentIntakeApprovalException>()),
    );
  });
}
