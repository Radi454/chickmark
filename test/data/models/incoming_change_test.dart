import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/incoming_change.dart';

void main() {
  group('IncomingChange', () {
    const sample = IncomingChange(
      table: 'audit_sessions',
      rowId: 's1',
      isNew: true,
      label: 'Acme · Flock 1',
      subtitle: 'Audit 2026-06-05 · by jane@x.com',
      updatedAt: '2026-06-05T00:00:00.000Z',
    );

    test('key combines table and rowId', () {
      expect(sample.key, 'audit_sessions:s1');
    });

    test('encode/decode round-trips a list', () {
      final decoded = IncomingChange.decodeList(
        IncomingChange.encodeList([sample]),
      );
      expect(decoded, hasLength(1));
      expect(decoded.first.key, sample.key);
      expect(decoded.first.isNew, isTrue);
      expect(decoded.first.label, sample.label);
      expect(decoded.first.subtitle, sample.subtitle);
      expect(decoded.first.updatedAt, sample.updatedAt);
    });

    test('decodeList tolerates null, empty, and garbage', () {
      expect(IncomingChange.decodeList(null), isEmpty);
      expect(IncomingChange.decodeList(''), isEmpty);
      expect(IncomingChange.decodeList('not json'), isEmpty);
      expect(IncomingChange.decodeList('{"not":"a list"}'), isEmpty);
    });
  });
}
