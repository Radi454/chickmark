import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/performance_sync_repository.dart';
import 'package:hatchaudit/features/agents/providers/agent_monitor_provider.dart';
import 'package:hatchaudit/features/agents/screens/agent_monitor_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../support/test_database.dart';

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

  testWidgets(
    'authorized admin sees synchronized Telegram evidence through the real monitor repositories',
    (tester) async {
      late AuthProvider auth;
      late AgentMonitorProvider monitor;
      await tester.runAsync(() async {
        auth = AuthProvider(supabaseService: _AuthorizedAdminSupabaseService());
        expect(
          await auth.login('admin@example.test', 'local-test-password'),
          isTrue,
        );
        expect(auth.state, AuthState.authenticated);
        expect(auth.user?.isAdmin, isTrue);
        await _syncTelegramEvidence();
        monitor = AgentMonitorProvider(currentUser: auth.user);
        await monitor.load();
        expect(monitor.health.conversationCount, 1);
      });

      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<AuthProvider>.value(value: auth),
              ChangeNotifierProvider<AgentMonitorProvider>.value(
                value: monitor,
              ),
            ],
            child: const AgentMonitorScreen(),
          ),
        ),
      );
      await tester.pump();
      await tester.runAsync(() async {
        for (var attempt = 0; attempt < 250 && monitor.isLoading; attempt++) {
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
      });
      await tester.pump();
      expect(monitor.isLoading, isFalse);

      expect(find.text('Administrator access is required.'), findsNothing);
      expect(find.text('Agent health'), findsOneWidget);
      expect(
        find.text('Selected customer: Integration Customer'),
        findsOneWidget,
      );
      expect(find.text('Selected flock: Integration Flock'), findsOneWidget);
      expect(find.text('Selected audit: 2026-07-30'), findsOneWidget);
      expect(find.textContaining('openai / gpt-4.1-mini'), findsOneWidget);
      expect(
        find.textContaining('Latest agent error: missing_flock_sector'),
        findsOneWidget,
      );
      expect(find.textContaining('Send /new in Telegram'), findsOneWidget);
      expect(tester.takeException(), isNull);
    },
  );
}

class _AuthorizedAdminSupabaseService extends SupabaseService {
  _AuthorizedAdminSupabaseService()
    : super(checkNetworkAvailableForTesting: () async => false);

  @override
  Future<AuthResult> signIn(
    String email,
    String password, {
    bool rememberSession = true,
  }) async {
    return AuthResult(
      success: true,
      user: UserModel(
        id: 'integration-admin',
        fullName: 'Integration Admin',
        email: email,
        role: 'admin',
        status: 'approved',
        createdAt: DateTime.utc(2026, 7, 30),
      ),
    );
  }
}

Future<void> _syncTelegramEvidence() async {
  final db = await DatabaseHelper().db;
  const now = '2026-07-30T12:00:00.000Z';
  await db.insert('customers', {
    'id': 'integration-customer',
    'name': 'Integration Customer',
    'createdAt': now,
  });
  await db.insert('flocks', {
    'id': 'integration-flock',
    'customerId': 'integration-customer',
    'flockId': 'Integration Flock',
  });
  await db.insert('hatcheries', {
    'id': 'integration-hatchery',
    'customerId': 'integration-customer',
    'name': 'Integration Hatchery',
  });
  await db.insert('audit_sessions', {
    'id': 'integration-audit',
    'customerId': 'integration-customer',
    'flockId': 'integration-flock',
    'hatcheryId': 'integration-hatchery',
    'date': '2026-07-30',
  });
  await db.insert('telegram_staff_links', {
    'id': 'integration-staff',
    'telegramUserId': '70001',
    'telegramChatId': '80001',
    'displayName': 'Integration Telegram Admin',
    'status': 'allowed',
    'accessRole': 'admin',
    'createdAt': now,
    'updatedAt': now,
  });
  final sync = PerformanceSyncRepository();
  await sync.upsertRemoteRow('agent_conversations', {
    'id': 'integration-conversation',
    'staff_link_id': 'integration-staff',
    'telegram_chat_id': '80001',
    'state_version': 2,
    'context_epoch': 1,
    'selected_customer_id': 'integration-customer',
    'selected_flock_id': 'integration-flock',
    'selected_audit_id': 'integration-audit',
    'context_updated_at': now,
    'created_at': now,
    'updated_at': now,
  });
  await sync.upsertRemoteRow('agent_conversation_turns', {
    'id': 'integration-inbound',
    'conversation_id': 'integration-conversation',
    'direction': 'inbound',
    'turn_index': 1,
    'context_epoch': 1,
    'telegram_update_id': '90001',
    'text': 'Start an intake',
    'language': 'en',
    'delivery_status': 'received',
    'created_at': now,
  });
  await sync.upsertRemoteRow('agent_conversation_turns', {
    'id': 'integration-outbound',
    'conversation_id': 'integration-conversation',
    'direction': 'outbound',
    'turn_index': 1,
    'context_epoch': 1,
    'text': 'Assign a sector first.',
    'language': 'en',
    'provider': 'openai',
    'model': 'gpt-4.1-mini',
    'provider_response_id': 'integration-response',
    'reply_to_turn_id': 'integration-inbound',
    'delivery_status': 'delivered',
    'created_at': '2026-07-30T12:00:01.000Z',
  });
  await sync.upsertRemoteRow('agent_tool_events', {
    'id': 'integration-tool',
    'conversation_turn_id': 'integration-inbound',
    'tool_call_id': 'integration-tool-call',
    'tool_name': 'start_intake',
    'tool_sequence': 1,
    'arguments_json': {'flockId': 'integration-flock'},
    'result_json': {'ok': false, 'code': 'missing_flock_sector'},
    'status': 'rejected',
    'created_at': '2026-07-30T12:00:00.500Z',
  });
}
