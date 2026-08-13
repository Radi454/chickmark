import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/flock_repository.dart';
import 'package:hatchaudit/features/home/providers/home_provider.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuditSessionRepository extends Mock
    implements AuditSessionRepository {}

class _MockFlockRepository extends Mock implements FlockRepository {}

void main() {
  late _MockAuditSessionRepository sessions;
  late _MockFlockRepository flocks;

  setUp(() {
    sessions = _MockAuditSessionRepository();
    flocks = _MockFlockRepository();
  });

  HomeProvider provider() {
    return HomeProvider(sessionRepository: sessions, flockRepository: flocks);
  }

  AuditSessionModel session({
    required String id,
    required DateTime date,
    String customerId = 'customer-1',
  }) {
    return AuditSessionModel(
      id: id,
      customerId: customerId,
      flockId: 'flock-1',
      hatcheryId: 'hatchery-1',
      date: date,
      selectedStationKeys: const ['egg', 'chicks'],
      createdAt: date,
      updatedAt: date,
    );
  }

  test(
    'loads recent sessions and the latest audit date from audit_sessions',
    () async {
      final now = DateTime(2026, 5, 22, 12);
      final monthSession = session(id: 'month', date: now);
      final recentSession = session(
        id: 'recent',
        date: now.subtract(const Duration(days: 2)),
      );

      when(
        () => sessions.getSessionsByDateRange(
          any(),
          any(),
          customerId: any(named: 'customerId'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) async => [monthSession]);
      when(
        () => sessions.getAllSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => [monthSession, recentSession]);
      when(
        () => sessions.getInProgressSessions(),
      ).thenAnswer((_) async => [monthSession]);
      when(() => flocks.getAllFlocks()).thenAnswer(
        (_) async => [
          FlockModel(
            id: 'flock-1',
            customerId: 'customer-1',
            flockId: 'F1',
            breed: 'Ross',
            entryDate: now,
          ),
        ],
      );

      final loaded = provider();
      await loaded.load(currentUser: null);

      expect(loaded.auditsThisMonth, 1);
      expect(loaded.recentSessions.map((item) => item.id), ['month', 'recent']);
      expect(loaded.activeSessions.map((item) => item.id), ['month']);
      expect(loaded.lastAuditDate, '22-05-2026');
      expect(loaded.activeFlocksCount, 1);
    },
  );

  test('scopes recent sessions to customer users', () async {
    final now = DateTime.now();
    final currentUser = UserModel(
      id: 'user-1',
      fullName: 'Customer User',
      email: 'customer@example.com',
      role: 'customer',
      status: 'approved',
      customerId: 'customer-2',
      createdAt: now,
    );
    final scopedSession = session(
      id: 'customer-session',
      date: now,
      customerId: 'customer-2',
    );

    when(
      () => sessions.getSessionsByDateRange(
        any(),
        any(),
        customerId: 'customer-2',
        limit: any(named: 'limit'),
      ),
    ).thenAnswer((_) async => [scopedSession]);
    when(
      () => sessions.getSessionsByCustomer('customer-2', limit: 3),
    ).thenAnswer((_) async => [scopedSession]);
    when(() => sessions.getInProgressSessions()).thenAnswer(
      (_) async => [
        scopedSession,
        session(id: 'other-session', date: now, customerId: 'customer-1'),
      ],
    );
    when(() => flocks.getAllFlocks()).thenAnswer(
      (_) async => [
        FlockModel(
          id: 'flock-2',
          customerId: 'customer-2',
          flockId: 'F2',
          breed: 'Ross',
          entryDate: now,
        ),
        FlockModel(
          id: 'other-flock',
          customerId: 'customer-1',
          flockId: 'F1',
          breed: 'Cobb',
          entryDate: now,
        ),
      ],
    );

    final loaded = provider();
    await loaded.load(currentUser: currentUser);

    expect(loaded.recentSessions.map((item) => item.id), ['customer-session']);
    expect(loaded.activeSessions.map((item) => item.id), ['customer-session']);
    expect(loaded.activeFlocksCount, 1);
  });

  test(
    'does not report loaded data until every initial query completes',
    () async {
      final firstQuery = Completer<List<AuditSessionModel>>();
      when(
        () => sessions.getSessionsByDateRange(
          any(),
          any(),
          customerId: any(named: 'customerId'),
          limit: any(named: 'limit'),
        ),
      ).thenAnswer((_) => firstQuery.future);
      when(
        () => sessions.getAllSessions(limit: any(named: 'limit')),
      ).thenAnswer((_) async => const []);
      when(
        () => sessions.getInProgressSessions(),
      ).thenAnswer((_) async => const []);
      when(() => flocks.getAllFlocks()).thenAnswer((_) async => const []);

      final loaded = provider();
      expect(loaded.loadState, HomeLoadState.uninitialized);
      expect(loaded.hasLoadedData, isFalse);

      final load = loaded.load(currentUser: null);
      expect(loaded.loadState, HomeLoadState.loading);
      expect(loaded.hasLoadedData, isFalse);

      firstQuery.complete(const []);
      await load;

      expect(loaded.loadState, HomeLoadState.loaded);
      expect(loaded.hasLoadedData, isTrue);
    },
  );
}
