import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/govee_capture_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../providers/customers_provider.dart';
import '../../../services/sync/bg_sync_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../../settings/providers/settings_provider.dart';
import '../providers/govee_capture_provider.dart';
import '../providers/govee_records_provider.dart';
import '../widgets/govee_floating_launcher.dart';

/// Standalone history of Govee environmental captures, grouped by visit-day,
/// with real per-row cloud sync status. Capturing happens via the floating
/// launcher; this screen is read-only history.
class GoveeRecordsScreen extends StatefulWidget {
  const GoveeRecordsScreen({super.key});

  @override
  State<GoveeRecordsScreen> createState() => _GoveeRecordsScreenState();
}

class _GoveeRecordsScreenState extends State<GoveeRecordsScreen> {
  final GoveeRecordsProvider _provider = GoveeRecordsProvider();
  final BgSyncService _bgSync = BgSyncService();
  final TextEditingController _searchController = TextEditingController();
  String? _lastMergedCaptureId;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _provider.refresh());
  }

  @override
  void dispose() {
    _searchController.dispose();
    _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider<GoveeRecordsProvider>.value(
      value: _provider,
      child: Consumer<GoveeRecordsProvider>(
        builder: (context, records, _) {
          final customers = context.watch<CustomersProvider>();
          final govee = context.watch<GoveeCaptureProvider>();
          _mergeFinishedCapture(records, govee.finishedCapture);
          records.setResolver(
            GoveeRecordResolver(
              customerName: (id) => customers.customerById(id)?.name ?? id,
              hatcheryName: (id) => customers.hatcheryById(id)?.name ?? id,
            ),
          );
          return Scaffold(
            appBar: const GradientAppBar(title: 'Govee Records'),
            body: Column(
              children: [
                _buildSyncHeader(),
                _buildSearchBar(),
                Expanded(child: _buildBody(records)),
              ],
            ),
          );
        },
      ),
    );
  }

  void _mergeFinishedCapture(
    GoveeRecordsProvider records,
    GoveeDailyCaptureModel? capture,
  ) {
    if (capture == null || capture.id == _lastMergedCaptureId) return;
    _lastMergedCaptureId = capture.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      records.mergeSavedCapture(capture);
    });
  }

  Widget _buildSyncHeader() {
    final settings = context.watch<SettingsProvider>();
    return AnimatedBuilder(
      animation: _bgSync,
      builder: (context, _) {
        final isSyncing = _bgSync.isSyncing;
        return Material(
          color: AppColors.surface,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
            child: Column(
              children: [
                Row(
                  children: [
                    Icon(
                      isSyncing
                          ? Icons.sync
                          : (settings.lastSyncOnline
                                ? Icons.cloud_done_outlined
                                : Icons.cloud_off_outlined),
                      size: 18,
                      color: isSyncing
                          ? AppColors.primary
                          : (settings.lastSyncOnline
                                ? AppColors.statusGood
                                : AppColors.statusError),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        isSyncing
                            ? (_bgSync.message.isEmpty
                                  ? 'Syncing…'
                                  : _bgSync.message)
                            : _lastSyncLabel(settings),
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textSecondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    TextButton.icon(
                      onPressed: isSyncing ? null : _syncNow,
                      icon: const Icon(Icons.sync, size: 18),
                      label: const Text('Sync Now'),
                    ),
                  ],
                ),
                if (isSyncing)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: _bgSync.progress == 0 ? null : _bgSync.progress,
                        minHeight: 3,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 6),
      child: TextField(
        controller: _searchController,
        decoration: InputDecoration(
          hintText: 'Search customer, hatchery, place…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _provider.setSearch('');
                  },
                ),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() {});
          _provider.setSearch(value);
        },
      ),
    );
  }

  Widget _buildBody(GoveeRecordsProvider records) {
    if (records.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final groups = records.visibleGroups;
    if (groups.isEmpty) {
      return _buildEmptyState(records);
    }
    return RefreshIndicator(
      onRefresh: _syncNow,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: groups.length,
        itemBuilder: (context, index) {
          final customers = context.read<CustomersProvider>();
          final group = groups[index];
          return _GoveeRecordCard(
            group: group,
            customerName:
                customers.customerById(group.customerId)?.name ??
                group.customerId,
            hatcheryName:
                customers.hatcheryById(group.hatcheryId)?.name ??
                group.hatcheryId,
            onRerecord: _rerecordCapture,
            onDelete: _confirmDeleteCapture,
          );
        },
      ),
    );
  }

  Widget _buildEmptyState(GoveeRecordsProvider records) {
    final hasQuery = records.search.trim().isNotEmpty;
    return RefreshIndicator(
      onRefresh: _syncNow,
      child: ListView(
        children: [
          const SizedBox(height: 120),
          Icon(
            Icons.device_thermostat_outlined,
            size: 64,
            color: Colors.grey[400],
          ),
          const SizedBox(height: 16),
          Center(
            child: Text(
              hasQuery
                  ? 'No Govee records match your search'
                  : 'No Govee records yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              hasQuery
                  ? 'Try another customer, hatchery, or place'
                  : 'Recorded environmental captures appear here',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _syncNow() async {
    if (_bgSync.isSyncing) return;
    await _bgSync.runBackgroundSync(
      authProvider: context.read<AuthProvider>(),
      customersProvider: context.read<CustomersProvider>(),
      settingsProvider: context.read<SettingsProvider>(),
    );
    if (!mounted) return;
    await _provider.refresh();
  }

  /// Re-opens the capture panel pre-scoped to this place/date. Saving replaces
  /// the existing capture (same customer + hatchery + place + date).
  Future<void> _rerecordCapture(GoveeDailyCaptureModel capture) async {
    final govee = context.read<GoveeCaptureProvider>();
    final isMachine =
        capture.place == TemperaturePlace.insideSetter ||
        capture.place == TemperaturePlace.insideHatcher;
    await govee.configure(
      customerId: capture.customerId,
      hatcheryId: capture.hatcheryId,
      place: capture.place,
      captureDate: capture.captureDate,
      stationKey: capture.stationKey,
      machineId: capture.machineId,
      captureTarget: isMachine
          ? GoveeCaptureTarget.insideMachine
          : GoveeCaptureTarget.room,
    );
    if (!mounted) return;
    await openGoveeFloatingCapturePanel(context);
    if (!mounted) return;
    await _provider.refresh();
  }

  Future<void> _confirmDeleteCapture(GoveeDailyCaptureModel capture) async {
    final readings = capture.readingCount;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete capture?'),
        content: Text(
          'This permanently removes the ${capture.place.label} capture '
          '($readings ${readings == 1 ? 'reading' : 'readings'}). '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_outline),
            label: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await _provider.deleteCapture(capture);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Capture removed')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not remove capture: $error')),
      );
    }
  }

  String _lastSyncLabel(SettingsProvider settings) {
    if (settings.lastSyncError != null && !settings.lastSyncOnline) {
      return 'Offline — last sync failed';
    }
    final raw = settings.lastSyncTimestamp;
    if (raw == null) return 'Not synced yet';
    final parsed = DateTime.tryParse(raw);
    if (parsed == null) return 'Synced';
    return 'Synced ${_relativeTime(parsed)}';
  }

  static String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return HatchDateUtils.formatDisplayDate(time);
  }
}

class _GoveeRecordCard extends StatefulWidget {
  final GoveeRecordGroup group;
  final String customerName;
  final String hatcheryName;
  final ValueChanged<GoveeDailyCaptureModel> onRerecord;
  final ValueChanged<GoveeDailyCaptureModel> onDelete;

  const _GoveeRecordCard({
    required this.group,
    required this.customerName,
    required this.hatcheryName,
    required this.onRerecord,
    required this.onDelete,
  });

  @override
  State<_GoveeRecordCard> createState() => _GoveeRecordCardState();
}

class _GoveeRecordCardState extends State<_GoveeRecordCard> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final group = widget.group;
    final readings = group.totalReadings;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Column(
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          '${widget.customerName} · ${widget.hatcheryName}',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      _SyncChip(sync: group.sync),
                      Icon(
                        _expanded ? Icons.expand_less : Icons.expand_more,
                        color: AppColors.textSecondary,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    '${HatchDateUtils.formatDisplayDateKey(group.captureDate)} · '
                    '${group.captures.length} ${group.captures.length == 1 ? 'spot' : 'spots'} · '
                    '$readings ${readings == 1 ? 'reading' : 'readings'}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(height: 1),
            for (final capture in group.captures)
              _CaptureRow(
                capture: capture,
                onRerecord: () => widget.onRerecord(capture),
                onDelete: () => widget.onDelete(capture),
              ),
          ],
        ],
      ),
    );
  }
}

