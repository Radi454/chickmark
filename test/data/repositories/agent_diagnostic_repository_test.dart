import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/agent_diagnostic_models.dart';
import 'package:hatchaudit/data/repositories/agent_diagnostic_repository.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    await databaseFactory.deleteDatabase(
      p.join(databaseDirectory.path, 'hatchaudit.db'),
    );
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test(
    'health counts delivery, tool, and unassigned-sector failures',
    () async {
      await _seedDiagnosticGraph();

      final health = await AgentDiagnosticRepository().loadHealth();

      expect(health.conversationCount, 1);
      expect(health.failedDeliveryCount, 1);
      expect(health.pendingDeliveryCount, 1);
      expect(health.failedToolCount, 1);
      expect(health.unassignedFlockCount, greaterThanOrEqualTo(1));
      expect(health.hasErrors, isTrue);
    },
  );

  test('pending replies require attention even without a hard failure', () {
    const health = AgentHealthSnapshot(pendingDeliveryCount: 1);

    expect(health.hasErrors, isTrue);
  });

  test(
    'conversation diagnostics expose latest activity, error time, and model',
    () async {
      await _seedDiagnosticGraph();

      final rows = await AgentDiagnosticRepository()
          .listConversationDiagnostics();

      expect(rows, hasLength(1));
      final diagnostic = rows.single;
      expect(diagnostic.staffName, 'Authorized Admin');
      expect(diagnostic.customerName, 'Diagnostic Customer');
      expect(diagnostic.flockName, 'Diagnostic Flock');
      expect(diagnostic.auditLabel, '2026-07-30');
      expect(diagnostic.flockSectorKey, isNull);
      expect(diagnostic.latestReplyText, 'Second reply');
      expect(diagnostic.latestTurnIndex, 2);
      expect(diagnostic.provider, 'openai');
      expect(diagnostic.model, 'gpt-4.1-mini');
      expect(diagnostic.deliveryStatus, 'pending');
      expect(diagnostic.latestToolErrorCode, 'unsupported_station_schema');
      expect(
        diagnostic.latestToolErrorAt,
        DateTime.parse('2026-07-30T10:00:00.500Z'),
      );
      expect(diagnostic.updatedAt, DateTime.parse('2026-07-30T10:00:02.000Z'));
    },
  );
}

Future<void> _seedDiagnosticGraph() async {
  final db = await DatabaseHelper().db;
  const now = '2026-07-30T10:00:00.000Z';
  await db.insert('customers', {
    'id': 'diagnostic-customer',
    'name': 'Diagnostic Customer',
    'createdAt': now,
  });
  await db.insert('flocks', {
    'id': 'diagnostic-flock',
    'customerId': 'diagnostic-customer',
    'flockId': 'Diagnostic Flock',
  });
  await db.insert('hatcheries', {
    'id': 'diagnostic-hatchery',
    'customerId': 'diagnostic-customer',
    'name': 'Diagnostic Hatchery',
  });
  await db.insert('audit_sessions', {
    'id': 'diagnostic-audit',
    'customerId': 'diagnostic-customer',
    'flockId': 'diagnostic-flock',
    'hatcheryId': 'diagnostic-hatchery',
    'date': '2026-07-30',
  });
  await db.insert('telegram_staff_links', {
    'id': 'diagnostic-staff',
    'telegramUserId': '10001',
    'telegramChatId': '20001',
    'displayName': 'Authorized Admin',
    'status': 'allowed',
    'accessRole': 'admin',
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('agent_conversations', {
    'id': 'diagnostic-conversation',
    'staffLinkId': 'diagnostic-staff',
    'telegramChatId': '20001',
    'stateVersion': 3,
    'contextEpoch': 2,
    'selectedCustomerId': 'diagnostic-customer',
    'selectedFlockId': 'diagnostic-flock',
    'selectedAuditId': 'diagnostic-audit',
    'contextUpdatedAt': now,
    'createdAt': now,
    'updatedAt': now,
  });
  await db.insert('agent_conversation_turns', {
    'id': 'diagnostic-inbound-1',
    'conversationId': 'diagnostic-conversation',
    'direction': 'inbound',
    'turnIndex': 1,
    'contextEpoch': 2,
    'telegramUpdateId': '30001',
    'text': 'First request',
    'language': 'en',
    'deliveryStatus': 'received',
    'createdAt': now,
  });
  await db.insert('agent_conversation_turns', {
    'id': 'diagnostic-outbound-1',
    'conversationId': 'diagnostic-conversation',
    'direction': 'outbound',
    'turnIndex': 1,
    'contextEpoch': 2,
    'text': 'First reply',
    'language': 'en',
    'provider': 'openai',
    'model': 'gpt-4.1-mini',
    'providerResponseId': 'response-1',
    'replyToTurnId': 'diagnostic-inbound-1',
    'deliveryStatus': 'failed',
    'createdAt': '2026-07-30T10:00:01.000Z',
  });
  await db.insert('agent_conversation_turns', {
    'id': 'diagnostic-outbound-2',
    'conversationId': 'diagnostic-conversation',
    'direction': 'outbound',
    'turnIndex': 2,
    'contextEpoch': 2,
    'text': 'Second reply',
    'language': 'en',
    'provider': 'openai',
    'model': 'gpt-4.1-mini',
    'providerResponseId': 'response-2',
    'deliveryStatus': 'pending',
    'createdAt': '2026-07-30T10:00:02.000Z',
  });
  await db.insert('agent_tool_events', {
    'id': 'diagnostic-tool-error',
    'conversationTurnId': 'diagnostic-inbound-1',
    'toolCallId': 'tool-call-1',
    'toolName': 'get_station_schema',
    'toolSequence': 1,
    'argumentsJson': '{"schemaKey":"unsupported","schemaVersion":1}',
    'resultJson': '{"ok":false,"code":"unsupported_station_schema"}',
    'status': 'rejected',
    'createdAt': '2026-07-30T10:00:00.500Z',
  });
}
