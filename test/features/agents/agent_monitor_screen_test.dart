import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/agent_intake_models.dart';
import 'package:hatchaudit/data/models/agent_diagnostic_models.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/agent_intake_repository.dart';
import 'package:hatchaudit/data/repositories/agent_diagnostic_repository.dart';
import 'package:hatchaudit/data/repositories/hatchery_agent_repository.dart';
import 'package:hatchaudit/features/agents/providers/agent_monitor_provider.dart';
import 'package:hatchaudit/features/agents/screens/agent_monitor_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/services/supabase/agent_intake_approval_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Agent Monitor shows batch list and row warnings', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning();

    await _pumpMonitor(tester, repository: repository, user: _adminUser());

    await tester.pumpAndSettle();

    expect(find.text('Agent Monitor'), findsOneWidget);
    expect(find.textContaining('Hatchability'), findsWidgets);
    expect(find.text('Confidence'), findsOneWidget);
    expect(find.text('Warnings'), findsOneWidget);
    expect(find.textContaining('Review'), findsWidgets);
    expect(
      find.textContaining('Hatchability changed from 80.0% to 85.0%'),
      findsOneWidget,
    );
  });

  testWidgets('Agent Monitor fits a narrow mobile layout', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final repository = _repositoryWithOneWarning();

    await _pumpMonitor(tester, repository: repository, user: _adminUser());

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Agent Monitor'), findsOneWidget);
  });

  testWidgets('narrow layout scrolls the whole monitor page', (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpMonitor(
      tester,
      repository: _repositoryWithOneWarning(staffLinks: const [
        TelegramStaffLink(
          id: 'allowed-1',
          telegramUserId: '777',
          displayName: 'Customer Operator',
          status: TelegramStaffLinkStatus.allowed,
          accessRole: TelegramAgentAccessRole.customer,
          customerId: 'customer-1',
        ),
      ]),
      user: _adminUser(),
    );
    await tester.pumpAndSettle();

    final page = find.byKey(const ValueKey('agent-monitor-scroll'));
    expect(page, findsOneWidget);

    // Header panels used to be pinned, leaving the workspace unreachable.
    await tester.drag(page, const Offset(0, -600));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    await tester.ensureVisible(find.text('Extracted rows'));
    await tester.pumpAndSettle();
    expect(find.text('Extracted rows'), findsOneWidget);
    expect(find.text('Admin action history'), findsOneWidget);
  });

  testWidgets('header panels collapse to free up workspace room', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(360, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await _pumpMonitor(
      tester,
      repository: _repositoryWithOneWarning(),
      user: _adminUser(),
      diagnosticRepository: _FakeAgentDiagnosticRepository(
        health: const AgentHealthSnapshot(conversationCount: 2),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Send /new in Telegram'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-health-toggle')));
    await tester.pumpAndSettle();

    expect(find.textContaining('Send /new in Telegram'), findsNothing);
    expect(find.text('Conversations 2 · no open issues'), findsOneWidget);
  });

  testWidgets('Agent Monitor explains context, model, errors, and /new', (
    tester,
  ) async {
    final diagnostics = _FakeAgentDiagnosticRepository(
      health: const AgentHealthSnapshot(
        conversationCount: 1,
        failedToolCount: 1,
        unassignedFlockCount: 1,
      ),
      conversations: [
        AgentConversationDiagnostic(
          id: 'conversation-1',
          contextEpoch: 2,
          updatedAt: DateTime.utc(2026, 7, 30),
          staffName: 'Authorized Admin',
          selectedCustomerId: 'customer-1',
          selectedFlockId: 'flock-1',
          customerName: 'Customer One',
          flockName: 'Flock One',
          latestTurnIndex: 3,
          provider: 'openai',
          model: 'gpt-4.1-mini',
          deliveryStatus: 'delivered',
          latestToolErrorCode: 'missing_flock_sector',
          latestToolErrorAt: DateTime.utc(2026, 7, 30, 9, 45),
        ),
      ],
    );

    await _pumpMonitor(
      tester,
      repository: _repositoryWithOneWarning(),
      user: _adminUser(),
      diagnosticRepository: diagnostics,
    );
    await tester.pumpAndSettle();

    expect(find.text('Agent health'), findsOneWidget);
    expect(find.text('Selected customer: Customer One'), findsOneWidget);
    expect(find.text('Selected flock: Flock One'), findsOneWidget);
    expect(find.text('Selected audit: Not selected'), findsOneWidget);
    expect(find.textContaining('no sector assignment'), findsOneWidget);
    expect(find.textContaining('openai / gpt-4.1-mini'), findsOneWidget);
    expect(
      find.textContaining('Latest agent error: missing_flock_sector'),
      findsOneWidget,
    );
    expect(find.textContaining('2026-07-30 09:45 UTC'), findsOneWidget);
    expect(find.textContaining('Send /new in Telegram'), findsOneWidget);
  });

  testWidgets('pending replies mark Agent Monitor as needing attention', (
    tester,
  ) async {
    await _pumpMonitor(
      tester,
      repository: _repositoryWithOneWarning(),
      user: _adminUser(),
      diagnosticRepository: _FakeAgentDiagnosticRepository(
        health: const AgentHealthSnapshot(pendingDeliveryCount: 1),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Needs attention'), findsOneWidget);
  });

  testWidgets('approved admin can pause Telegram ingestion', (tester) async {
    final repository = _repositoryWithOneWarning();

    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    final toggle = find.byKey(const ValueKey('telegram-agent-toggle'));
    expect(toggle, findsOneWidget);

    await tester.tap(toggle);
    await tester.pump();

    expect(repository.settingsSaveCount, 1);
    expect(repository.settings.telegramEnabled, isFalse);
  });

  testWidgets('Agent Monitor shows pending Telegram staff access requests', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning(
      pendingStaffLinks: [_pendingStaffLink()],
    );

    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    expect(find.text('Pending Telegram access'), findsOneWidget);
    expect(find.text('New Staff'), findsOneWidget);
    expect(find.text('@newstaff'), findsOneWidget);
    expect(find.text('Telegram ID: 999'), findsOneWidget);
    expect(find.text('Chat ID: 123'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-staff-approve-pending-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-staff-reject-pending-1')),
      findsOneWidget,
    );
  });

  testWidgets('admin can approve pending Telegram staff access', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning(
      pendingStaffLinks: [_pendingStaffLink()],
    );

    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('agent-staff-approve-pending-1')),
    );
    await tester.pumpAndSettle();

    expect(find.text('Assign Telegram access'), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.byKey(const ValueKey('agent-staff-confirm-assignment')),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(
      find.byKey(const ValueKey('agent-staff-customer-dropdown')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer A').last);
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('agent-staff-confirm-assignment')),
    );
    await tester.pumpAndSettle();

    expect(repository.staffScopeDecisions.single.linkId, 'pending-1');
    expect(
      repository.staffScopeDecisions.single.accessRole,
      TelegramAgentAccessRole.customer,
    );
    expect(repository.staffScopeDecisions.single.customerId, 'customer-1');
    expect(repository.staffScopeDecisions.single.decidedBy, 'admin-1');
  });

  testWidgets('admin can explicitly grant all-customer agent access', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning(
      pendingStaffLinks: [_pendingStaffLink()],
    );
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('agent-staff-approve-pending-1')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-staff-role-admin')));
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey('agent-staff-confirm-assignment')),
    );
    await tester.pumpAndSettle();

    expect(
      repository.staffScopeDecisions.single.accessRole,
      TelegramAgentAccessRole.admin,
    );
    expect(repository.staffScopeDecisions.single.customerId, isNull);
  });

  testWidgets('existing Telegram user displays its enforced customer scope', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning(
      staffLinks: const [
        TelegramStaffLink(
          id: 'allowed-1',
          telegramUserId: '777',
          displayName: 'Customer Operator',
          status: TelegramStaffLinkStatus.allowed,
          accessRole: TelegramAgentAccessRole.customer,
          customerId: 'customer-1',
        ),
      ],
    );
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    expect(find.text('Telegram users'), findsOneWidget);
    expect(find.text('Customer Operator'), findsOneWidget);
    expect(find.text('Customer access · Customer A'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('agent-staff-edit-allowed-1')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-staff-revoke-allowed-1')),
      findsOneWidget,
    );
  });

  testWidgets('admin can reject pending Telegram staff access', (tester) async {
    final repository = _repositoryWithOneWarning(
      pendingStaffLinks: [_pendingStaffLink()],
    );

    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('agent-staff-reject-pending-1')),
    );
    await tester.pumpAndSettle();

    expect(repository.staffStatusDecisions.single.linkId, 'pending-1');
    expect(
      repository.staffStatusDecisions.single.status,
      TelegramStaffLinkStatus.revoked,
    );
    expect(repository.staffStatusDecisions.single.decidedBy, 'admin-1');
  });

  testWidgets('admin approval action approves the selected draft row', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning();
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Approve'));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(repository.approvedRowId, 'row-1');
    expect(repository.approvedBy, 'admin-1');
  });

  testWidgets('auditors cannot load or control Agent Monitor', (tester) async {
    final repository = _repositoryWithOneWarning();

    await _pumpMonitor(tester, repository: repository, user: _auditorUser());
    await tester.pumpAndSettle();

    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(find.byKey(const ValueKey('telegram-agent-toggle')), findsNothing);
    expect(find.text('Daily hatch report'), findsNothing);
    expect(find.text('Edit'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
    expect(repository.settingsLoadCount, 0);
    expect(repository.batchSummaryLoadCount, 0);
    expect(repository.settingsSaveCount, 0);
  });

  testWidgets('customers remain outside Agent Monitor', (tester) async {
    final repository = _repositoryWithOneWarning();

    await _pumpMonitor(tester, repository: repository, user: _customerUser());
    await tester.pumpAndSettle();

    expect(find.text('Administrator access is required.'), findsOneWidget);
    expect(find.byKey(const ValueKey('telegram-agent-toggle')), findsNothing);
    expect(find.text('Daily hatch report'), findsNothing);
    expect(repository.settingsLoadCount, 0);
    expect(repository.batchSummaryLoadCount, 0);
    expect(repository.settingsSaveCount, 0);
  });

  testWidgets('reject action forwards an optional admin reason', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning();
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Reject'));
    await tester.tap(find.text('Reject'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-rejection-reason')),
      'Wrong flock',
    );
    await tester.tap(find.byKey(const ValueKey('agent-confirm-rejection')));
    await tester.pumpAndSettle();

    expect(repository.rejectedRowId, 'row-1');
    expect(repository.rejectedBy, 'admin-1');
    expect(repository.rejectionReason, 'Wrong flock');
  });

  testWidgets('edit action saves changed draft row fields', (tester) async {
    final repository = _repositoryWithOneWarning();
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-edit-station-name')),
      'Station B',
    );
    await tester.enterText(
      find.byKey(const ValueKey('agent-edit-hatch-date')),
      '2026-08-01',
    );
    await tester.tap(find.byKey(const ValueKey('agent-save-row-edit')));
    await tester.pumpAndSettle();

    expect(repository.updatedRow?.stationName, 'Station B');
    expect(repository.updatedRow?.hatchDate, DateTime.utc(2026, 8, 1));
  });

  testWidgets('edit resolves names through hierarchy selectors without UUIDs', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning();
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('agent-edit-customer-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-edit-flock-selector')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey('agent-edit-hatchery-selector')),
      findsOneWidget,
    );
    expect(find.text('Customer ID'), findsNothing);
    expect(find.text('Flock ID'), findsNothing);
    expect(find.text('Hatchery ID'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('agent-save-row-edit')));
    await tester.pumpAndSettle();

    expect(repository.updatedRow?.customerId, 'customer-1');
    expect(repository.updatedRow?.customerName, 'Customer A');
    expect(repository.updatedRow?.flockId, 'flock-1');
    expect(repository.updatedRow?.flockName, 'Flock 12');
    expect(repository.updatedRow?.hatcheryId, 'hatchery-1');
  });

  testWidgets('changing customer scopes the flock and hatchery selectors', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning();
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();

    await tester.tap(
      find.byKey(const ValueKey('agent-edit-customer-selector')),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('Customer B').last);
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('agent-edit-flock-selector')));
    await tester.pumpAndSettle();
    await tester.tap(find.textContaining('Flock B').last);
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('agent-save-row-edit')));
    await tester.pumpAndSettle();

    expect(repository.updatedRow?.customerId, 'customer-2');
    expect(repository.updatedRow?.customerName, 'Customer B');
    expect(repository.updatedRow?.flockId, 'flock-2');
    expect(repository.updatedRow?.flockName, 'Flock B');
    expect(repository.updatedRow?.hatcheryId, 'hatchery-2');
  });

  testWidgets('saving preserves persisted links missing from local catalog', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning(
      row: HatcheryDraftRow(
        id: 'row-1',
        batchId: 'batch-1',
        rowOrdinal: 1,
        status: HatcheryDraftRowStatus.needsReview,
        customerId: 'remote-customer',
        customerName: 'Remote Customer',
        flockId: 'remote-flock',
        flockName: 'Remote Flock',
        hatcheryId: 'remote-hatchery',
        stationName: 'Station A',
        breed: 'Ross',
        eggsPlaced: 1000,
        totalProduction: 850,
        hatchabilityPct: 85,
        confidencePct: 91,
      ),
    );
    await _pumpMonitor(tester, repository: repository, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Edit'));
    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    expect(
      find.textContaining('Unavailable locally', skipOffstage: false),
      findsNWidgets(3),
    );

    await tester.tap(find.byKey(const ValueKey('agent-save-row-edit')));
    await tester.pumpAndSettle();

    expect(repository.updatedRow?.customerId, 'remote-customer');
    expect(repository.updatedRow?.customerName, 'Remote Customer');
    expect(repository.updatedRow?.flockId, 'remote-flock');
    expect(repository.updatedRow?.flockName, 'Remote Flock');
    expect(repository.updatedRow?.hatcheryId, 'remote-hatchery');
  });

  testWidgets(
    'Agent Monitor presents a confirmed conversational Pasgar draft',
    (tester) async {
      final intakeRepository = _FakeAgentIntakeRepository();
      await _pumpMonitor(
        tester,
        repository: _repositoryWithOneWarning(),
        intakeRepository: intakeRepository,
        user: _adminUser(),
      );
      await tester.pumpAndSettle();

      expect(find.text('Conversational station intakes'), findsOneWidget);
      expect(find.text('Chick Quality — Pasgar'), findsOneWidget);
      expect(find.text('Customer One'), findsOneWidget);
      expect(find.text('Flock One'), findsOneWidget);
      expect(find.text('Main Hatchery'), findsWidgets);
      expect(find.text('Reflexes'), findsOneWidget);
      expect(find.text('2 chicks'), findsWidgets);
      expect(find.text('5.0 percent'), findsWidgets);
      expect(find.text('9.8 score'), findsOneWidget);
      expect(find.text('Schema v1'), findsOneWidget);
      expect(find.text('sample 40'), findsNothing);
      expect(
        find.byKey(const ValueKey('agent-intake-conversation-evidence')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('agent-intake-approve-new')),
        findsOneWidget,
      );
      expect(find.byKey(const ValueKey('agent-intake-attach')), findsOneWidget);
      expect(find.byKey(const ValueKey('agent-intake-reject')), findsOneWidget);
    },
  );

  testWidgets('review card renders a non-Pasgar station from its schema', (
    tester,
  ) async {
    final intakeRepository = _FakeAgentIntakeRepository(
      initialDetails: _weightDetails(),
    );
    await _pumpMonitor(
      tester,
      repository: _repositoryWithOneWarning(),
      intakeRepository: intakeRepository,
      user: _adminUser(),
    );
    await tester.pumpAndSettle();

    expect(find.text('Chick Quality — Weights'), findsOneWidget);
    expect(find.text('Chick weights'), findsOneWidget);
    expect(find.text('[39.5,40.0,41.25] grams'), findsOneWidget);
    expect(find.text('weights from scale · 96%'), findsOneWidget);
    expect(find.text('Avg Weight'), findsOneWidget);
    expect(find.text('40.3 grams'), findsOneWidget);
    expect(find.text('House'), findsOneWidget);
  });

  testWidgets('Pasgar evidence expands and an admin can edit a count', (
    tester,
  ) async {
    final intakeRepository = _FakeAgentIntakeRepository();
    await _pumpMonitor(
      tester,
      repository: _repositoryWithOneWarning(),
      intakeRepository: intakeRepository,
      user: _adminUser(),
    );
    await tester.pumpAndSettle();

    final evidence = find.byKey(
      const ValueKey('agent-intake-conversation-evidence'),
    );
    await tester.ensureVisible(evidence);
    await tester.tap(evidence);
    await tester.pumpAndSettle();
    expect(find.text('sample 40'), findsOneWidget);

    final edit = find.byKey(
      const ValueKey('agent-intake-edit-pasgarNavelCount'),
    );
    await tester.ensureVisible(edit);
    await tester.tap(edit);
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('agent-intake-edit-value-input')),
      '3',
    );
    await tester.tap(find.byKey(const ValueKey('agent-intake-save-value')));
    await tester.pumpAndSettle();

    expect(intakeRepository.updatedFieldKey, 'pasgarNavelCount');
    expect(intakeRepository.updatedValue, 3);
  });
}

