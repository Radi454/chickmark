import 'package:flutter/foundation.dart';

import '../../../data/models/govee_capture_model.dart';
import '../../../data/repositories/govee_capture_repository.dart';

/// Resolves customer/hatchery ids to display names for the records list.
class GoveeRecordResolver {
  final String Function(String customerId) customerName;
  final String Function(String hatcheryId) hatcheryName;

  const GoveeRecordResolver({
    required this.customerName,
    required this.hatcheryName,
  });
}

/// A day's worth of Govee captures for one customer + hatchery (one visit-day).
class GoveeRecordGroup {
  final String customerId;
  final String hatcheryId;
  final String captureDate;
  final List<GoveeDailyCaptureModel> captures;

  /// Rolled-up cloud sync state across the day's captures.
  final String sync;

  const GoveeRecordGroup({
    required this.customerId,
    required this.hatcheryId,
    required this.captureDate,
    required this.captures,
    required this.sync,
  });

  int get totalReadings =>
      captures.fold(0, (sum, capture) => sum + capture.readingCount);

  DateTime get latestUpdatedAt => captures
      .map((capture) => capture.updatedAt)
      .reduce((a, b) => a.isAfter(b) ? a : b);
}

/// Drives the standalone Govee Records screen: loads all daily captures, groups
/// them by visit-day, and filters by free-text search. Sync state per group is
/// derived from the real per-row [GoveeDailyCaptureModel.syncStatus].
class GoveeRecordsProvider extends ChangeNotifier {
  final GoveeCaptureRepository _repo;

  GoveeRecordsProvider({GoveeCaptureRepository? repository})
    : _repo = repository ?? GoveeCaptureRepository();

  final List<GoveeDailyCaptureModel> _all = [];
  bool _isLoading = false;
  String _search = '';
  String? _error;
  GoveeRecordResolver? _resolver;

  bool get isLoading => _isLoading;
  String get search => _search;
  String? get error => _error;
  bool get isEmpty => _all.isEmpty;

  void setResolver(GoveeRecordResolver resolver) => _resolver = resolver;

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    try {
      final captures = await _repo.getAllCaptures();
      _all
        ..clear()
        ..addAll(captures);
    } catch (_) {
      _error = 'Could not load Govee records';
    }
    _isLoading = false;
    notifyListeners();
  }

  void setSearch(String query) {
    _search = query;
    notifyListeners();
  }

  /// Removes one place capture (queuing a cloud tombstone) and drops it from the
  /// in-memory list so the list updates without a full reload.
  Future<void> deleteCapture(GoveeDailyCaptureModel capture) async {
    await _repo.deleteCapture(capture.id);
    _all.removeWhere((c) => c.id == capture.id);
    notifyListeners();
  }

  /// Keeps an already-open records list in sync with saves from the floating
  /// capture panel. Re-recording replaces the prior row for the same scope.
  void mergeSavedCapture(GoveeDailyCaptureModel capture) {
    _all.removeWhere(
      (existing) =>
          existing.id == capture.id || _sameCaptureScope(existing, capture),
    );
    _all.add(capture);
    notifyListeners();
  }

  List<GoveeRecordGroup> get visibleGroups {
    final byKey = <String, List<GoveeDailyCaptureModel>>{};
    for (final capture in _all) {
      final key =
          '${capture.customerId}|${capture.hatcheryId}|${capture.captureDate}';
      byKey.putIfAbsent(key, () => []).add(capture);
    }
    final groups =
        byKey.values.map((captures) {
          final sorted = [...captures]
            ..sort((a, b) => a.place.label.compareTo(b.place.label));
          final first = sorted.first;
          return GoveeRecordGroup(
            customerId: first.customerId,
            hatcheryId: first.hatcheryId,
            captureDate: first.captureDate,
            captures: sorted,
            sync: _rollup(sorted),
          );
        }).toList()..sort((a, b) {
          final updatedSort = b.latestUpdatedAt.compareTo(a.latestUpdatedAt);
          if (updatedSort != 0) return updatedSort;
          final dateSort = b.captureDate.compareTo(a.captureDate);
          if (dateSort != 0) return dateSort;
          return a.customerId.compareTo(b.customerId);
        });

    final query = _search.trim().toLowerCase();
    if (query.isEmpty) return groups;
    return groups.where((group) => _matches(group, query)).toList();
  }

  bool _matches(GoveeRecordGroup group, String query) {
    final resolver = _resolver;
    final haystack = <String>[
      group.customerId,
      group.hatcheryId,
      group.captureDate,
      if (resolver != null) resolver.customerName(group.customerId),
      if (resolver != null) resolver.hatcheryName(group.hatcheryId),
      for (final capture in group.captures) capture.place.label,
    ];
    return haystack.any((value) => value.toLowerCase().contains(query));
  }

  String _rollup(List<GoveeDailyCaptureModel> captures) {
    if (captures.any((c) => c.syncStatus == 'failed')) return 'failed';
    if (captures.any((c) => c.syncStatus == 'pending')) return 'pending';
    return 'synced';
  }

  bool _sameCaptureScope(GoveeDailyCaptureModel a, GoveeDailyCaptureModel b) {
    return a.customerId == b.customerId &&
        a.hatcheryId == b.hatcheryId &&
        a.captureDate == b.captureDate &&
        a.place == b.place &&
        (a.machineId ?? '') == (b.machineId ?? '');
  }
}
