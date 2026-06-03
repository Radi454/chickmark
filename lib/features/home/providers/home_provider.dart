import 'package:flutter/foundation.dart';

import '../../../data/models/audit_session_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/audit_session_repository.dart';
import '../../../data/repositories/flock_repository.dart';
import '../../../core/utils/date_utils.dart';

class HomeProvider extends ChangeNotifier {
  final AuditSessionRepository _sessionRepository;
  final FlockRepository _flockRepository;

  HomeProvider({
    AuditSessionRepository? sessionRepository,
    FlockRepository? flockRepository,
  }) : _sessionRepository = sessionRepository ?? AuditSessionRepository(),
       _flockRepository = flockRepository ?? FlockRepository();

  int _auditsThisMonth = 0;
  int _activeFlocksCount = 0;
  String? _lastAuditDate;
  List<AuditSessionModel> _recentSessions = [];
  List<AuditSessionModel> _activeSessions = [];
  Map<String, int> _auditsByType = {};
  bool _isLoading = false;

  int get auditsThisMonth => _auditsThisMonth;
  int get activeFlocksCount => _activeFlocksCount;
  String? get lastAuditDate => _lastAuditDate;
  List<AuditSessionModel> get recentSessions =>
      List.unmodifiable(_recentSessions);
  List<AuditSessionModel> get activeSessions =>
      List.unmodifiable(_activeSessions);
  Map<String, int> get auditsByType => Map.unmodifiable(_auditsByType);
  bool get isLoading => _isLoading;

  Future<void> load({required UserModel? currentUser}) async {
    _isLoading = true;
    notifyListeners();

    try {
      final customerId = currentUser?.isCustomer == true
          ? currentUser?.customerId
          : null;
      final now = DateTime.now();
      final monthStart = DateTime(
        now.year,
        now.month,
        1,
      ).toIso8601String().substring(0, 10);

      final sessions = await _sessionRepository.getSessionsByDateRange(
        monthStart,
        now.toIso8601String().substring(0, 10),
        customerId: customerId,
        limit: 100000,
      );
      _auditsThisMonth = sessions.length;

      _auditsByType = <String, int>{};
      for (final session in sessions) {
        for (final stationKey in session.selectedStationKeys) {
          _auditsByType[stationKey] = (_auditsByType[stationKey] ?? 0) + 1;
        }
      }

      _recentSessions = customerId == null
          ? await _sessionRepository.getAllSessions(limit: 3)
          : await _sessionRepository.getSessionsByCustomer(
              customerId,
              limit: 3,
            );
      final activeSessions = await _sessionRepository.getInProgressSessions();
      _activeSessions = customerId == null
          ? activeSessions
          : activeSessions
                .where((session) => session.customerId == customerId)
                .toList();
      _lastAuditDate = _recentSessions.isNotEmpty
          ? HatchDateUtils.formatDisplayDate(_recentSessions.first.date)
          : null;

      final flocks = await _flockRepository.getAllFlocks();
      final scopedFlocks = customerId == null
          ? flocks
          : flocks.where((flock) => flock.customerId == customerId).toList();
      _activeFlocksCount = scopedFlocks
          .where((flock) => flock.status == 'active')
          .length;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