Future<void> _pumpMonitor(
  WidgetTester tester, {
  required _FakeHatcheryAgentRepository repository,
  required UserModel user,
  AgentIntakeRepository? intakeRepository,
  AgentIntakeApprovalPort? approvalPort,
  AgentDiagnosticRepository? diagnosticRepository,
}) {
  return tester.pumpWidget(
    MaterialApp(
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      home: MultiProvider(
        providers: [
          ChangeNotifierProvider<AgentMonitorProvider>(
            create: (_) => AgentMonitorProvider(
              repository: repository,
              intakeRepository:
                  intakeRepository ?? _FakeEmptyAgentIntakeRepository(),
              diagnosticRepository:
                  diagnosticRepository ?? _FakeAgentDiagnosticRepository(),
              approvalPort: approvalPort ?? _FakeApprovalPort(),
              currentUser: user,
            ),
          ),
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider(user),
          ),
        ],
        child: const AgentMonitorScreen(),
      ),
    ),
  );
}

class _FakeAgentDiagnosticRepository extends AgentDiagnosticRepository {
  _FakeAgentDiagnosticRepository({
    this.health = const AgentHealthSnapshot(),
    this.conversations = const [],
  });

  final AgentHealthSnapshot health;
  final List<AgentConversationDiagnostic> conversations;

