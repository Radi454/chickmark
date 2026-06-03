import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../core/security/safe_debug_log.dart';
import '../../../data/models/audit_session_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/audit_session_repository.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../services/supabase/supabase_service.dart';
import 'package:uuid/uuid.dart';

class AuditSessionContext {
  final String customerId;
  final String hatcheryId;
  final String flockId;
  final DateTime date;
  final String breed;
  final int flockAgeWeeks;
  final List<String>? selectedStationKeys;

  const AuditSessionContext({
    required this.customerId,
    required this.hatcheryId,
    required this.flockId,
    required this.date,
    required this.breed,
    this.flockAgeWeeks = 0,
    this.selectedStationKeys,
  });
}

class AuditSessionProvider extends ChangeNotifier {
  final AuditSessionRepository _repository;
  final ActivityLogRepository _activityLogRepository;
  final SupabaseService _supabaseService;
  final Uuid _uuid;

  AuditSessionProvider({
    AuditSessionRepository? repository,
    ActivityLogRepository? activityLogRepository,
    SupabaseService? supabaseService,
    Uuid? uuid,
  }) : _repository = repository ?? AuditSessionRepository(),
       _activityLogRepository =
           activityLogRepository ?? ActivityLogRepository(),
       _supabaseService = supabaseService ?? SupabaseService(),
       _uuid = uuid ?? const Uuid();

  // State
  AuditSessionModel? _currentSession;
  int _currentStationIndex = 0;
  int _targetStationIndex = 0;
  bool _isMovingToStation = false;
  bool _isLoading = false;
  bool _isResumed = false;
  UserModel? _currentUser;
  String? _error;
  List<String>? _selectedStationKeys;
  int _loadOperation = 0;
  bool _isDisposed = false;

  // Getters
  AuditSessionModel? get currentSession => _currentSession;
  int get currentStationIndex => _currentStationIndex;
  bool get isMovingToStation => _isMovingToStation;
  bool get isLoading => _isLoading;
  bool get isResumed => _isResumed;
  bool get isSessionActive =>
      _currentSession != null && _currentSession!.status == 'in_progress';
  bool get isSessionComplete =>
      _currentSession != null && _currentSession!.status == 'completed';
  List<String> get stationsCompleted =>
      _currentSession?.stationsCompleted ?? [];
  List<String> get stationKeys =>
      _currentSession?.selectedStationKeys ??
      (_selectedStationKeys == null
          ? supportedStationKeys
          : normalizeStationKeys(_selectedStationKeys));
  int get stationCount => stationKeys.length;
  bool get isStationCompleted =>
      _currentStationIndex < stationCount &&
      stationsCompleted.contains(stationKeys[_currentStationIndex]);
  String? get error => _error;

  @override
  void dispose() {
    _isDisposed = true;
    super.dispose();
  }

  void _notifyListeners() {
    if (!_isDisposed) notifyListeners();
  }

  bool _isCurrentLoad(int operation) =>
      !_isDisposed && operation == _loadOperation;

  static const Map<String, String> stationDisplayLabels = {
    'egg': AuditTypeLabels.eggStationLabel,
    'chicks': 'Chicks',
    'hatch_analysis_egg_breakouts': 'Hatch Analysis & Egg Breakouts',
    'setters': 'Setters',
    'hatchers': 'Hatchers',
  };

  static const Map<String, String> stationKeyToAuditType = {
    'egg': 'Egg',
    'chicks': 'Chicks',
    'hatch_analysis_egg_breakouts': 'Hatch Analysis & Egg Breakouts',
    'setters': 'Setters',
    'hatchers': 'Hatchers',
  };

