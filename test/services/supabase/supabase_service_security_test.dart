import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';

void main() {
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
