import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/auth/session_trust_store.dart';

void main() {
  late Map<String, String> storage;
  late SessionTrustStore store;

  setUp(() {
    storage = <String, String>{};
    store = SessionTrustStore(
      readValue: (key) async => storage[key],
      writeValue: (key, value) async => storage[key] = value,
      deleteValue: (key) async => storage.remove(key),
    );
  });

  test('read returns null when nothing was ever recorded', () async {
    expect(await store.read(), isNull);
  });

  test('record then read round-trips user and verification time', () async {
    final verifiedAt = DateTime.utc(2026, 8, 13, 9, 30);
    await store.record('supabase-user-123', verifiedAt);

    final trust = await store.read();
    expect(trust, isNotNull);
    expect(trust!.userId, 'supabase-user-123');
    expect(trust.lastVerifiedAt, verifiedAt);
  });

  test('record overwrites the previous trust record', () async {
    await store.record('user-a', DateTime.utc(2026, 8, 1));
    await store.record('user-b', DateTime.utc(2026, 8, 12));

    final trust = await store.read();
    expect(trust!.userId, 'user-b');
    expect(trust.lastVerifiedAt, DateTime.utc(2026, 8, 12));
  });

  test('clear removes the record', () async {
    await store.record('user-a', DateTime.utc(2026, 8, 1));
    await store.clear();
    expect(await store.read(), isNull);
  });

  test('corrupt stored payload is treated as no trust, not a crash', () async {
    storage['session_trust_v1'] = 'not-json';
    expect(await store.read(), isNull);
  });

  test('payload missing required fields is treated as no trust', () async {
    storage['session_trust_v1'] = '{"userId":"user-a"}';
    expect(await store.read(), isNull);
  });
}
