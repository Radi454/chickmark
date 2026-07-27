import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/hatchery_agent_models.dart';
import 'package:hatchaudit/data/repositories/hatchery_agent_repository.dart';
import 'package:hatchaudit/features/agents/providers/agent_monitor_provider.dart';

void main() {
  test('load exposes newest batch summaries', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-new', submittedAt: DateTime.utc(2026, 7, 27)),
        _summary(id: 'batch-old', submittedAt: DateTime.utc(2026, 7, 26)),
      ],
    );
    final provider = AgentMonitorProvider(repository: repository);

    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.batches.map((batch) => batch.id), [
      'batch-new',
      'batch-old',
    ]);
  });

  test('load exposes the persisted Telegram setting', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      settings: const AgentSettings(telegramEnabled: false),
    );
    final provider = AgentMonitorProvider(repository: repository);

    await provider.load();

    expect(provider.settings.telegramEnabled, isFalse);
  });

  test('selectBatch exposes the requested batch details', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      detailsById: {'batch-1': _details('batch-1')},
    );
    final provider = AgentMonitorProvider(repository: repository);

    await provider.selectBatch('batch-1');

    expect(provider.selectedBatch?.batch.id, 'batch-1');
  });

  test('load selects the newest batch when none is selected', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-new', submittedAt: DateTime.utc(2026, 7, 27)),
      ],
      detailsById: {'batch-new': _details('batch-new')},
    );
    final provider = AgentMonitorProvider(repository: repository);

    await provider.load();

    expect(provider.selectedBatch?.batch.id, 'batch-new');
  });

  test('setTelegramEnabled persists and exposes the new setting', () async {
    final repository = _FakeHatcheryAgentRepository(summaries: const []);
    final provider = AgentMonitorProvider(repository: repository);
    await provider.load();

    await provider.setTelegramEnabled(false);

    expect(provider.settings.telegramEnabled, isFalse);
    expect(repository.settings.telegramEnabled, isFalse);
  });

  test('load exposes a readable error when the repository fails', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      listError: StateError('database unavailable'),
    );
    final provider = AgentMonitorProvider(repository: repository);

    await provider.load();

    expect(provider.isLoading, isFalse);
    expect(provider.error, 'Unable to load agent data. Please try again.');
  });

  test('failed Telegram update keeps the persisted setting', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      saveError: StateError('write failed'),
    );
    final provider = AgentMonitorProvider(repository: repository);
    await provider.load();

    await provider.setTelegramEnabled(false);

    expect(provider.settings.telegramEnabled, isTrue);
    expect(
      provider.error,
      'Unable to update Telegram agent. Please try again.',
    );
  });

  test(
    'refreshSelected replaces the selected batch with fresh details',
    () async {
      final detailsById = <String, HatcheryDraftBatchDetails>{
        'batch-1': _details('batch-1'),
      };
      final repository = _FakeHatcheryAgentRepository(
        summaries: const [],
        detailsById: detailsById,
      );
      final provider = AgentMonitorProvider(repository: repository);
      await provider.selectBatch('batch-1');
      detailsById['batch-1'] = _details(
        'batch-1',
        status: AgentSubmissionStatus.needsAdminReview,
      );

      await provider.refreshSelected();

      expect(
        provider.selectedBatch?.batch.status,
        AgentSubmissionStatus.needsAdminReview,
      );
    },
  );

  test('selectBatch exposes a readable error when details fail', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: const [],
      detailError: StateError('read failed'),
    );
    final provider = AgentMonitorProvider(repository: repository);

    await provider.selectBatch('batch-1');

    expect(provider.isLoading, isFalse);
    expect(provider.error, 'Unable to load this draft. Please try again.');
  });

  test(
    'approveRow approves then reloads selected details and summaries',
    () async {
      final repository = _FakeHatcheryAgentRepository(
        summaries: [
          _summary(id: 'batch-1', submittedAt: DateTime.utc(2026, 7, 27)),
        ],
        detailsById: {'batch-1': _details('batch-1')},
      );
      final provider = AgentMonitorProvider(repository: repository);
      await provider.load();
      final initialDetailLoads = repository.detailLoadCount;
      final initialSummaryLoads = repository.summaryLoadCount;

      await provider.approveRow('row-1', 'admin-1');

      expect(repository.approvedRowId, 'row-1');
      expect(repository.approvedBy, 'admin-1');
      expect(repository.detailLoadCount, initialDetailLoads + 1);
      expect(repository.summaryLoadCount, initialSummaryLoads + 1);
    },
  );

  test('rejectRow forwards its reason then refreshes monitor data', () async {
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-1', submittedAt: DateTime.utc(2026, 7, 27)),
      ],
      detailsById: {'batch-1': _details('batch-1')},
    );
    final provider = AgentMonitorProvider(repository: repository);
    await provider.load();

    await provider.rejectRow('row-1', 'admin-1', reason: 'Wrong flock');

    expect(repository.rejectedRowId, 'row-1');
    expect(repository.rejectedBy, 'admin-1');
    expect(repository.rejectionReason, 'Wrong flock');
    expect(repository.detailLoadCount, 2);
    expect(repository.summaryLoadCount, 2);
  });

  test('saveRowEdit persists the row then refreshes monitor data', () async {
    final row = _row('row-1');
    final repository = _FakeHatcheryAgentRepository(
      summaries: [
        _summary(id: 'batch-1', submittedAt: DateTime.utc(2026, 7, 27)),
      ],
      detailsById: {
        'batch-1': _details('batch-1', rows: [row]),
      },
    );
    final provider = AgentMonitorProvider(repository: repository);
    await provider.load();
    final edited = row.copyWith(stationName: 'Station B');

    await provider.saveRowEdit(edited);

    expect(repository.updatedRow?.stationName, 'Station B');
    expect(repository.detailLoadCount, 2);
    expect(repository.summaryLoadCount, 2);
  });
}

