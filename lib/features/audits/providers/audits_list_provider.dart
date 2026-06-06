import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../../data/models/audit_session_model.dart';
import '../../../data/repositories/audit_session_repository.dart';
import '../../../data/repositories/govee_capture_repository.dart';
import '../../../data/repositories/panel_sample_repository.dart';
import '../models/session_filter.dart';
import 'audit_session_provider.dart';

/// Data status of a single station within a session, derived from real stored
/// data: [empty] (no panel rows), [inProgress] (rows exist but not marked
/// completed), [done] (marked completed).
enum StationDataStatus { empty, inProgress, done }

/// Resolves session foreign keys to display/search names. Injected from the
/// screen (backed by CustomersProvider) so the provider stays unit-testable.
class SessionDisplayResolver {
  final String Function(String customerId) customerName;
  final String Function(String? hatcheryId) hatcheryName;
  final String Function(String? flockId) flockLabel;
  final String? Function(String? flockId) flockBreed;

  const SessionDisplayResolver({
    required this.customerName,
    required this.hatcheryName,
    required this.flockLabel,
    required this.flockBreed,
  });
}

class StationView {
  final String key;
  final String label;
  final StationDataStatus status;

  /// Panel-data sync state: 'synced' | 'pending' | 'failed' | 'none'.
  final String sync;

  /// Govee environmental-capture sync state for this station's spot:
  /// 'synced' | 'pending' | 'failed' | 'none' (no capture / station has no spot).
  final String goveeSync;

  const StationView({
    required this.key,
    required this.label,
    required this.status,
    required this.sync,
    this.goveeSync = 'none',
  });

  bool get hasGovee => goveeSync != 'none';
}

class SessionView {
  final AuditSessionModel session;
  final List<StationView> stations;

  /// Rolled-up sync state for the whole visit: 'synced' | 'pending' | 'failed'.
  final String sync;
  final int completed;
  final int total;

  /// Visit-level Govee environmental capture summary (across all spots).
  final int goveeCaptureCount;

  /// Rolled-up Govee sync state: 'synced' | 'pending' | 'failed' | 'none'.
  final String goveeSync;

  const SessionView({
    required this.session,
    required this.stations,
    required this.sync,
    required this.completed,
    required this.total,
    this.goveeCaptureCount = 0,
    this.goveeSync = 'none',
  });
}

/// Drives the session-driven Audits management screen: paged loading, station
/// data + sync rollups, search/filter, and per-session/station actions.
class AuditsListProvider extends ChangeNotifier {
  final AuditSessionRepository _sessionRepo;
  final PanelSampleRepository _panelRepo;
  final GoveeCaptureRepository _goveeRepo;

  AuditsListProvider({
    AuditSessionRepository? sessionRepository,
    PanelSampleRepository? panelRepository,
    GoveeCaptureRepository? goveeRepository,
  }) : _sessionRepo = sessionRepository ?? AuditSessionRepository(),
       _panelRepo = panelRepository ?? PanelSampleRepository(),
       _goveeRepo = goveeRepository ?? GoveeCaptureRepository();

  static const pageSize = 20;
  static const _prefsFilterKey = 'audit_session_filter';

  final List<AuditSessionModel> _loaded = [];
  // sessionId -> tableName -> syncStatus -> count
  final Map<String, Map<String, Map<String, int>>> _rollups = {};
  // 'customerId|hatcheryId|captureDate' -> stationKey -> syncStatus -> count
  final Map<String, Map<String, Map<String, int>>> _goveeRollups = {};
  SessionFilter _filter = SessionFilter.empty;
  String _search = '';
  SessionDisplayResolver? _resolver;

  bool _isLoading = false;
  bool _isLoadingMore = false;
  bool _hasMore = true;
  int _offset = 0;
  String? _error;

  bool get isLoading => _isLoading;
  bool get isLoadingMore => _isLoadingMore;
  bool get hasMore => _hasMore;
  String? get error => _error;
  SessionFilter get filter => _filter;
  String get search => _search;
  bool get isEmpty => _loaded.isEmpty;

  /// Set the name resolver used for free-text search and card display. Does not
  /// notify (the screen rebuilds it from CustomersProvider each frame).
  void setResolver(SessionDisplayResolver resolver) => _resolver = resolver;
  SessionDisplayResolver? get resolver => _resolver;

  Future<void> init() async {
    _filter = await _loadPersistedFilter();
    await refresh();
  }