  @override
  Future<AgentHealthSnapshot> loadHealth() async => health;

  @override
  Future<List<AgentConversationDiagnostic>> listConversationDiagnostics({
    int limit = 25,
  }) async => conversations;
}

class _FakeEmptyAgentIntakeRepository extends AgentIntakeRepository {
  @override
  Future<List<AgentIntakeSession>> listAwaitingReview() async => const [];
}

class _FakeAgentIntakeRepository extends AgentIntakeRepository {
  _FakeAgentIntakeRepository({AgentIntakeDetails? initialDetails})
    : details = initialDetails ?? _pasgarDetails();

  AgentIntakeDetails details;
  String? updatedFieldKey;
  Object? updatedValue;

  @override
  Future<List<AgentIntakeSession>> listAwaitingReview() async {
    return [details.session];
  }

  @override
  Future<AgentIntakeDetails?> loadDetails(String intakeId) async => details;

  @override
  Future<List<AuditSessionModel>> listMatchingAuditSessions(
    AgentIntakeSession intake,
  ) async {
    return [
      AuditSessionModel(
        id: 'audit-existing',
        customerId: 'customer-1',
        flockId: 'flock-1',
        hatcheryId: 'hatchery-1',
        date: DateTime.utc(2026, 7, 28),
        createdAt: DateTime.utc(2026, 7, 28),
        updatedAt: DateTime.utc(2026, 7, 28),
      ),
    ];
  }

