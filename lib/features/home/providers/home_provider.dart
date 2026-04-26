import 'package:flutter/foundation.dart';

import '../../../data/models/audit_model.dart';
import '../../../data/models/user_model.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/flock_repository.dart';

class HomeProvider extends ChangeNotifier {
  final AuditRepository _auditRepository = AuditRepository();
  final FlockRepository _flockRepository = FlockRepository();

  int _auditsThisMonth = 0;
  int _activeFlocksCount = 0;
  String? _lastAuditDate;
  List<AuditModel> _recentAudits = [];
  Map<String, int> _auditsByType = {};
  bool _isLoading = false;

  int get auditsThisMonth => _auditsThisMonth;
  int get activeFlocksCount => _activeFlocksCount;
  String? get lastAuditDate => _lastAuditDate;
  List<AuditModel> get recentAudits => List.unmodifiable(_recentAudits);
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

      final allAudits = await _auditRepository.getAuditsSince(
        monthStart,
        customerId: customerId,
      );
      _auditsThisMonth = allAudits.length;

      _auditsByType = <String, int>{};
      for (final audit in allAudits) {
        _auditsByType[audit.auditType] = (_auditsByType[audit.auditType] ?? 0) + 1;
      }

      _recentAudits = await _auditRepository.getRecentAudits(
        limit: 5,
        customerId: customerId,
      );
      _lastAuditDate = _recentAudits.isNotEmpty
          ? _recentAudits.first.date.toIso8601String().split('T').first
          : null;

      final flocks = await _flockRepository.getAllFlocks();
      final scopedFlocks = customerId == null
          ? flocks
          : flocks.where((flock) => flock.customerId == customerId).toList();
      _activeFlocksCount = scopedFlocks.where((flock) => flock.status == 'active').length;
    } finally {
      _isLoading = false;
      notifyListeners();
    }
  }
}
