import 'dart:async';
import 'package:flutter/foundation.dart';

import '../../../data/models/audit_session_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/activity_log_repository.dart';
import '../../../data/repositories/audit_session_repository.dart';
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

  static const Map<String, String> stationDisplayLabels = {
    'egg_storage': 'Egg Storage & Handling',
    'chick_quality': 'Chick Quality',
    'hatch_analysis': 'Hatch Analysis',
    'setter_optimizing': 'Setter Optimizing',
    'hatcher_optimizing': 'Hatcher Optimizing',
  };

  static const Map<String, String> stationKeyToAuditType = {
    'egg_storage': 'Egg Storage',
    'chick_quality': 'Chick Quality',
    'hatch_analysis': 'Hatch Analysis',
    'setter_optimizing': 'Setter Optimizing',
    'hatcher_optimizing': 'Hatcher Optimizing',
  };

  /// Start a new audit session.
  Future<void> startSession({
    required AuditSessionContext context,
    UserModel? currentUser,
  }) async {
    _currentUser = currentUser;
    _selectedStationKeys = normalizeStationKeys(context.selectedStationKeys);
    _isLoading = true;
    _error = null;
    notifyListeners();

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
      _currentSession = session;
      _currentStationIndex = 0;
      _isResumed = false;

      await _logActivity('session_start', session.id);

      unawaited(_supabaseService.syncAuditSession(session.toMap()));
    } catch (e) {
      _error = 'Failed to start visit session';
      if (kDebugMode) print('Error starting session: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Resume an existing session from its last completed station.
  Future<void> resumeSession(String sessionId) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final session = await _repository.getSessionById(sessionId);
      if (session == null) {
        _error = 'Session not found';
        _isLoading = false;
        notifyListeners();
        return;
      }

      _currentSession = session;
      _isResumed = true;

      final completed = session.stationsCompleted;
      if (completed.length >= stationKeys.length) {
        _currentStationIndex = stationKeys.length - 1;
      } else {
        _currentStationIndex = stationKeys.indexWhere(
          (stationKey) => !completed.contains(stationKey),
        );
        if (_currentStationIndex == -1) {
          _currentStationIndex = 0;
        }
      }

      await _logActivity('session_resume', sessionId);
    } catch (e) {
      _error = 'Failed to resume visit session';
      if (kDebugMode) print('Error resuming session: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Navigate to the next station.
  void goToNextStation() {
    if (_currentStationIndex < stationKeys.length - 1) {
      _targetStationIndex = _currentStationIndex + 1;
      _isMovingToStation = true;
      notifyListeners();
    }
  }

  /// Navigate to the previous station.
  void goToPreviousStation() {
    if (_currentStationIndex > 0) {
      _targetStationIndex = _currentStationIndex - 1;
      _isMovingToStation = true;
      notifyListeners();
    }
  }

  /// Navigate directly to a station by index.
  void goToStation(int index) {
    if (index >= 0 && index < stationKeys.length) {
      _targetStationIndex = index;
      _isMovingToStation = true;
      notifyListeners();
    }
  }

  /// Mark that the navigation transition is complete.
  void stationTransitionComplete() {
    _currentStationIndex = _targetStationIndex;
    _isMovingToStation = false;
    notifyListeners();
  }

  /// Mark the current station as completed and persist progress.
  Future<void> markCurrentStationCompleted() async {
    if (_currentSession == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      final stationKey = stationKeys[_currentStationIndex];
      await _repository.markStationCompleted(_currentSession!.id, stationKey);

      final updated = await _repository.getSessionById(_currentSession!.id);
      if (updated != null) {
        _currentSession = updated;
      }

      await _logActivity(
        'station_complete',
        _currentSession!.id,
        detail: stationKey,
      );

      unawaited(_supabaseService.syncAuditSession(_currentSession!.toMap()));
    } catch (e) {
      if (kDebugMode) print('Error marking station completed: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
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

      notifyListeners();
    } catch (e) {
      if (kDebugMode) print('Error updating session progress: $e');
    }
  }

  /// Complete the entire visit session.
  Future<void> completeSession() async {
    if (_currentSession == null) return;

    _isLoading = true;
    notifyListeners();

    try {
      await _repository.updateSessionProgress(
        _currentSession!.id,
        List.from(stationKeys),
      );

      final updated = await _repository.getSessionById(_currentSession!.id);
      if (updated != null) {
        _currentSession = updated;
      }

      await _logActivity('session_complete', _currentSession!.id);

      unawaited(_supabaseService.syncAuditSession(_currentSession!.toMap()));
    } catch (e) {
      if (kDebugMode) print('Error completing session: $e');
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }

  /// Load an incomplete session for the home screen resume list.
  Future<List<AuditSessionModel>> loadInProgressSessions() async {
    try {
      return await _repository.getInProgressSessions();
    } catch (e) {
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
        notifyListeners();
      }
    } catch (e) {
      if (kDebugMode) print('Error deleting session: $e');
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
    notifyListeners();
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
}