  @override
  Future<void> updateValue({
    required String intakeId,
    required String fieldKey,
    required Object? value,
    DateTime? updatedAt,
  }) async {
    updatedFieldKey = fieldKey;
    updatedValue = value;
    final values = Map<String, Object?>.from(details.session.workingValues)
      ..[fieldKey] = value;
    final map = details.session.toMap();
    map['workingValuesJson'] = values;
    map['summaryVersion'] = 2;
    map['summarySnapshotJson'] = {
      'version': 2,
      'values': values,
      'generatedAt': '2026-07-28T13:00:00.000Z',
    };
    details = AgentIntakeDetails(
      session: AgentIntakeSession.fromMap(map),
      values: details.values,
      turns: details.turns,
    );
  }
}

class _FakeApprovalPort implements AgentIntakeApprovalPort {
  @override
  Future<AgentIntakeApprovalResult> approve({
    required String intakeId,
    required int expectedSummaryVersion,
    String? targetSessionId,
  }) async {
    return AgentIntakeApprovalResult(
      intakeId: intakeId,
      auditSessionId: targetSessionId ?? 'audit-new',
      panelRowId: 'panel-1',
      alreadyApproved: false,
    );
  }
}

AgentIntakeDetails _pasgarDetails() {
  const values = <String, int>{
    'pasgarSampleSize': 40,
    'pasgarReflexesCount': 2,
    'pasgarBeakCount': 1,
    'pasgarNavelCount': 1,
    'pasgarBellyCount': 1,
    'pasgarLegCount': 2,
    'pasgarFeatherDevCount': 3,
  };
  return AgentIntakeDetails(
    session: AgentIntakeSession.fromMap({
      'id': 'intake-1',
      'staffLinkId': 'staff-1',
      'telegramChatId': 'chat-1',
      'schemaKey': 'chicks.pasgar',
      'schemaVersion': 1,
      'state': 'awaiting_admin_review',
      'language': 'mixed',
      'customerId': 'customer-1',
      'customerName': 'Customer One',
      'flockId': 'flock-1',
      'flockName': 'Flock One',
      'hatcheryId': 'hatchery-1',
      'hatcheryName': 'Main Hatchery',
      'auditDate': '2026-07-28',
      'scope': 'pool',
      'workingValuesJson': values,
      'summaryVersion': 1,
      'summarySnapshotJson': {
        'version': 1,
        'values': values,
        'generatedAt': '2026-07-28T12:00:00.000Z',
      },
      'userConfirmedAt': '2026-07-28T12:01:00.000Z',
      'createdAt': '2026-07-28T11:00:00.000Z',
      'updatedAt': '2026-07-28T12:01:00.000Z',
    }),
    values: const [],
    turns: [
      AgentIntakeTurn.fromMap({
        'id': 'turn-1',
        'intakeSessionId': 'intake-1',
        'direction': 'inbound',
        'telegramUpdateId': 'update-1',
        'telegramMessageId': 'message-1',
        'text': 'sample 40',
        'language': 'en',
        'intent': 'provide_data',
        'createdAt': '2026-07-28T11:30:00.000Z',
      }),
    ],
  );
}