  /// Start a new audit session.
  Future<void> startSession({
    required AuditSessionContext context,
    UserModel? currentUser,
  }) async {
    final operation = ++_loadOperation;
    _currentUser = currentUser;
    _selectedStationKeys = normalizeStationKeys(context.selectedStationKeys);
    _isLoading = true;
    _error = null;
    _notifyListeners();

    try {
      final now = DateTime.now();
      final selectedStationKeys = normalizeStationKeys(
        context.selectedStationKeys,
      );
      final session = AuditSessionModel(
        id: _uuid.v4(),
        customerId: context.customerId,
        flockId: context.flockId,
        hatcheryId: context.hatcheryId,
        date: context.date,
        breed: context.breed,
        flockAgeWeeks: context.flockAgeWeeks,
        status: 'in_progress',
        selectedStationKeys: selectedStationKeys,
        stationsCompleted: const [],
        createdBy: currentUser?.id,
        createdAt: now,
        updatedAt: now,
      );

      await _repository.insertSession(session);
      if (!_isCurrentLoad(operation)) return;
      _currentSession = session;
      _currentStationIndex = 0;
      _targetStationIndex = 0;
      _isResumed = false;

      await _safeLogActivity('session_start', session.id);

      unawaited(_supabaseService.syncAuditSession(session.toMap()));
    } catch (e) {
      if (!_isCurrentLoad(operation)) return;
      _error = 'Failed to start visit session';
      safeDebugLog('Error starting session', error: e);
    } finally {
      if (_isCurrentLoad(operation)) {
        _isLoading = false;
        _notifyListeners();
      }
    }
  }

  /// Start a visit, or resume the matching in-progress visit for this context.
  Future<void> startOrResumeSession({
    required AuditSessionContext context,
    UserModel? currentUser,
  }) async {
    final operation = ++_loadOperation;
    _currentUser = currentUser;
    _selectedStationKeys = normalizeStationKeys(context.selectedStationKeys);
    _isLoading = true;
    _error = null;
    _notifyListeners();

    try {
      final existing = await _repository.findInProgressSession(
        customerId: context.customerId,
        flockId: context.flockId,
        hatcheryId: context.hatcheryId,
        date: context.date,
      );
      if (!_isCurrentLoad(operation)) return;
      if (existing != null) {
        _currentSession = existing;
        _selectedStationKeys = normalizeStationKeys(
          existing.selectedStationKeys,
        );
        _isResumed = true;
        _setResumeStationIndex(existing);
        await _safeLogActivity('session_resume', existing.id);
        return;
      }
    } catch (e) {
      if (!_isCurrentLoad(operation)) return;
      _error = 'Failed to resume visit session';
      safeDebugLog('Error finding session to resume', error: e);
      return;
    } finally {
      if (_isCurrentLoad(operation)) {
        _isLoading = false;
        _notifyListeners();
      }
    }

    await startSession(context: context, currentUser: currentUser);
  }

  /// Load a matching in-progress session for Select Stations without creating.
  Future<bool> loadMatchingSessionForStationSelection({
    required AuditSessionContext context,
    UserModel? currentUser,
  }) async {
    final operation = ++_loadOperation;
    _currentUser = currentUser;
    _isLoading = true;
    _error = null;
    _notifyListeners();

    try {
      final existing = await _repository.findInProgressSession(
        customerId: context.customerId,
        flockId: context.flockId,
        hatcheryId: context.hatcheryId,
        date: context.date,
      );
      if (!_isCurrentLoad(operation)) return false;
      if (existing == null) {
        _currentSession = null;
        _currentStationIndex = 0;
        _targetStationIndex = 0;
        _isResumed = false;
        return false;
      }
      _currentSession = existing;
      _selectedStationKeys = normalizeStationKeys(existing.selectedStationKeys);
      _isResumed = true;
      _setResumeStationIndex(existing, initialStationIndex: 0);
      await _safeLogActivity('session_resume', existing.id);
      return true;
    } catch (e) {
      if (_isCurrentLoad(operation)) {
        _error = 'Failed to resume visit session';
        safeDebugLog('Error finding session to resume', error: e);
      }
      return false;
    } finally {
      if (_isCurrentLoad(operation)) {
        _isLoading = false;
        _notifyListeners();
      }
    }
  }

