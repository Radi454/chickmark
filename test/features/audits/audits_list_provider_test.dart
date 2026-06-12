import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/panel_sample_repository.dart';
import 'package:hatchaudit/features/audits/models/session_filter.dart';
import 'package:hatchaudit/features/audits/providers/audits_list_provider.dart';

class _MockSessionRepo extends Mock implements AuditSessionRepository {}

class _MockPanelRepo extends Mock implements PanelSampleRepository {}

AuditSessionModel _session(
  String id, {
  String customerId = 'c1',
  String flockId = 'f1',
  String status = 'in_progress',
  String syncStatus = 'synced',
  List<String> selected = supportedStationKeys,
  List<String> completed = const [],
}) {
  return AuditSessionModel(
    id: id,
    customerId: customerId,
    flockId: flockId,
    hatcheryId: 'h1',
    date: DateTime(2026, 5, 1),
    status: status,
    syncStatus: syncStatus,
    selectedStationKeys: selected,
    stationsCompleted: completed,
    createdAt: DateTime(2026, 5, 1),
    updatedAt: DateTime(2026, 5, 1),
  );
}

/// Convenience resolver mapping ids straight back to readable names.
const _resolver = SessionDisplayResolver(
  customerName: _customerName,
  hatcheryName: _hatcheryName,
  flockLabel: _flockLabel,
  flockBreed: _flockBreed,
);
String _customerName(String id) => switch (id) {
  'c-acme' => 'Acme Hatchery',
  'c-globex' => 'Globex Farms',
  _ => id,
};
String _hatcheryName(String? id) => 'Hatchery $id';
String _flockLabel(String? id) => switch (id) {
  'f-ross' => 'Ross-12',
  _ => id ?? '',
};
String? _flockBreed(String? id) => id == 'f-ross' ? 'Ross 308' : null;