AgentIntakeDetails _weightDetails() {
  final values = <String, Object?>{
    'weightsJson': [39.5, 40.0, 41.25],
  };
  return AgentIntakeDetails(
    session: AgentIntakeSession.fromMap({
      'id': 'intake-weights',
      'staffLinkId': 'staff-1',
      'telegramChatId': 'chat-1',
      'schemaKey': 'chicks.weights',
      'schemaVersion': 1,
      'state': 'awaiting_admin_review',
      'language': 'mixed',
      'customerId': 'customer-1',
      'customerName': 'Customer One',
      'flockId': 'flock-1',
      'flockName': 'Flock One',
      'hatcheryId': 'hatchery-1',
      'hatcheryName': 'Main Hatchery',
      'auditDate': '2026-07-28',
      'scope': 'house',
      'workingValuesJson': values,
      'summaryVersion': 1,
      'summarySnapshotJson': {
        'version': 1,
        'schemaKey': 'chicks.weights',
        'schemaVersion': 1,
        'values': values,
        'calculations': {
          'sampleSize': 3,
          'avgWeight': 40.3,
          'uniformityPct': 100.0,
          'cvPct': 2.2,
        },
        'generatedAt': '2026-07-28T12:00:00.000Z',
      },
      'userConfirmedAt': '2026-07-28T12:01:00.000Z',
      'createdAt': '2026-07-28T11:00:00.000Z',
      'updatedAt': '2026-07-28T12:01:00.000Z',
    }),
    values: [
      AgentIntakeValue.fromMap({
        'id': 'weight-value',
        'intakeSessionId': 'intake-weights',
        'fieldKey': 'weightsJson',
        'valueJson': jsonEncode(values['weightsJson']),
        'sourcePhrase': 'weights from scale',
        'confidence': 0.96,
        'createdAt': '2026-07-28T11:30:00.000Z',
        'updatedAt': '2026-07-28T11:30:00.000Z',
      }),
    ],
    turns: const [],
  );
}

