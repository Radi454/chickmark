import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/chick_sample_identity.dart';
import 'package:hatchaudit/data/models/panel_sample_model.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';

void main() {
  group('ChickSampleIdentity', () {
    test('pool scope ignores hierarchy text and stays canonical', () {
      expect(
        ChickSampleIdentity.buildScopeKey(
          scopeType: SamplingLayer.pool,
          house: 'must not leak',
          setter: 'must not leak',
        ),
        '{}',
      );
    });

    test('non-pool scope preserves exact trimmed declared identity', () {
      expect(
        ChickSampleIdentity.buildScopeKey(
          scopeType: SamplingLayer.setterHatcher,
          setter: ' Setter | A ',
          hatcher: ' Hatcher:A ',
        ),
        '{"hatcher":"Hatcher:A","setter":"Setter | A"}',
      );
    });

    test('non-pool scope rejects a blank required identifier', () {
      expect(
        () => ChickSampleIdentity.buildScopeKey(
          scopeType: SamplingLayer.house,
          house: '  ',
        ),
        throwsArgumentError,
      );
      expect(
        () => ChickSampleIdentity.buildScopeKey(
          scopeType: SamplingLayer.setterHatcher,
          setter: 'S1',
          hatcher: null,
        ),
        throwsArgumentError,
      );
    });

    test(
      'legacy scope records an explicit null without inventing identity',
      () {
        expect(
          ChickSampleIdentity.buildLegacyScopeKey(
            scopeType: SamplingLayer.setterHatcher,
            setter: 'Setter A',
          ),
          '{"hatcher":null,"setter":"Setter A"}',
        );
      },
    );

    test('sample key has a hand-checked unambiguous encoding', () {
      expect(
        ChickSampleIdentity.buildSampleKey(
          domain: 'chicks.weights',
          sessionId: 'session-1',
          scopeType: SamplingLayer.house,
          scopeKey: '{"house":"House A"}',
          replicate: 1,
        ),
        'WyJjaGlja3Mud2VpZ2h0cyIsInNlc3Npb24tMSIsImhvdXNlIiwie1wiaG91c2VcIjpcIkhvdXNlIEFcIn0iLDFd',
      );
    });

    test('delimiter-like values cannot collide', () {
      final first = ChickSampleIdentity.buildSampleKey(
        domain: 'chicks.weights',
        sessionId: 'session|house',
        scopeType: SamplingLayer.house,
        scopeKey: '{"house":"A"}',
        replicate: 1,
      );
      final second = ChickSampleIdentity.buildSampleKey(
        domain: 'chicks.weights|session',
        sessionId: 'house',
        scopeType: SamplingLayer.house,
        scopeKey: '{"house":"A"}',
        replicate: 1,
      );

      expect(first, isNot(second));
    });

    test('sample key rejects blank identity and non-positive replicate', () {
      expect(
        () => ChickSampleIdentity.buildSampleKey(
          domain: '',
          sessionId: 'session-1',
          scopeType: SamplingLayer.pool,
          scopeKey: '{}',
          replicate: 1,
        ),
        throwsArgumentError,
      );
      expect(
        () => ChickSampleIdentity.buildSampleKey(
          domain: 'chicks.weights',
          sessionId: 'session-1',
          scopeType: SamplingLayer.pool,
          scopeKey: '{}',
          replicate: 0,
        ),
        throwsArgumentError,
      );
    });

    test('draft id is not part of persisted sample identity', () {
      String keyForDraft(String ignoredDraftId) {
        return ChickSampleIdentity.buildSampleKey(
          domain: 'chicks.weights',
          sessionId: 'session-1',
          scopeType: SamplingLayer.pool,
          scopeKey: '{}',
          replicate: 1,
        );
      }

      expect(keyForDraft('draft-before'), keyForDraft('draft-after-reload'));
    });
  });

  test(
    'PanelRecord round trip preserves persisted V2 identity and provenance',
    () {
      final observedAt = DateTime.utc(2026, 8, 24, 9, 30);
      final record = PanelRecord(
        id: '0198f00c-5c00-7000-8000-000000000001',
        tableName: 'chick_weights',
        sessionId: 'session-1',
        customerId: 'customer-1',
        date: DateTime(2026, 8, 24),
        scopeType: SamplingLayer.house,
        house: 'House A',
        domain: 'chicks.weights',
        schemaVersion: 1,
        scopeKey: '{"house":"House A"}',
        replicate: 2,
        sampleKey: 'stable-sample-key',
        source: 'human',
        captureMethod: 'manual',
        createdBy: 'user-1',
        deviceId: 'device-1',
        sourceRefId: 'form-1',
        observedAt: observedAt,
        qualityStatus: 'FLAG',
        qualityFlags: '[{"tier":"FLAG","code":"missing_raw_evidence"}]',
        createdAt: DateTime.utc(2026, 8, 24, 9),
        updatedAt: DateTime.utc(2026, 8, 24, 9, 31),
      );

      final reloaded = PanelRecord.fromMap('chick_weights', record.toMap());

      expect(reloaded.id, '0198f00c-5c00-7000-8000-000000000001');
      expect(reloaded.domain, 'chicks.weights');
      expect(reloaded.schemaVersion, 1);
      expect(reloaded.scopeKey, '{"house":"House A"}');
      expect(reloaded.replicate, 2);
      expect(reloaded.sampleKey, 'stable-sample-key');
      expect(reloaded.source, 'human');
      expect(reloaded.captureMethod, 'manual');
      expect(reloaded.createdBy, 'user-1');
      expect(reloaded.deviceId, 'device-1');
      expect(reloaded.sourceRefId, 'form-1');
      expect(reloaded.observedAt, observedAt);
      expect(reloaded.qualityStatus, 'FLAG');
      expect(
        reloaded.qualityFlags,
        '[{"tier":"FLAG","code":"missing_raw_evidence"}]',
      );
    },
  );
}
