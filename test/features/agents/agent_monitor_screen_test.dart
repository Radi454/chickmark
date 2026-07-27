import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/data/repositories/hatchery_agent_repository.dart';
import 'package:hatchaudit/features/agents/providers/agent_monitor_provider.dart';
import 'package:hatchaudit/features/agents/screens/agent_monitor_screen.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('Agent Monitor shows batch list and row warnings', (
    tester,
  ) async {
    final provider = AgentMonitorProvider(
      repository: _repositoryWithOneWarning(),
    );

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<AgentMonitorProvider>.value(
          value: provider,
          child: const AgentMonitorScreen(),
        ),
      ),
    );

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

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        home: ChangeNotifierProvider<AgentMonitorProvider>.value(
          value: provider,
          child: const AgentMonitorScreen(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Agent Monitor'), findsOneWidget);
  });
}

HatcheryAgentRepository _repositoryWithOneWarning() {
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
}
