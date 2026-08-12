import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/services/supabase/supabase_service.dart';

void main() {
  SupabaseService offlineService() => SupabaseService(
        isConfiguredForTesting: () => true,
        reloadConfigForTesting: () async {},
        initializeSupabaseForTesting: () async => false,
        checkNetworkAvailableForTesting: () async => false,
        clientForTesting: () => throw StateError('client must not be touched'),
      );

  test('deleteRows throws when Supabase is unavailable', () async {
    await expectLater(
      offlineService().deleteRows('audit_sessions', ['row-1']),
      throwsStateError,
    );
  });

  test('deleteRows still no-ops silently for empty id lists', () async {
    await offlineService().deleteRows('audit_sessions', const []);
  });
}
