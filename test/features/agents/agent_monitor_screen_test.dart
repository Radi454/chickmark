import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/hatchery_agent_repository.dart';
import 'package:hatchaudit/features/agents/providers/agent_monitor_provider.dart';
import 'package:hatchaudit/features/agents/screens/agent_monitor_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Agent Monitor shows batch list and row warnings', (
    tester,
  ) async {
    final provider = AgentMonitorProvider(
      repository: _repositoryWithOneWarning(),
    );

    await _pumpMonitor(tester, provider: provider, user: _adminUser());

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
    final provider = AgentMonitorProvider(
      repository: _repositoryWithOneWarning(),
    );

    await _pumpMonitor(tester, provider: provider, user: _adminUser());

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Agent Monitor'), findsOneWidget);
  });

  testWidgets('admin approval action approves the selected draft row', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning();
    final provider = AgentMonitorProvider(repository: repository);
    await _pumpMonitor(tester, provider: provider, user: _adminUser());
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.text('Approve'));
    await tester.tap(find.text('Approve'));
    await tester.pumpAndSettle();

    expect(repository.approvedRowId, 'row-1');
    expect(repository.approvedBy, 'admin-1');
  });

  testWidgets('customer users do not receive draft row actions', (
    tester,
  ) async {
    final provider = AgentMonitorProvider(
      repository: _repositoryWithOneWarning(),
    );
    await _pumpMonitor(tester, provider: provider, user: _customerUser());
    await tester.pumpAndSettle();

    expect(find.text('Edit'), findsNothing);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reject'), findsNothing);
  });

  testWidgets('reject action forwards an optional admin reason', (
    tester,
  ) async {
    final repository = _repositoryWithOneWarning();
    final provider = AgentMonitorProvider(repository: repository);
    await _pumpMonitor(tester, provider: provider, user: _adminUser());
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
    final provider = AgentMonitorProvider(repository: repository);
    await _pumpMonitor(tester, provider: provider, user: _adminUser());
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
}

Future<void> _pumpMonitor(
  WidgetTester tester, {
  required AgentMonitorProvider provider,
  required UserModel user,
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
          ChangeNotifierProvider<AgentMonitorProvider>.value(value: provider),
          ChangeNotifierProvider<AuthProvider>(
            create: (_) => _FakeAuthProvider(user),
          ),
        ],
        child: const AgentMonitorScreen(),
      ),
    ),
  );
}

_FakeHatcheryAgentRepository _repositoryWithOneWarning() {
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
  return _FakeHatcheryAgentRepository(summary: summary, details: details);
}

class _FakeHatcheryAgentRepository extends HatcheryAgentRepository {
  _FakeHatcheryAgentRepository({required this.summary, required this.details});

  final HatcheryDraftBatchSummary summary;
  final HatcheryDraftBatchDetails details;
  String? approvedRowId;
  String? approvedBy;
  String? rejectedRowId;
  String? rejectedBy;
  String? rejectionReason;
  HatcheryDraftRow? updatedRow;

  @override
  Future<AgentSettings> loadSettings() async => const AgentSettings();

  @override
  Future<List<HatcheryDraftBatchSummary>> listBatchSummaries() async {
    return [summary];
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