  /// Resume an existing session from its last completed station.
  Future<void> resumeSession(
    String sessionId, {
    int? initialStationIndex,
  }) async {
    final operation = ++_loadOperation;
    _isLoading = true;
    _error = null;
    _notifyListeners();

    try {
      final session = await _repository.getSessionById(sessionId);
      if (!_isCurrentLoad(operation)) return;
      if (session == null) {
        _error = 'Session not found';
        _isLoading = false;
        _notifyListeners();
        return;
      }

      _currentSession = session;
      _selectedStationKeys = normalizeStationKeys(session.selectedStationKeys);
      _isResumed = true;
      _setResumeStationIndex(session, initialStationIndex: initialStationIndex);

      await _safeLogActivity('session_resume', sessionId);
    } catch (e) {
      if (!_isCurrentLoad(operation)) return;
      _error = 'Failed to resume visit session';
      safeDebugLog('Error resuming session', error: e);
    } finally {
      if (_isCurrentLoad(operation)) {
        _isLoading = false;
        _notifyListeners();
      }
    }
  }

  Future<void> updateSelectedStationKeys(
    List<String> selectedStationKeys,
  ) async {
    if (_currentSession == null) return;

    try {
      await _repository.updateSelectedStationKeys(
        _currentSession!.id,
        selectedStationKeys,
      );
      final updated = await _repository.getSessionById(_currentSession!.id);
      if (updated != null) {
        _currentSession = updated;
        _selectedStationKeys = normalizeStationKeys(
          updated.selectedStationKeys,
        );
        _setResumeStationIndex(updated);
        unawaited(_supabaseService.syncAuditSession(updated.toMap()));
      }
      _notifyListeners();
    } catch (e) {
      _error = 'Failed to update visit stations';
      safeDebugLog('Error updating selected station keys', error: e);
    }
  }

  void _setResumeStationIndex(
    AuditSessionModel session, {
    int? initialStationIndex,
  }) {
    final keys = normalizeStationKeys(session.selectedStationKeys);
    if (initialStationIndex != null &&
        initialStationIndex >= 0 &&
        initialStationIndex < keys.length) {
      _currentStationIndex = initialStationIndex;
      _targetStationIndex = initialStationIndex;
      return;
    }

    final completed = session.stationsCompleted;
    if (completed.length >= keys.length) {
      _currentStationIndex = 0;
    } else {
      _currentStationIndex = keys.indexWhere(
        (stationKey) => !completed.contains(stationKey),
      );
      if (_currentStationIndex == -1) {
        _currentStationIndex = 0;
      }
    }
    _targetStationIndex = _currentStationIndex;
  }

  /// Navigate to the next station.
  void goToNextStation() {
    if (_currentStationIndex < stationKeys.length - 1) {
      _targetStationIndex = _currentStationIndex + 1;
      _isMovingToStation = true;
      _notifyListeners();
    }
  }

  /// Navigate to the previous station.
  void goToPreviousStation() {
    if (_currentStationIndex > 0) {
      _targetStationIndex = _currentStationIndex - 1;
      _isMovingToStation = true;
      _notifyListeners();
    }
  }

  /// Navigate directly to a station by index.
  void goToStation(int index) {
    if (index >= 0 && index < stationKeys.length) {
      _targetStationIndex = index;
      _isMovingToStation = true;
      _notifyListeners();
    }
  }

  /// Mark that the navigation transition is complete.
  void stationTransitionComplete() {
    _currentStationIndex = _targetStationIndex;
    _isMovingToStation = false;
    _notifyListeners();
  }

