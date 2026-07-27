import 'package:flutter/foundation.dart';

import '../../../data/models/hatchery_agent_models.dart';
import '../../../data/repositories/hatchery_agent_repository.dart';

class AgentMonitorProvider extends ChangeNotifier {
  AgentMonitorProvider({HatcheryAgentRepository? repository})
    : _repository = repository ?? HatcheryAgentRepository();

  final HatcheryAgentRepository _repository;

  bool _isLoading = false;
  String? _error;
  AgentSettings _settings = const AgentSettings();
  List<HatcheryDraftBatchSummary> _batches = const [];
  HatcheryDraftBatchDetails? _selectedBatch;

  bool get isLoading => _isLoading;
  String? get error => _error;
  AgentSettings get settings => _settings;
  List<HatcheryDraftBatchSummary> get batches => _batches;
  HatcheryDraftBatchDetails? get selectedBatch => _selectedBatch;

  Future<void> load() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _settings = await _repository.loadSettings();
      _batches = List.unmodifiable(await _repository.listBatchSummaries());
      final selectedId = _selectedBatch?.batch.id;
      final selectedStillExists =
          selectedId != null && _batches.any((batch) => batch.id == selectedId);
      final batchId = selectedStillExists
          ? selectedId
          : (_batches.isEmpty ? null : _batches.first.id);
      _selectedBatch = batchId == null
          ? null
          : await _repository.loadBatchDetails(batchId);
    } catch (_) {
      _error = 'Unable to load agent data. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> selectBatch(String batchId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _selectedBatch = await _repository.loadBatchDetails(batchId);
    } catch (_) {
      _error = 'Unable to load this draft. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> refreshSelected() async {
    final batchId = _selectedBatch?.batch.id;
    if (batchId == null) return;
    await selectBatch(batchId);
  }

  Future<void> setTelegramEnabled(bool enabled) async {
    _error = null;
    final nextSettings = AgentSettings(
      id: _settings.id,
      telegramEnabled: enabled,
      hatchabilityWarningThresholdPoints:
          _settings.hatchabilityWarningThresholdPoints,
      minimumReadyConfidencePct: _settings.minimumReadyConfidencePct,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await _repository.saveSettings(nextSettings);
      _settings = nextSettings;
    } catch (_) {
      _error = 'Unable to update Telegram agent. Please try again.';
    }
    notifyListeners();
  }

  Future<void> approveRow(String rowId, String adminUserId) {
    return _runRowAction(
      action: () async {
        await _repository.approveDraftRow(
          rowId: rowId,
          approvedBy: adminUserId,
          approvedAt: DateTime.now().toUtc(),
        );
      },
      errorMessage: 'Unable to approve this row. Please try again.',
    );
  }

  Future<void> rejectRow(String rowId, String adminUserId, {String? reason}) {
    return _runRowAction(
      action: () => _repository.rejectDraftRow(
        rowId: rowId,
        rejectedBy: adminUserId,
        rejectedAt: DateTime.now().toUtc(),
        reason: reason,
      ),
      errorMessage: 'Unable to reject this row. Please try again.',
    );
  }

  Future<void> saveRowEdit(HatcheryDraftRow row) {
    return _runRowAction(
      action: () => _repository.updateDraftRow(row),
      errorMessage: 'Unable to save this row. Please try again.',
    );
  }

  Future<void> _runRowAction({
    required Future<void> Function() action,
    required String errorMessage,
  }) async {
    final batchId = _selectedBatch?.batch.id;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await action();
      _batches = List.unmodifiable(await _repository.listBatchSummaries());
      if (batchId != null) {
        _selectedBatch = await _repository.loadBatchDetails(batchId);
      }
    } catch (_) {
      _error = errorMessage;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