class _CaptureRow extends StatelessWidget {
  final GoveeDailyCaptureModel capture;
  final VoidCallback onRerecord;
  final VoidCallback onDelete;

  const _CaptureRow({
    required this.capture,
    required this.onRerecord,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Row(
        children: [
          const Icon(
            Icons.device_thermostat,
            size: 20,
            color: AppColors.primary,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  capture.place.label,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  _statsLine(capture),
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textSecondary,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          _SyncDot(sync: capture.syncStatus),
          PopupMenuButton<String>(
            tooltip: 'Capture actions',
            icon: const Icon(
              Icons.more_vert,
              size: 18,
              color: AppColors.textSecondary,
            ),
            onSelected: (value) {
              if (value == 'rerecord') onRerecord();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (context) => const [
              PopupMenuItem<String>(
                value: 'rerecord',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.fiber_manual_record_outlined),
                  title: Text('Re-record'),
                ),
              ),
              PopupMenuItem<String>(
                value: 'delete',
                child: ListTile(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    Icons.delete_outline,
                    color: AppColors.statusError,
                  ),
                  title: Text('Delete'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _statsLine(GoveeDailyCaptureModel capture) {
    final parts = <String>[
      if (capture.tempAvg != null) '${capture.tempAvg!.toStringAsFixed(1)}°',
      if (capture.rhAvg != null) '${capture.rhAvg!.toStringAsFixed(0)}% RH',
      '${capture.readingCount} ${capture.readingCount == 1 ? 'reading' : 'readings'}',
    ];
    return parts.join(' · ');
  }
}

class _SyncChip extends StatelessWidget {
  final String sync;

  const _SyncChip({required this.sync});

  @override
  Widget build(BuildContext context) {
    final (icon, color, label) = switch (sync) {
      'synced' => (Icons.cloud_done_outlined, AppColors.statusGood, 'Synced'),
      'failed' => (Icons.cloud_off_outlined, AppColors.statusError, 'Failed'),
      _ => (Icons.cloud_upload_outlined, _pendingColor, 'Pending'),
    };
    return Padding(
      padding: const EdgeInsets.only(right: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncDot extends StatelessWidget {
  final String sync;

  const _SyncDot({required this.sync});

  @override
  Widget build(BuildContext context) {
    final color = switch (sync) {
      'synced' => AppColors.statusGood,
      'failed' => AppColors.statusError,
      _ => _pendingColor,
    };
    return Tooltip(
      message:
          'Sync: ${sync.isEmpty ? sync : '${sync[0].toUpperCase()}${sync.substring(1)}'}',
      child: Container(
        width: 10,
        height: 10,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      ),
    );
  }
}

const Color _pendingColor = Color(0xFFB45309); // amber-700
