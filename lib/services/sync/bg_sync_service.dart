import 'package:flutter/foundation.dart';

import '../../features/auth/providers/auth_provider.dart';
import '../../features/settings/providers/settings_provider.dart';
import '../../providers/customers_provider.dart';
import '../supabase/startup_sync_service.dart';
import '../../core/debug/startup_timer.dart';
import 'app_sync_coordinator.dart';

enum BgSyncState { idle, syncing, completed, failed }

class BgSyncService extends ChangeNotifier {
  BgSyncState _state = BgSyncState.idle;
  String _message = '';
  double _progress = 0;

  BgSyncState get state => _state;
  String get message => _message;
  double get progress => _progress;

  bool get isSyncing => _state == BgSyncState.syncing;
  bool get isComplete =>
      _state == BgSyncState.completed || _state == BgSyncState.failed;

  Future<AppSyncResult> runBackgroundSync({
    required AuthProvider authProvider,
    required CustomersProvider customersProvider,
    SettingsProvider? settingsProvider,
  }) async {
    if (_state == BgSyncState.syncing) return AppSyncResult.success;

    _state = BgSyncState.syncing;
    _message = 'Syncing...';
    _progress = 0;
    notifyListeners();
    settingsProvider?.markSyncing();
    StartupTimer.lap('bg_sync_start');

    try {
      final user = authProvider.user;
      final syncService = StartupSyncService();

      final outcome = await syncService.run(
        userId: user?.id,
        canPush: user?.canEditAudits ?? false,
        collectIncoming: settingsProvider?.hasSyncedBefore ?? false,
        onProgress: (progress) {
          _progress = progress.value;
          _message = progress.message;
          notifyListeners();
        },
      );

      StartupTimer.lap('bg_sync_complete');

      if (!customersProvider.isLoading) {
        await customersProvider.loadCustomers(currentUser: user);
      }

      StartupTimer.lap('bg_sync_customers_loaded');

      _state = BgSyncState.completed;
      _message = outcome.hasFailures
          ? 'Sync incomplete — ${outcome.failureSummary}'
          : 'Sync complete';
      _progress = 1;
      await settingsProvider?.recordSync(
        online: outcome.online,
        pushed: outcome.pushed,
        pulled: outcome.pulled,
        incoming: outcome.incomingSessions,
        otherIncoming: outcome.otherIncomingCount,
        error: outcome.failureSummary,
      );
      notifyListeners();
      StartupTimer.report();
      return outcome.online ? AppSyncResult.success : AppSyncResult.offline;
    } catch (e) {
      debugPrint('[BG_SYNC] Background sync failed: $e');
      StartupTimer.lap('bg_sync_failed');
      _state = BgSyncState.failed;
      _message = 'Sync failed — offline data available';
      _progress = 1;
      await settingsProvider?.recordSync(
        online: false,
        pushed: 0,
        pulled: 0,
        error: e.toString(),
      );
      notifyListeners();
      StartupTimer.report();
      return AppSyncResult.transientFailure;
    }
  }
}
