import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/network/network_status_monitor.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  SettingsProvider makeProvider({NetworkStatus status = NetworkStatus.online}) {
    final monitor = NetworkStatusMonitor(
      checkReachability: () async => status == NetworkStatus.online,
      connectivityStream: const Stream.empty(),
      initialStatus: status,
      startImmediately: false,
    );
    addTearDown(monitor.dispose);
    return SettingsProvider(networkStatus: monitor);
  }

  group('SettingsProvider.cloudStatus', () {
    test('persists the selected language code', () async {
      final provider = makeProvider();
      await Future<void>.delayed(Duration.zero);

      expect(provider.languageCode, 'en');
      await provider.setLanguageCode('ar');

      final prefs = await SharedPreferences.getInstance();
      expect(provider.languageCode, 'ar');
      expect(prefs.getString('pref_language_code'), 'ar');
      provider.dispose();
    });

    test('starts in online state when nothing else has happened', () {
      final provider = makeProvider();
      expect(provider.cloudStatus, CloudStatus.online);
      provider.dispose();
    });

    test('markSyncing flips status to syncing', () {
      final provider = makeProvider();
      provider.markSyncing();
      expect(provider.cloudStatus, CloudStatus.syncing);
      expect(provider.isSyncing, isTrue);
      provider.dispose();
    });

    test('recordSync(online: true) lands as CloudStatus.online', () async {
      final provider = makeProvider();
      // Drain the constructor's async `_load()` so its `prefs.getInt(...)` (0
      // in the empty mock) doesn't race past our recordSync below and clobber
      // pushed/pulled.
      await Future<void>.delayed(Duration.zero);
      provider.markSyncing();
      await provider.recordSync(online: true, pushed: 3, pulled: 5);
      expect(provider.cloudStatus, CloudStatus.online);
      expect(provider.isSyncing, isFalse);
      expect(provider.isOffline, isFalse);
      expect(provider.lastSyncPushed, 3);
      expect(provider.lastSyncPulled, 5);
      provider.dispose();
    });

    test('recordSync(online: false) lands as CloudStatus.offline', () async {
      final provider = makeProvider(status: NetworkStatus.offline);
      provider.markSyncing();
      await provider.recordSync(online: false, pushed: 0, pulled: 0);
      expect(provider.cloudStatus, CloudStatus.offline);
      expect(provider.isOffline, isTrue);
      provider.dispose();
    });

    test('recordSync with error lands as CloudStatus.error', () async {
      final provider = makeProvider();
      provider.markSyncing();
      await provider.recordSync(
        online: false,
        pushed: 0,
        pulled: 0,
        error: 'boom',
      );
      expect(provider.cloudStatus, CloudStatus.error);
      expect(provider.lastSyncError, 'boom');
      provider.dispose();
    });

    test(
      'a second recordSync(online: true) after an error returns to online',
      () async {
        final provider = makeProvider();
        provider.markSyncing();
        await provider.recordSync(
          online: false,
          pushed: 0,
          pulled: 0,
          error: 'boom',
        );
        expect(provider.cloudStatus, CloudStatus.error);
        provider.markSyncing();
        await provider.recordSync(online: true, pushed: 1, pulled: 2);
        expect(provider.cloudStatus, CloudStatus.online);
        expect(provider.lastSyncError, isNull);
        provider.dispose();
      },
    );
  });
}