_FakeHatcheryAgentRepository _repositoryWithOneWarning({
  HatcheryDraftRow? row,
  List<TelegramStaffLink> pendingStaffLinks = const [],
  List<TelegramStaffLink> staffLinks = const [],
}) {
  final summary = HatcheryDraftBatchSummary(
    id: 'batch-1',
    submissionId: 'submission-1',
    status: AgentSubmissionStatus.needsAdminReview,
    submittedAt: DateTime.utc(2026, 7, 27, 10, 30),
    sourceKind: AgentSourceKind.text,
    sourceSummary: 'Daily hatch report',
    sourceText: 'Customer A flock 12 hatch report',
    telegramUserId: '456',
    rowCount: 1,
    needsReviewCount: 1,
    approvedCount: 0,
    rejectedCount: 0,
  );
  final details = HatcheryDraftBatchDetails(
    submission: HatcheryAgentSubmission(
      id: 'submission-1',
      telegramUserId: '456',
      sourceKind: AgentSourceKind.text,
      sourceText: 'Customer A flock 12 hatch report',
      status: AgentSubmissionStatus.needsAdminReview,
      submittedAt: DateTime.utc(2026, 7, 27, 10, 30),
    ),
    batch: const HatcheryDraftBatch(
      id: 'batch-1',
      submissionId: 'submission-1',
      status: AgentSubmissionStatus.needsAdminReview,
      sourceSummary: 'Daily hatch report',
    ),
    rows: [
      row ??
          HatcheryDraftRow(
            id: 'row-1',
            batchId: 'batch-1',
            rowOrdinal: 1,
            status: HatcheryDraftRowStatus.needsReview,
            customerName: 'Customer A',
            flockName: 'Flock 12',
            stationName: 'Station A',
            breed: 'Ross',
            eggsPlaced: 1000,
            totalProduction: 850,
            hatchabilityPct: 85,
            confidencePct: 91,
            warningsJson: jsonEncode([
              {
                'kind': 'historicalChange',
                'severity': 'review',
                'messageEn': 'Hatchability changed from 80.0% to 85.0%.',
                'messageAr': 'تغيرت قابلية الفقس من 80.0٪ إلى 85.0٪.',
                'previousPct': 80,
                'currentPct': 85,
              },
            ]),
          ),
    ],
    questions: const [
      HatcheryAgentQuestion(
        id: 'question-1',
        submissionId: 'submission-1',
        rowOrdinal: 1,
        fieldKey: 'flockAgeWeeks',
        questionTextEn: 'What is the flock age?',
        questionTextAr: 'ما عمر القطيع؟',
        status: AgentQuestionStatus.answered,
        answerText: '30 weeks',
      ),
    ],
    events: const [],
  );
  return _FakeHatcheryAgentRepository(
    summary: summary,
    details: details,
    pendingStaffLinks: pendingStaffLinks,
    staffLinks: staffLinks,
  );
}

