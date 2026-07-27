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

  @override
  Future<AgentSettings> loadSettings() async => settings;

  @override
  Future<List<HatcheryDraftBatchSummary>> listBatchSummaries() async {
    if (listError case final error?) throw error;
    return summaries;
  }

  @override
  Future<HatcheryDraftBatchDetails?> loadBatchDetails(String batchId) async {
    if (detailError case final error?) throw error;
    return detailsById[batchId];
  }

  @override
  Future<void> saveSettings(AgentSettings settings) async {
    if (saveError case final error?) throw error;
    this.settings = settings;
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
    rows: const [],
    questions: const [],
    events: const [],
  );
}