void main() {
  late _MockSessionRepo sessions;
  late _MockPanelRepo panels;

  setUpAll(() {
    registerFallbackValue(<String>[]);
  });

  setUp(() {
    sessions = _MockSessionRepo();
    panels = _MockPanelRepo();
    when(() => panels.getStationRollupForSessions(any())).thenAnswer(
      (_) async => <String, Map<String, Map<String, int>>>{},
    );
  });

  AuditsListProvider provider() => AuditsListProvider(
    sessionRepository: sessions,
    panelRepository: panels,
  );

  void stubPages(List<List<AuditSessionModel>> pages) {
    when(
      () => sessions.querySessions(
        statuses: any(named: 'statuses'),
        dateFrom: any(named: 'dateFrom'),
        dateTo: any(named: 'dateTo'),
        customerId: any(named: 'customerId'),
        flockId: any(named: 'flockId'),
        limit: any(named: 'limit'),
        offset: any(named: 'offset'),
      ),
    ).thenAnswer((invocation) async {
      final offset = invocation.namedArguments[const Symbol('offset')] as int;
      final limit = invocation.namedArguments[const Symbol('limit')] as int;
      final all = pages.expand((page) => page).toList();
      if (offset >= all.length) return <AuditSessionModel>[];
      return all.skip(offset).take(limit).toList();
    });
  }

  test('shows all sessions and is not capped at five', () async {
    final many = List.generate(12, (i) => _session('s$i'));
    stubPages([many]);

    final p = provider();
    await p.refresh();

    expect(p.visibleSessions.length, 12);
  });

  test('paginates with loadMore (page size 20) appending later pages', () async {
    final first = List.generate(20, (i) => _session('a$i'));
    final second = List.generate(7, (i) => _session('b$i'));
    stubPages([first, second]);

    final p = provider();
    await p.refresh();
    expect(p.visibleSessions.length, 20);
    expect(p.hasMore, isTrue);

    await p.loadMore();
    expect(p.visibleSessions.length, 27);
    expect(p.hasMore, isFalse);
  });

  test('search filters sessions by resolved customer/flock names', () async {
    stubPages([
      [
        _session('s1', customerId: 'c-acme', flockId: 'f-ross'),
        _session('s2', customerId: 'c-globex', flockId: 'f-x'),
      ],
    ]);

    final p = provider()..setResolver(_resolver);
    await p.refresh();
    expect(p.visibleSessions.length, 2);

    p.setSearch('acme');
    expect(p.visibleSessions.map((v) => v.session.id), ['s1']);

    p.setSearch('ross 308'); // matches flock breed of s1
    expect(p.visibleSessions.map((v) => v.session.id), ['s1']);

    p.setSearch('globex');
    expect(p.visibleSessions.map((v) => v.session.id), ['s2']);
  });

  test('derives station status: done / in progress / empty', () async {
    stubPages([
      [
        _session(
          's1',
          selected: ['egg', 'chicks', 'setters'],
          completed: ['egg'],
        ),
      ],
    ]);
    when(() => panels.getStationRollupForSessions(any())).thenAnswer(
      (_) async => {
        's1': {
          'egg_storage': {'synced': 1},
          'chick_quality': {'pending': 1}, // chicks has data, not completed
        },
      },
    );

    final p = provider();
    await p.refresh();
    final stations = {
      for (final s in p.visibleSessions.single.stations) s.key: s.status,
    };

    expect(stations['egg'], StationDataStatus.done);
    expect(stations['chicks'], StationDataStatus.inProgress);
    expect(stations['setters'], StationDataStatus.empty);
  });

  test('derives sync status from session + panel rows and filters by it', () async {
    stubPages([
      [
        _session('s-synced', selected: ['egg']),
        _session('s-pending', selected: ['egg']),
        _session('s-failed', selected: ['egg']),
      ],
    ]);
    when(() => panels.getStationRollupForSessions(any())).thenAnswer(
      (_) async => {
        's-synced': {
          'egg_storage': {'synced': 2},
        },
        's-pending': {
          'egg_storage': {'synced': 1, 'pending': 1},
        },
        's-failed': {
          'egg_storage': {'failed': 1},
        },
      },
    );

    final p = provider();
    await p.refresh();
    final byId = {for (final v in p.visibleSessions) v.session.id: v.sync};
    expect(byId['s-synced'], 'synced');
    expect(byId['s-pending'], 'pending');
    expect(byId['s-failed'], 'failed');

    await p.setFilter(const SessionFilter(syncStatuses: {'failed'}));
    expect(p.visibleSessions.map((v) => v.session.id), ['s-failed']);
  });

  test('clearStation deletes panel rows, de-completes, and reloads', () async {
    stubPages([
      [
        _session('s1', selected: ['egg', 'chicks'], completed: ['egg', 'chicks']),
      ],
    ]);
    when(
      () => panels.deleteRowsBySessionId(any(), any()),
    ).thenAnswer((_) async {});
    when(
      () => sessions.updateSessionProgress(any(), any()),
    ).thenAnswer((_) async {});
    when(() => sessions.getSessionById('s1')).thenAnswer(
      (_) async => _session('s1', selected: ['egg', 'chicks'], completed: ['chicks']),
    );

    final p = provider();
    await p.refresh();
    await p.clearStation(p.visibleSessions.single.session, 'egg');

    // Both egg panel tables cleared.
    verify(() => panels.deleteRowsBySessionId('egg_storage', 's1')).called(1);
    verify(() => panels.deleteRowsBySessionId('egg_quality', 's1')).called(1);
    // Station dropped from completion (only chicks remains).
    verify(() => sessions.updateSessionProgress('s1', ['chicks'])).called(1);
  });

  test('removeSession drops it from the visible list', () async {
    stubPages([
      [_session('s1'), _session('s2')],
    ]);

    final p = provider();
    await p.refresh();
    expect(p.visibleSessions.length, 2);

    p.removeSession('s1');
    expect(p.visibleSessions.map((v) => v.session.id), ['s2']);
  });
}