class _FakeHatcheryAgentRepository extends HatcheryAgentRepository {
  _FakeHatcheryAgentRepository({
    required this.summary,
    required this.details,
    this.pendingStaffLinks = const [],
    this.staffLinks = const [],
  });

  final HatcheryDraftBatchSummary summary;
  final HatcheryDraftBatchDetails details;
  List<TelegramStaffLink> pendingStaffLinks;
  List<TelegramStaffLink> staffLinks;
  AgentSettings settings = const AgentSettings();
  int settingsLoadCount = 0;
  int batchSummaryLoadCount = 0;
  int settingsSaveCount = 0;
  String? approvedRowId;
  String? approvedBy;
  String? rejectedRowId;
  String? rejectedBy;
  String? rejectionReason;
  HatcheryDraftRow? updatedRow;
  final List<_StaffStatusDecision> staffStatusDecisions = [];
  final List<_StaffScopeDecision> staffScopeDecisions = [];

  @override
  Future<AgentSettings> loadSettings() async {
    settingsLoadCount++;
    return settings;
  }

  @override
  Future<HatcheryAgentLinkCatalog> loadLinkCatalog() async {
    return HatcheryAgentLinkCatalog(
      customers: [
        CustomerModel(
          id: 'customer-1',
          name: 'Customer A',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: 'test',
        ),
        CustomerModel(
          id: 'customer-2',
          name: 'Customer B',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: 'test',
        ),
      ],
      flocks: [
        FlockModel(
          id: 'flock-1',
          customerId: 'customer-1',
          flockId: 'Flock 12',
          breed: 'Ross',
          entryDate: DateTime.utc(2025, 12, 1),
        ),
        FlockModel(
          id: 'flock-2',
          customerId: 'customer-2',
          flockId: 'Flock B',
          breed: 'Cobb',
          entryDate: DateTime.utc(2025, 12, 1),
        ),
      ],
      hatcheries: [
        HatcheryModel(
          id: 'hatchery-1',
          customerId: 'customer-1',
          name: 'Main Hatchery',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: 'test',
        ),
        HatcheryModel(
          id: 'hatchery-2',
          customerId: 'customer-2',
          name: 'Second Hatchery',
          createdAt: DateTime.utc(2026, 1, 1),
          createdBy: 'test',
        ),
      ],
    );
  }

  @override
  Future<List<HatcheryDraftBatchSummary>> listBatchSummaries() async {
    batchSummaryLoadCount++;
    return [summary];
  }

  @override
  Future<List<TelegramStaffLink>> listPendingStaffLinks() async {
    return pendingStaffLinks;
  }

