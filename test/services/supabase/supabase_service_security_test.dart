import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

void main() {
  test('Chick V2 identity and provenance map to cloud snake_case', () {
    final payload = toSupabaseUpsertPayload('chick_weights', {
      'sampleKey': 'key-1',
      'scopeKey': '{"house":"H1"}',
      'schemaVersion': 1,
      'captureMethod': 'manual',
      'createdBy': 'user-1',
      'deviceId': 'device-1',
      'sourceRefId': 'ref-1',
      'observedAt': '2026-08-24T00:00:00Z',
      'qualityStatus': 'WARN',
      'qualityFlags': '[{"tier":"WARN","code":"item_out_of_range"}]',
      'dirtyAt': 'device-only',
    });

    expect(payload, {
      'sample_key': 'key-1',
      'scope_key': '{"house":"H1"}',
      'schema_version': 1,
      'capture_method': 'manual',
      'created_by': 'user-1',
      'device_id': 'device-1',
      'source_ref_id': 'ref-1',
      'observed_at': '2026-08-24T00:00:00Z',
      'quality_status': 'WARN',
      'quality_flags': '[{"tier":"WARN","code":"item_out_of_range"}]',
    });
  });

  test(
    'upsert payload strips local sync metadata before snake case conversion',
    () {
      final payload = toSupabaseUpsertPayload('flocks', {
        'id': 'flock-1',
        'customerId': 'customer-1',
        'flockId': 'F-1',
        'depletionAgeWeeks': 65,
        'updatedAt': '2026-07-28T00:24:00Z',
        'syncStatus': 'pending',
        'dirtyAt': '2026-07-28T00:24:01Z',
        'lastSyncedAt': null,
        'syncError': 'previous failure',
      });

      expect(payload, {
        'id': 'flock-1',
        'customer_id': 'customer-1',
        'flock_id': 'F-1',
        'depletion_age_weeks': 65,
        'updated_at': '2026-07-28T00:24:00Z',
      });
    },
  );

  test(
    'refreshAvailability waits for Supabase initialization readiness',
    () async {
      var initializerCalled = false;
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async {
          initializerCalled = true;
          return false;
        },
      );

      final available = await service.refreshAvailability();

      expect(initializerCalled, isTrue);
      expect(available, isFalse);
    },
  );

  test(
    'refreshAvailability reloads config before declaring cloud unconfigured',
    () async {
      var configured = false;
      var reloadCalled = false;
      var initializerCalled = false;
      final service = SupabaseService(
        isConfiguredForTesting: () => configured,
        reloadConfigForTesting: () async {
          reloadCalled = true;
          configured = true;
        },
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async {
          initializerCalled = true;
          return true;
        },
      );

      final available = await service.refreshAvailability();

      expect(reloadCalled, isTrue);
      expect(initializerCalled, isTrue);
      expect(available, isTrue);
    },
  );

  test(
    'remote operations do not read client before initialization succeeds',
    () async {
      var clientRead = false;
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async => false,
        clientForTesting: () {
          clientRead = true;
          throw StateError('client should not be read before initialization');
        },
      );

      final sent = await service.sendPasswordReset('test@example.com');

      expect(sent, isFalse);
      expect(clientRead, isFalse);
    },
  );
}
