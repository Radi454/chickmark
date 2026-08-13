import 'package:flutter/foundation.dart';

import '../../../data/models/agent_intake_models.dart';
import '../../../data/models/agent_diagnostic_models.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../data/models/hatchery_agent_models.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/agent_intake_repository.dart';
import '../../../data/repositories/agent_diagnostic_repository.dart';
import '../../../data/repositories/hatchery_agent_repository.dart';
import '../../../services/supabase/agent_intake_approval_service.dart';
import '../../../services/supabase/telegram_agent_settings_service.dart';

class AgentMonitorProvider extends ChangeNotifier {
  AgentMonitorProvider({
    required UserModel? currentUser,
    HatcheryAgentRepository? repository,
    AgentIntakeRepository? intakeRepository,
    AgentDiagnosticRepository? diagnosticRepository,
    AgentIntakeApprovalPort? approvalPort,
    TelegramAgentSettingsPort? telegramSettingsPort,
  }) : _currentUser = currentUser,
       _repository = repository ?? HatcheryAgentRepository(),
       _intakeRepository = intakeRepository ?? AgentIntakeRepository(),
       _diagnosticRepository =
           diagnosticRepository ?? AgentDiagnosticRepository(),
       _approvalPort = approvalPort ?? AgentIntakeApprovalService(),
       _telegramSettingsPort =
           telegramSettingsPort ?? TelegramAgentSettingsService();

  final UserModel? _currentUser;
  final HatcheryAgentRepository _repository;
  final AgentIntakeRepository _intakeRepository;
  final AgentDiagnosticRepository _diagnosticRepository;
  final AgentIntakeApprovalPort _approvalPort;
  final TelegramAgentSettingsPort _telegramSettingsPort;

  bool _isLoading = false;
  bool _isUpdatingTelegram = false;
  int _telegramUpdateToken = 0;
  bool _hasLoaded = false;
  String? _error;
  AgentSettings _settings = const AgentSettings();
  HatcheryAgentLinkCatalog _linkCatalog = const HatcheryAgentLinkCatalog();
  List<TelegramStaffLink> _pendingStaffLinks = const [];
  List<TelegramStaffLink> _staffLinks = const [];
  List<HatcheryDraftBatchSummary> _batches = const [];
  HatcheryDraftBatchDetails? _selectedBatch;
  List<AgentIntakeSession> _intakes = const [];
  AgentIntakeDetails? _selectedIntake;
  List<AuditSessionModel> _matchingAuditSessions = const [];
  AgentHealthSnapshot _health = const AgentHealthSnapshot();
  List<AgentConversationDiagnostic> _conversationDiagnostics = const [];

  bool get isLoading => _isLoading;
  bool get isUpdatingTelegram => _isUpdatingTelegram;
  bool get hasLoaded => _hasLoaded;
  String? get error => _error;
  AgentSettings get settings => _settings;
  HatcheryAgentLinkCatalog get linkCatalog => _linkCatalog;
  List<TelegramStaffLink> get pendingStaffLinks => _pendingStaffLinks;
  List<TelegramStaffLink> get staffLinks => _staffLinks;
  List<HatcheryDraftBatchSummary> get batches => _batches;
  HatcheryDraftBatchDetails? get selectedBatch => _selectedBatch;
  List<AgentIntakeSession> get intakes => _intakes;
  AgentIntakeDetails? get selectedIntake => _selectedIntake;
  List<AuditSessionModel> get matchingAuditSessions => _matchingAuditSessions;
  AgentHealthSnapshot get health => _health;
  List<AgentConversationDiagnostic> get conversationDiagnostics =>
      _conversationDiagnostics;
  bool get canAccessMonitor =>
      _currentUser?.isApproved == true && _currentUser?.isAdmin == true;

