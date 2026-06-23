import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/incoming_change.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

IncomingChange _change(String id, {bool isNew = true, String label = 'L'}) =>
    IncomingChange(
      table: 'audit_sessions',
      rowId: id,
      isNew: isNew,
      label: label,
      subtitle: 's',
      updatedAt: '2026-06-05T00:00:00.000Z',
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  // Drain the constructor's async `_load()` so it doesn't race past our writes.
  Future<SettingsProvider> provider() async {
    final p = SettingsProvider();
    await Future<void>.delayed(Duration.zero);
    return p;
  }

  group('SettingsProvider incoming changes', () {
    test('recordSync stores incoming sessions and other count', () async {
      final p = await provider();
      await p.recordSync(
        online: true,
        pushed: 0,
        pulled: 5,
        incoming: [_change('a'), _change('b')],
        otherIncoming: 3,
      );
      expect(p.incomingChanges, hasLength(2));
      expect(p.otherIncomingCount, 3);
      expect(p.hasIncomingChanges, isTrue);
      p.dispose();
    });

    test('merge dedupes by key (newest wins) and accumulates other', () async {
      final p = await provider();
      await p.recordSync(
        online: true,
        pushed: 0,
        pulled: 0,
        incoming: [_change('a', label: 'old')],
        otherIncoming: 1,
      );
      await p.recordSync(
        online: true,
        pushed: 0,
        pulled: 0,
        incoming: [
          _change('a', label: 'new'),
          _change('b'),
        ],
        otherIncoming: 2,
      );
      expect(p.incomingChanges, hasLength(2)); // 'a' deduped
      expect(p.incomingChanges.firstWhere((c) => c.rowId == 'a').label, 'new');
      expect(p.otherIncomingCount, 3); // 1 + 2
      p.dispose();
    });

    test('an offline empty-merge sync preserves a pending notice', () async {
      final p = await provider();
      await p.recordSync(
        online: true,
        pushed: 0,
        pulled: 0,
        incoming: [_change('a')],
        otherIncoming: 1,
      );
      await p.recordSync(online: false, pushed: 0, pulled: 0); // empty batch
      expect(p.incomingChanges, hasLength(1));
      expect(p.otherIncomingCount, 1);
      p.dispose();
    });

    test('acknowledgeIncomingChange removes only that item', () async {
      final p = await provider();
      await p.recordSync(
        online: true,
        pushed: 0,
        pulled: 0,
        incoming: [_change('a'), _change('b')],
        otherIncoming: 2,
      );
      await p.acknowledgeIncomingChange('audit_sessions:a');
      expect(p.incomingChanges, hasLength(1));
      expect(p.incomingChanges.single.rowId, 'b');
      expect(p.otherIncomingCount, 2); // aggregate untouched
      p.dispose();
    });

    test('clearIncomingChanges empties everything', () async {
      final p = await provider();
      await p.recordSync(
        online: true,
        pushed: 0,
        pulled: 0,
        incoming: [_change('a')],
        otherIncoming: 5,
      );
      await p.clearIncomingChanges();
      expect(p.incomingChanges, isEmpty);
      expect(p.otherIncomingCount, 0);
      expect(p.hasIncomingChanges, isFalse);
      p.dispose();
    });

    test(
      'successful manual sync can acknowledge pending incoming notices',
      () async {
        final p = await provider();
        await p.recordSync(
          online: true,
          pushed: 0,
          pulled: 0,
          incoming: [_change('a')],
          otherIncoming: 5,
        );

        await p.recordSync(
          online: true,
          pushed: 0,
          pulled: 2,
          acknowledgeIncoming: true,
        );

        expect(p.incomingChanges, isEmpty);
        expect(p.otherIncomingCount, 0);
        expect(p.hasIncomingChanges, isFalse);
        p.dispose();
      },
    );

    test('incoming changes persist across provider reloads', () async {
      final p1 = await provider();
      await p1.recordSync(
        online: true,
        pushed: 0,
        pulled: 0,
        incoming: [_change('a')],
        otherIncoming: 1,
      );
      p1.dispose();

      final p2 = await provider();
      expect(p2.incomingChanges, hasLength(1));
      expect(p2.otherIncomingCount, 1);
      p2.dispose();
    });
  });
}