  /// Mark the current station as completed and persist progress.
  Future<void> markCurrentStationCompleted() async {
    if (_currentSession == null || _isLoading) return;

    _isLoading = true;
    _notifyListeners();

    try {
      final stationKey = stationKeys[_currentStationIndex];
      await _repository.markStationCompleted(_currentSession!.id, stationKey);

      final updated = await _repository.getSessionById(_currentSession!.id);
      if (updated != null) {
        _currentSession = updated;
      }

      await _safeLogActivity(
        'station_complete',
        _currentSession!.id,
        detail: stationKey,
      );

      unawaited(_supabaseService.syncAuditSession(_currentSession!.toMap()));
    } catch (e) {
      _error = 'Failed to save station progress';
      safeDebugLog('Error marking station completed', error: e);
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  /// Update session progress with an explicit list of completed station keys.
  Future<void> updateProgress(List<String> completed) async {
    if (_currentSession == null) return;

    try {
      await _repository.updateSessionProgress(_currentSession!.id, completed);
      final updated = await _repository.getSessionById(_currentSession!.id);
      if (updated != null) {
        _currentSession = updated;
      }

      unawaited(_supabaseService.syncAuditSession(_currentSession!.toMap()));

      _notifyListeners();
    } catch (e) {
      _error = 'Failed to save session progress';
      safeDebugLog('Error updating session progress', error: e);
    }
  }

  /// Remove the visible station from completion progress and reopen if needed.
  Future<void> removeCurrentStationCompletion() async {
    if (_currentSession == null) return;
    if (_currentStationIndex < 0 ||
        _currentStationIndex >= stationKeys.length) {
      return;
    }
    final stationKey = stationKeys[_currentStationIndex];
    if (!stationsCompleted.contains(stationKey)) return;
    final nextCompleted = stationsCompleted
        .where((completedKey) => completedKey != stationKey)
        .toList(growable: false);
    await updateProgress(nextCompleted);
  }

  /// Complete the entire visit session.
  Future<void> completeSession() async {
    if (_currentSession == null || _isLoading) return;

    _isLoading = true;
    _notifyListeners();

    try {
      await _repository.updateSessionProgress(
        _currentSession!.id,
        List.from(stationKeys),
      );

      final updated = await _repository.getSessionById(_currentSession!.id);
      if (updated != null) {
        _currentSession = updated;
      }

      await _safeLogActivity('session_complete', _currentSession!.id);

      unawaited(_supabaseService.syncAuditSession(_currentSession!.toMap()));
    } catch (e) {
      _error = 'Failed to complete visit session';
      safeDebugLog('Error completing session', error: e);
    } finally {
      _isLoading = false;
      _notifyListeners();
    }
  }

  /// Load an incomplete session for the home screen resume list.
  Future<List<AuditSessionModel>> loadInProgressSessions() async {
    try {
      return await _repository.getInProgressSessions();
    } catch (e) {
      safeDebugLog('Error loading in-progress sessions', error: e);
      return [];
    }
  }

  /// Load completed sessions for history.
  Future<List<AuditSessionModel>> loadCompletedSessions({
    String? customerId,
    int limit = 50,
    int offset = 0,
  }) async {
    try {
      return await _repository.getCompletedSessions(
        customerId: customerId,
        limit: limit,
        offset: offset,
      );
    } catch (e) {
      safeDebugLog('Error loading completed sessions', error: e);
      return [];
    }
  }

  /// Delete a session.
  Future<void> deleteSession(String sessionId) async {
    try {
      await _repository.deleteSession(sessionId);
      await _logActivity('session_delete', sessionId);
      if (_currentSession?.id == sessionId) {
        _currentSession = null;
        _currentStationIndex = 0;
        _isResumed = false;
        _notifyListeners();
      }
    } catch (e) {
      _error = 'Failed to delete visit session';
      safeDebugLog('Error deleting session', error: e);
    }
  }

  /// Clear the current session from provider state.
  void clearCurrentSession() {
    _currentSession = null;
    _currentStationIndex = 0;
    _targetStationIndex = 0;
    _isMovingToStation = false;
    _isResumed = false;
    _selectedStationKeys = null;
    _error = null;
    _loadOperation++;
    _notifyListeners();
  }

  Future<void> _logActivity(
    String action,
    String sessionId, {
    String? detail,
  }) async {
    final userId = _currentUser?.id;
    if (userId == null || userId.isEmpty) return;
    await _activityLogRepository.log(
      userId,
      action,
      entityType: 'audit_session',
      entityId: sessionId,
      details: detail,
    );
  }

  Future<void> _safeLogActivity(
    String action,
    String sessionId, {
    String? detail,
  }) async {
    try {
      await _logActivity(action, sessionId, detail: detail);
    } catch (e) {
      safeDebugLog('Error logging audit session activity', error: e);
    }
  }
}