class _FakeHatcheryAgentRepository extends HatcheryAgentRepository {
  _FakeHatcheryAgentRepository({
    required this.summaries,
    this.settings = const AgentSettings(),
    this.detailsById = const {},
    this.listError,
    this.saveError,
    this.detailError,
  });

  final List<HatcheryDraftBatchSummary> summaries;
  AgentSettings settings;
  final Map<String, HatcheryDraftBatchDetails> detailsById;
  final Object? listError;
  final Object? saveError;
  final Object? detailError;
  int summaryLoadCount = 0;
  int detailLoadCount = 0;
  String? approvedRowId;
  String? approvedBy;
  String? rejectedRowId;
  String? rejectedBy;
  String? rejectionReason;
  HatcheryDraftRow? updatedRow;

  @override
  Future<AgentSettings> loadSettings() async => settings;

  @override
  Future<List<HatcheryDraftBatchSummary>> listBatchSummaries() async {
    if (listError case final error?) throw error;
    summaryLoadCount++;
    return summaries;
  }

  @override
  Future<HatcheryDraftBatchDetails?> loadBatchDetails(String batchId) async {
    if (detailError case final error?) throw error;
    detailLoadCount++;
    return detailsById[batchId];
  }

  @override
  Future<void> saveSettings(AgentSettings settings) async {
    if (saveError case final error?) throw error;
    this.settings = settings;
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
      approvedBy: approvedBy,
      approvedAt: approvedAt,
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

HatcheryDraftBatchSummary _summary({
  required String id,
  required DateTime submittedAt,
}) {
  return HatcheryDraftBatchSummary(
    id: id,
    submissionId: 'submission-$id',
    status: AgentSubmissionStatus.draftReady,
    submittedAt: submittedAt,
    sourceKind: AgentSourceKind.text,
    rowCount: 1,
    needsReviewCount: 0,
    approvedCount: 0,
    rejectedCount: 0,
  );
}

HatcheryDraftBatchDetails _details(
  String batchId, {
  AgentSubmissionStatus status = AgentSubmissionStatus.draftReady,
  List<HatcheryDraftRow> rows = const [],
}) {
  return HatcheryDraftBatchDetails(
    submission: HatcheryAgentSubmission(
      id: 'submission-$batchId',
      sourceKind: AgentSourceKind.text,
      status: status,
      submittedAt: DateTime.utc(2026, 7, 27),
    ),
    batch: HatcheryDraftBatch(
      id: batchId,
      submissionId: 'submission-$batchId',
      status: status,
    ),
    rows: rows,
    questions: const [],
    events: const [],
  );
}

HatcheryDraftRow _row(String id) {
  return HatcheryDraftRow(
    id: id,
    batchId: 'batch-1',
    rowOrdinal: 1,
    status: HatcheryDraftRowStatus.needsReview,
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