  Future<void> load() async {
    if (!canAccessMonitor) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      _settings = await _repository.loadSettings();
      _linkCatalog = await _repository.loadLinkCatalog();
      _pendingStaffLinks = List.unmodifiable(
        await _repository.listPendingStaffLinks(),
      );
      _staffLinks = List.unmodifiable(await _repository.listStaffLinks());
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
    }
    try {
      await _loadIntakes();
    } catch (_) {
      _error ??= 'Unable to load conversational intake data. Please try again.';
    }
    try {
      _health = await _diagnosticRepository.loadHealth();
      _conversationDiagnostics = List.unmodifiable(
        await _diagnosticRepository.listConversationDiagnostics(),
      );
    } catch (_) {
      _error ??= 'Unable to load agent health data. Please try again.';
    }
    _isLoading = false;
    _hasLoaded = true;
    notifyListeners();
  }

  Future<void> selectBatch(String batchId) async {
    if (!canAccessMonitor) return;
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
    if (!canAccessMonitor) return;
    final batchId = _selectedBatch?.batch.id;
    if (batchId == null) return;
    await selectBatch(batchId);
  }

  Future<void> selectIntake(String intakeId) async {
    if (!canAccessMonitor) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final details = await _intakeRepository.loadDetails(intakeId);
      _selectedIntake = details;
      _matchingAuditSessions = details == null
          ? const []
          : List.unmodifiable(
              await _intakeRepository.listMatchingAuditSessions(
                details.session,
              ),
            );
    } catch (_) {
      _error = 'Unable to load this intake. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> saveIntakeValue(String fieldKey, Object? value) {
    return _runIntakeAction(
      action: (intake) => _intakeRepository.updateValue(
        intakeId: intake.session.id,
        fieldKey: fieldKey,
        value: value,
      ),
      errorMessage: 'Unable to save this intake value. Please try again.',
      keepSelection: true,
    );
  }

  Future<void> approveIntake({String? targetSessionId}) {
    return _runIntakeAction(
      action: (intake) async {
        final result = await _approvalPort.approve(
          intakeId: intake.session.id,
          expectedSummaryVersion: intake.session.summaryVersion,
          targetSessionId: targetSessionId,
        );
        await _intakeRepository.markApproved(
          intakeId: intake.session.id,
          auditSessionId: result.auditSessionId,
          panelRowId: result.panelRowId,
          reviewedBy: _currentUser!.id,
        );
      },
      errorMessage: 'Unable to approve this intake. Please try again.',
      keepSelection: false,
    );
  }

  Future<void> rejectIntake(String reason) async {
    final normalized = reason.trim();
    if (normalized.isEmpty) {
      _error = 'Enter a rejection reason.';
      notifyListeners();
      return;
    }
    await _runIntakeAction(
      action: (intake) => _intakeRepository.reject(
        intakeId: intake.session.id,
        reason: normalized,
        reviewedBy: _currentUser!.id,
      ),
      errorMessage: 'Unable to reject this intake. Please try again.',
      keepSelection: false,
    );
  }

  Future<void> setTelegramEnabled(bool enabled) async {
    if (!canAccessMonitor ||
        _isUpdatingTelegram ||
        enabled == _settings.telegramEnabled) {
      return;
    }
    _error = null;
    final requested = AgentSettings(
      id: _settings.id,
      telegramEnabled: enabled,
      hatchabilityWarningThresholdPoints:
          _settings.hatchabilityWarningThresholdPoints,
      minimumReadyConfidencePct: _settings.minimumReadyConfidencePct,
      updatedAt: DateTime.now().toUtc(),
    );
    final token = ++_telegramUpdateToken;
    _isUpdatingTelegram = true;
    notifyListeners();
    try {
      final confirmed = await _telegramSettingsPort.confirm(requested);
      if (token != _telegramUpdateToken) return;
      try {
        await _repository.saveConfirmedSettings(confirmed);
      } catch (_) {
        if (token != _telegramUpdateToken) return;
        _settings = confirmed;
        _error =
            'Telegram updated, but the local cache could not be refreshed.';
        return;
      }
      if (token == _telegramUpdateToken) {
        _settings = confirmed;
      }
    } catch (_) {
      if (token == _telegramUpdateToken) {
        _error = 'Unable to update Telegram agent. Please try again.';
      }
    } finally {
      if (token == _telegramUpdateToken) {
        _isUpdatingTelegram = false;
        notifyListeners();
      }
    }
  }

  Future<void> approveStaffLink({
    required String linkId,
    required TelegramAgentAccessRole accessRole,
    required String? customerId,
  }) async {
    if (!canAccessMonitor) return;
    final normalizedCustomerId = customerId?.trim();
    if (accessRole == TelegramAgentAccessRole.customer &&
        (normalizedCustomerId == null || normalizedCustomerId.isEmpty)) {
      _error = 'Select a customer before allowing access.';
      notifyListeners();
      return;
    }
    if (accessRole == TelegramAgentAccessRole.admin &&
        normalizedCustomerId != null &&
        normalizedCustomerId.isNotEmpty) {
      _error = 'Admin access cannot be limited to one customer.';
      notifyListeners();
      return;
    }

    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.approveStaffLink(
        linkId: linkId,
        accessRole: accessRole,
        customerId: normalizedCustomerId,
        decidedBy: _currentUser!.id,
        decidedAt: DateTime.now().toUtc(),
      );
      await _reloadStaffLinks();
    } catch (_) {
      _error = 'Unable to update Telegram staff access. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> revokeStaffLink(String linkId) {
    return _setStaffLinkStatus(
      linkId: linkId,
      status: TelegramStaffLinkStatus.revoked,
    );
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
    if (!canAccessMonitor) return;
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

  Future<void> _runIntakeAction({
    required Future<void> Function(AgentIntakeDetails intake) action,
    required String errorMessage,
    required bool keepSelection,
  }) async {
    if (!canAccessMonitor) return;
    final selected = _selectedIntake;
    if (selected == null) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await action(selected);
      final selectedId = keepSelection ? selected.session.id : null;
      _intakes = List.unmodifiable(
        await _intakeRepository.listAwaitingReview(),
      );
      final nextId =
          selectedId != null &&
              _intakes.any((intake) => intake.id == selectedId)
          ? selectedId
          : (_intakes.isEmpty ? null : _intakes.first.id);
      if (nextId == null) {
        _selectedIntake = null;
        _matchingAuditSessions = const [];
      } else {
        _selectedIntake = await _intakeRepository.loadDetails(nextId);
        final next = _selectedIntake;
        _matchingAuditSessions = next == null
            ? const []
            : List.unmodifiable(
                await _intakeRepository.listMatchingAuditSessions(next.session),
              );
      }
    } catch (_) {
      _error = errorMessage;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _loadIntakes() async {
    _intakes = List.unmodifiable(await _intakeRepository.listAwaitingReview());
    final selectedId = _selectedIntake?.session.id;
    final nextId =
        selectedId != null && _intakes.any((intake) => intake.id == selectedId)
        ? selectedId
        : (_intakes.isEmpty ? null : _intakes.first.id);
    if (nextId == null) {
      _selectedIntake = null;
      _matchingAuditSessions = const [];
      return;
    }
    _selectedIntake = await _intakeRepository.loadDetails(nextId);
    final selected = _selectedIntake;
    _matchingAuditSessions = selected == null
        ? const []
        : List.unmodifiable(
            await _intakeRepository.listMatchingAuditSessions(selected.session),
          );
  }

  Future<void> _setStaffLinkStatus({
    required String linkId,
    required TelegramStaffLinkStatus status,
  }) async {
    if (!canAccessMonitor) return;
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      await _repository.setStaffLinkStatus(
        linkId: linkId,
        status: status,
        decidedBy: _currentUser!.id,
        decidedAt: DateTime.now().toUtc(),
      );
      await _reloadStaffLinks();
    } catch (_) {
      _error = 'Unable to update Telegram staff access. Please try again.';
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  Future<void> _reloadStaffLinks() async {
    _pendingStaffLinks = List.unmodifiable(
      await _repository.listPendingStaffLinks(),
    );
    _staffLinks = List.unmodifiable(await _repository.listStaffLinks());
  }
}