  Future<void> refresh() async {
    _isLoading = true;
    _error = null;
    notifyListeners();
    _loaded.clear();
    _rollups.clear();
    _goveeRollups.clear();
    _offset = 0;
    _hasMore = true;
    try {
      await _loadPage();
    } catch (e) {
      _error = 'Could not load visits';
    }
    _isLoading = false;
    notifyListeners();
  }

  Future<void> loadMore() async {
    if (_isLoadingMore || _isLoading || !_hasMore) return;
    _isLoadingMore = true;
    notifyListeners();
    try {
      await _loadPage();
    } catch (e) {
      _error = 'Could not load more visits';
    }
    _isLoadingMore = false;
    notifyListeners();
  }

  Future<void> _loadPage() async {
    final statuses = _filter.statuses.isEmpty
        ? null
        : _filter.statuses.toList();
    final page = await _sessionRepo.querySessions(
      statuses: statuses,
      dateFrom: _filter.dateFrom == null ? null : _dateKey(_filter.dateFrom!),
      dateTo: _filter.dateTo == null ? null : _dateKey(_filter.dateTo!),
      customerId: _filter.customerId,
      flockId: _filter.flockId,
      limit: pageSize,
      offset: _offset,
    );
    _offset += page.length;
    if (page.length < pageSize) _hasMore = false;
    _loaded.addAll(page);
    if (page.isNotEmpty) {
      final rollups = await _panelRepo.getStationRollupForSessions(
        page.map((session) => session.id),
      );
      _rollups.addAll(rollups);
      final goveeRollups = await _goveeRepo.getGoveeRollupForSessions(
        page.map(_goveeKeyTuple),
      );
      _goveeRollups.addAll(goveeRollups);
    }
  }

  Future<void> setFilter(SessionFilter filter) async {
    _filter = filter;
    await _persistFilter(filter);
    await refresh();
  }

  Future<void> clearFilters() => setFilter(SessionFilter.empty);

  void setSearch(String value) {
    _search = value;
    notifyListeners();
  }

  /// Sessions visible after structured filters (already applied in SQL),
  /// sync-status filter, and free-text search.
  List<SessionView> get visibleSessions {
    final query = _search.trim().toLowerCase();
    final out = <SessionView>[];
    for (final session in _loaded) {
      final view = _viewFor(session);
      if (_filter.syncStatuses.isNotEmpty &&
          !_filter.syncStatuses.contains(view.sync)) {
        continue;
      }
      if (query.isNotEmpty && !_matchesSearch(session, query)) continue;
      out.add(view);
    }
    return out;
  }

  SessionView _viewFor(AuditSessionModel session) {
    final selected = session.selectedStationKeys;
    final completed = session.stationsCompleted;
    final stations = <StationView>[];
    var anyFailed = session.syncStatus == 'failed';
    var anyPending = session.syncStatus == 'pending';
    final goveeForSession =
        _goveeRollups[_goveeKey(session)] ??
        const <String, Map<String, int>>{};

    for (final key in selected) {
      final tables = kStationPanelTables[key] ?? const [];
      var total = 0;
      var pending = 0;
      var failed = 0;
      for (final table in tables) {
        final counts = _rollups[session.id]?[table];
        if (counts == null) continue;
        for (final entry in counts.entries) {
          total += entry.value;
          if (entry.key == 'pending') pending += entry.value;
          if (entry.key == 'failed') failed += entry.value;
        }
      }
      final hasData = total > 0;
      final done = completed.contains(key);
      final dataStatus = done
          ? StationDataStatus.done
          : (hasData ? StationDataStatus.inProgress : StationDataStatus.empty);
      String sync;
      if (!hasData) {
        sync = 'none';
      } else if (failed > 0) {
        sync = 'failed';
        anyFailed = true;
      } else if (pending > 0) {
        sync = 'pending';
        anyPending = true;
      } else {
        sync = 'synced';
      }

      // Govee environmental capture for this station's spot (links by
      // customer+hatchery+date). Folds into the session-level sync rollup.
      final goveeCounts = goveeForSession[key];
      var goveeSync = 'none';
      if (goveeCounts != null && goveeCounts.isNotEmpty) {
        final goveeFailed = goveeCounts['failed'] ?? 0;
        final goveePending = goveeCounts['pending'] ?? 0;
        if (goveeFailed > 0) {
          goveeSync = 'failed';
          anyFailed = true;
        } else if (goveePending > 0) {
          goveeSync = 'pending';
          anyPending = true;
        } else {
          goveeSync = 'synced';
        }
      }

      stations.add(
        StationView(
          key: key,
          label: AuditSessionProvider.stationDisplayLabels[key] ?? key,
          status: dataStatus,
          sync: sync,
          goveeSync: goveeSync,
        ),
      );
    }

    // Visit-level Govee rollup across every captured spot (not just spots that
    // map to a selected station), for the dedicated Govee sector row.
    var goveeTotal = 0;
    var goveePendingTotal = 0;
    var goveeFailedTotal = 0;
    for (final byStatus in goveeForSession.values) {
      for (final entry in byStatus.entries) {
        goveeTotal += entry.value;
        if (entry.key == 'pending') goveePendingTotal += entry.value;
        if (entry.key == 'failed') goveeFailedTotal += entry.value;
      }
    }
    final sessionGoveeSync = goveeTotal == 0
        ? 'none'
        : (goveeFailedTotal > 0
              ? 'failed'
              : (goveePendingTotal > 0 ? 'pending' : 'synced'));

    final sessionSync = anyFailed
        ? 'failed'
        : (anyPending ? 'pending' : 'synced');
    return SessionView(
      session: session,
      stations: stations,
      sync: sessionSync,
      completed: completed.where(selected.contains).length,
      total: selected.length,
      goveeCaptureCount: goveeTotal,
      goveeSync: sessionGoveeSync,
    );
  }

