import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';

void main() {
  test('storage enums normalize known and unknown values', () {
    expect(
      AgentSubmissionStatus.fromStorage('waiting_for_staff_answer'),
      AgentSubmissionStatus.waitingForStaffAnswer,
    );
    expect(
      AgentSubmissionStatus.fromStorage('unknown'),
      AgentSubmissionStatus.received,
    );
    expect(
      HatcheryDraftRowStatus.fromStorage('needs_review'),
      HatcheryDraftRowStatus.needsReview,
    );
    expect(
      AgentSourceKind.fromStorage('spreadsheet'),
      AgentSourceKind.spreadsheet,
    );
    expect(
      AgentQuestionStatus.fromStorage('answered'),
      AgentQuestionStatus.answered,
    );
  });

  test('submission round-trips Telegram source metadata', () {
    final submission = HatcheryAgentSubmission(
      id: 'submission-1',
      telegramUpdateId: '100',
      telegramMessageId: '10',
      telegramChatId: '123',
      telegramUserId: '456',
      staffLinkId: 'staff-1',
      sourceKind: AgentSourceKind.pdf,
      sourceText: 'Visible table notes',
      sourceFileName: 'hatch.pdf',
      sourceMimeType: 'application/pdf',
      sourceRemotePath: 'agent/submission-1/hatch.pdf',
      status: AgentSubmissionStatus.waitingForStaffAnswer,
      errorMessage: 'Missing flock age',
      submittedAt: DateTime.utc(2026, 7, 27, 8),
      processedAt: DateTime.utc(2026, 7, 27, 8, 1),
      createdAt: DateTime.utc(2026, 7, 27, 8),
      updatedAt: DateTime.utc(2026, 7, 27, 8, 1),
    );

    final copy = HatcheryAgentSubmission.fromMap(submission.toMap());

    expect(copy.id, 'submission-1');
    expect(copy.sourceKind, AgentSourceKind.pdf);
    expect(copy.status, AgentSubmissionStatus.waitingForStaffAnswer);
    expect(copy.sourceRemotePath, 'agent/submission-1/hatch.pdf');
    expect(copy.submittedAt, DateTime.utc(2026, 7, 27, 8));
  });

  test('question round-trips bilingual prompt and staff answer', () {
    final question = HatcheryAgentQuestion(
      id: 'question-1',
      submissionId: 'submission-1',
      rowOrdinal: 2,
      fieldKey: 'flockAgeWeeks',
      questionTextEn: 'What is the flock age?',
      questionTextAr: 'ما عمر القطيع؟',
      status: AgentQuestionStatus.answered,
      answerText: '30',
      answeredAt: DateTime.utc(2026, 7, 27, 8, 5),
      createdAt: DateTime.utc(2026, 7, 27, 8, 2),
      updatedAt: DateTime.utc(2026, 7, 27, 8, 5),
    );

    final copy = HatcheryAgentQuestion.fromMap(question.toMap());

    expect(copy.rowOrdinal, 2);
    expect(copy.questionTextAr, 'ما عمر القطيع؟');
    expect(copy.status, AgentQuestionStatus.answered);
    expect(copy.answerText, '30');
  });

  test('draft batch round-trips submission and status', () {
    final batch = HatcheryDraftBatch(
      id: 'batch-1',
      submissionId: 'submission-1',
      status: AgentSubmissionStatus.needsAdminReview,
      sourceSummary: 'Two extracted hatchery rows',
      createdAt: DateTime.utc(2026, 7, 27, 8, 1),
      updatedAt: DateTime.utc(2026, 7, 27, 8, 2),
    );

    final copy = HatcheryDraftBatch.fromMap(batch.toMap());

    expect(copy.id, 'batch-1');
    expect(copy.submissionId, 'submission-1');
    expect(copy.status, AgentSubmissionStatus.needsAdminReview);
    expect(copy.sourceSummary, 'Two extracted hatchery rows');
  });

  test('draft row round-trips all hatchery extraction fields', () {
    final row = HatcheryDraftRow(
      id: 'row-1',
      batchId: 'batch-1',
      rowOrdinal: 1,
      status: HatcheryDraftRowStatus.needsReview,
      customerId: 'customer-1',
      customerName: 'Al Salehia',
      flockId: 'flock-1',
      flockName: 'Ross 1',
      hatcheryId: 'hatchery-1',
      stationName: 'Station A',
      breed: 'Ross',
      eggsPlaced: 19200,
      productionDate: DateTime.utc(2025, 12, 9),
      placementDate: DateTime.utc(2025, 12, 11),
      eggWeightG: 67,
      fertilityPct: 92,
      transferWeightG: 63,
      setterNumber: '6',
      hatcherNumber: '6',
      hatchDate: DateTime.utc(2026, 1, 1),
      healthyChicks: 11400,
      secondGradeChicks: 105,
      condemnedChicks: 13,
      totalProduction: 11518,
      hatchabilityPct: 59.989583333333336,
      confidencePct: 94,
      extractionJson: '{"source":"table"}',
      warningsJson: '[{"kind":"historical_change"}]',
      proposedFlockAgeWeeks: 30,
      approvedRecordId: 'record-1',
      reviewedBy: 'admin-1',
      reviewedAt: DateTime.utc(2026, 7, 27, 9),
      createdAt: DateTime.utc(2026, 7, 27, 8),
      updatedAt: DateTime.utc(2026, 7, 27, 9),
    );

    final copy = HatcheryDraftRow.fromMap(row.toMap());

    expect(copy.customerName, 'Al Salehia');
    expect(copy.customerId, 'customer-1');
    expect(copy.eggsPlaced, 19200);
    expect(copy.productionDate, DateTime.utc(2025, 12, 9));
    expect(copy.totalProduction, 11518);
    expect(copy.hatchabilityPct, closeTo(59.9895, 0.0001));
    expect(copy.proposedFlockAgeWeeks, 30);
    expect(copy.status, HatcheryDraftRowStatus.needsReview);
  });

  test('audit event round-trips actor and evidence details', () {
    final event = HatcheryAgentAuditEvent(
      id: 'event-1',
      submissionId: 'submission-1',
      rowId: 'row-1',
      actorType: 'agent',
      actorId: 'extractor',
      eventType: 'row_extracted',
      detailsJson: '{"confidencePct":94}',
      createdAt: DateTime.utc(2026, 7, 27, 8, 1),
    );

    final copy = HatcheryAgentAuditEvent.fromMap(event.toMap());

    expect(copy.actorType, 'agent');
    expect(copy.eventType, 'row_extracted');
    expect(copy.detailsJson, '{"confidencePct":94}');
  });

  test('daily record round-trips approved hatchery values', () {
    final record = HatcheryDailyRecord(
      id: 'record-1',
      sourceDraftRowId: 'row-1',
      customerId: 'customer-1',
      flockId: 'flock-1',
      hatcheryId: 'hatchery-1',
      stationName: 'Station A',
      breed: 'Ross',
      eggsPlaced: 1000,
      hatchDate: DateTime.utc(2026, 7, 27),
      totalProduction: 850,
      hatchabilityPct: 85,
      approvedBy: 'admin-1',
      approvedAt: DateTime.utc(2026, 7, 27, 9),
      createdAt: DateTime.utc(2026, 7, 27, 9),
      updatedAt: DateTime.utc(2026, 7, 27, 9),
    );

    final copy = HatcheryDailyRecord.fromMap(record.toMap());

    expect(copy.sourceDraftRowId, 'row-1');
    expect(copy.stationName, 'Station A');
    expect(copy.hatchDate, DateTime.utc(2026, 7, 27));
    expect(copy.hatchabilityPct, 85);
    expect(copy.approvedBy, 'admin-1');
  });

  test('historical point maps the comparable approved record', () {
    final point = HatcheryHistoricalPoint.fromMap(const {
      'id': 'record-1',
      'hatchDate': '2026-07-20T00:00:00.000Z',
      'hatchabilityPct': 82.5,
    });

    expect(point.recordId, 'record-1');
    expect(point.hatchDate, DateTime.utc(2026, 7, 20));
    expect(point.hatchabilityPct, 82.5);
  });

  test('agent settings round-trip enablement and review thresholds', () {
    final settings = AgentSettings(
      telegramEnabled: false,
      hatchabilityWarningThresholdPoints: 4,
      minimumReadyConfidencePct: 90,
      updatedAt: DateTime.utc(2026, 7, 27),
    );

    final copy = AgentSettings.fromMap(settings.toMap());

    expect(copy.id, 1);
    expect(copy.telegramEnabled, isFalse);
    expect(copy.hatchabilityWarningThresholdPoints, 4);
    expect(copy.minimumReadyConfidencePct, 90);
  });
}