  @override
  Future<List<TelegramStaffLink>> listStaffLinks() async => staffLinks;

  @override
  Future<void> saveSettings(AgentSettings settings) async {
    settingsSaveCount++;
    this.settings = settings;
  }

  @override
  Future<HatcheryDraftBatchDetails?> loadBatchDetails(String batchId) async {
    return batchId == summary.id ? details : null;
  }

  @override
  Future<HatcheryDailyRecord> approveDraftRow({
    required String rowId,
    required String approvedBy,
    required DateTime approvedAt,
  }) async {
    approvedRowId = rowId;
    this.approvedBy = approvedBy;
    return HatcheryDailyRecord(
      id: 'record-1',
      sourceDraftRowId: rowId,
      customerId: 'customer-1',
      flockId: 'flock-1',
      stationName: 'Station A',
      breed: 'Ross',
      eggsPlaced: 1000,
      hatchDate: DateTime.utc(2026, 7, 27),
      totalProduction: 850,
      hatchabilityPct: 85,
    );
  }

  @override
  Future<void> rejectDraftRow({
    required String rowId,
    required String rejectedBy,
    required DateTime rejectedAt,
    String? reason,
  }) async {
    rejectedRowId = rowId;
    this.rejectedBy = rejectedBy;
    rejectionReason = reason;
  }

  @override
  Future<void> updateDraftRow(HatcheryDraftRow row) async {
    updatedRow = row;
  }

  @override
  Future<void> setStaffLinkStatus({
    required String linkId,
    required TelegramStaffLinkStatus status,
    required String decidedBy,
    required DateTime decidedAt,
  }) async {
    staffStatusDecisions.add(
      _StaffStatusDecision(
        linkId: linkId,
        status: status,
        decidedBy: decidedBy,
      ),
    );
    pendingStaffLinks = pendingStaffLinks
        .where((link) => link.id != linkId)
        .toList(growable: false);
    staffLinks = staffLinks
        .where((link) => link.id != linkId)
        .toList(growable: false);
  }

  @override
  Future<void> approveStaffLink({
    required String linkId,
    required TelegramAgentAccessRole accessRole,
    required String? customerId,
    required String decidedBy,
    required DateTime decidedAt,
  }) async {
    staffScopeDecisions.add(
      _StaffScopeDecision(
        linkId: linkId,
        accessRole: accessRole,
        customerId: customerId,
        decidedBy: decidedBy,
      ),
    );
    pendingStaffLinks = pendingStaffLinks
        .where((link) => link.id != linkId)
        .toList(growable: false);
  }
}

class _StaffStatusDecision {
  const _StaffStatusDecision({
    required this.linkId,
    required this.status,
    required this.decidedBy,
  });

  final String linkId;
  final TelegramStaffLinkStatus status;
  final String decidedBy;
}

class _StaffScopeDecision {
  const _StaffScopeDecision({
    required this.linkId,
    required this.accessRole,
    required this.customerId,
    required this.decidedBy,
  });

  final String linkId;
  final TelegramAgentAccessRole accessRole;
  final String? customerId;
  final String decidedBy;
}

TelegramStaffLink _pendingStaffLink() {
  return TelegramStaffLink(
    id: 'pending-1',
    telegramUserId: '999',
    telegramChatId: '123',
    displayName: 'New Staff',
    username: 'newstaff',
    status: TelegramStaffLinkStatus.pending,
    createdAt: DateTime.utc(2026, 7, 27, 8),
    updatedAt: DateTime.utc(2026, 7, 27, 9),
  );
}

class _FakeAuthProvider extends AuthProvider {
  _FakeAuthProvider(this.currentUser);

  final UserModel currentUser;

  @override
  UserModel get user => currentUser;
}

UserModel _adminUser() {
  return UserModel(
    id: 'admin-1',
    fullName: 'Admin',
    email: 'admin@example.test',
    role: 'admin',
    status: 'approved',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

UserModel _auditorUser() {
  return UserModel(
    id: 'auditor-1',
    fullName: 'Auditor',
    email: 'auditor@example.test',
    role: 'auditor',
    status: 'approved',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}

UserModel _customerUser() {
  return UserModel(
    id: 'customer-user-1',
    fullName: 'Customer',
    email: 'customer@example.test',
    role: 'customer',
    status: 'approved',
    customerId: 'customer-1',
    createdAt: DateTime.utc(2026, 1, 1),
  );
}