  bool _matchesSearch(AuditSessionModel session, String query) {
    final resolver = _resolver;
    final haystack = <String?>[
      session.customerId,
      session.flockId,
      session.breed,
      resolver?.customerName(session.customerId),
      resolver?.hatcheryName(session.hatcheryId),
      resolver?.flockLabel(session.flockId),
      resolver?.flockBreed(session.flockId),
    ];
    return haystack.any(
      (value) => value != null && value.toLowerCase().contains(query),
    );
  }

  /// Clears one station's stored data and de-completes it, mirroring the
  /// in-session Clear (delete the station's panel rows + drop it from
  /// stationsCompleted). Both writes flow through the dirty-tracking repos.
  Future<void> clearStation(
    AuditSessionModel session,
    String stationKey,
  ) async {
    final tables = kStationPanelTables[stationKey] ?? const [];
    for (final table in tables) {
      await _panelRepo.deleteRowsBySessionId(table, session.id);
    }
    final nextCompleted = session.stationsCompleted
        .where((key) => key != stationKey)
        .toList(growable: false);
    await _sessionRepo.updateSessionProgress(session.id, nextCompleted);
    await reloadSession(session.id);
  }

  /// Drop a session from the in-memory view (after it was deleted elsewhere).
  void removeSession(String id) {
    _loaded.removeWhere((session) => session.id == id);
    _rollups.remove(id);
    notifyListeners();
  }

  /// Re-read a single session + its rollup (after returning from the workflow
  /// or clearing a station) without reloading the whole list.
  Future<void> reloadSession(String id) async {
    final updated = await _sessionRepo.getSessionById(id);
    final index = _loaded.indexWhere((session) => session.id == id);
    if (index < 0) {
      notifyListeners();
      return;
    }
    if (updated == null) {
      _loaded.removeAt(index);
      _rollups.remove(id);
    } else {
      _loaded[index] = updated;
      final rollup = await _panelRepo.getStationRollupForSessions([id]);
      _rollups[id] = rollup[id] ?? {};
      final govee = await _goveeRepo.getGoveeRollupForSessions([
        _goveeKeyTuple(updated),
      ]);
      _goveeRollups[_goveeKey(updated)] = govee[_goveeKey(updated)] ?? {};
    }
    notifyListeners();
  }

  String _goveeKey(AuditSessionModel session) =>
      '${session.customerId}|${session.hatcheryId}|${_captureDateKey(session.date)}';

  ({String customerId, String hatcheryId, String captureDate}) _goveeKeyTuple(
    AuditSessionModel session,
  ) => (
    customerId: session.customerId,
    hatcheryId: session.hatcheryId,
    captureDate: _captureDateKey(session.date),
  );

  /// Govee captureDate format ('yyyy-MM-dd'), matching how captures are stored.
  String _captureDateKey(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }

  Future<SessionFilter> _loadPersistedFilter() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return SessionFilter.decode(prefs.getString(_prefsFilterKey));
    } catch (_) {
      return SessionFilter.empty;
    }
  }

  Future<void> _persistFilter(SessionFilter filter) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (filter.hasFilters) {
        await prefs.setString(_prefsFilterKey, filter.encode());
      } else {
        await prefs.remove(_prefsFilterKey);
      }
    } catch (_) {}
  }

  String _dateKey(DateTime date) => date.toIso8601String().split('T').first;
}
