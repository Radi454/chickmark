import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/utils/date_utils.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/services/sync/bg_sync_service.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/features/audits/models/session_filter.dart';
import 'package:hatchaudit/features/audits/providers/audits_list_provider.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_session_screen.dart';
import 'package:hatchaudit/features/audits/widgets/audit_access_guard.dart';
import 'package:hatchaudit/features/audits/widgets/audit_keyboard_dismiss.dart';
import 'package:hatchaudit/features/audits/widgets/session_filter_sheet.dart';
import 'package:hatchaudit/features/audits/widgets/session_card.dart';

class AuditsScreen extends StatefulWidget {
  const AuditsScreen({super.key});

  @override
  State<AuditsScreen> createState() => _AuditsScreenState();
}

class _AuditsScreenState extends State<AuditsScreen> {
  final AuditsListProvider _listProvider = AuditsListProvider();
  final BgSyncService _bgSync = BgSyncService();
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_handleScroll);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _listProvider.init();
    });
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    _listProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!AuditAccess.allowed(context)) return const AuditAccessDenied();

    final canEdit = context.select<AuthProvider, bool>(
      (auth) => auth.user?.canEditAudits ?? false,
    );

    return ChangeNotifierProvider<AuditsListProvider>.value(
      value: _listProvider,
      child: Consumer<AuditsListProvider>(
        builder: (context, list, _) {
          final resolver = _buildResolver(context.watch<CustomersProvider>());
          list.setResolver(resolver);

          return Scaffold(
            appBar: GradientAppBar(
              title: 'Audits',
              actions: [
                IconButton(
                  tooltip: 'Filter visits',
                  icon: Badge(
                    isLabelVisible: list.filter.hasFilters,
                    label: Text(list.filter.activeCount.toString()),
                    child: const Icon(Icons.filter_list),
                  ),
                  onPressed: _openFilters,
                ),
              ],
            ),
            body: AuditKeyboardDismiss(
              child: Column(
                children: [
                  _buildSyncHeader(),
                  _buildSearchBar(),
                  _buildActiveFilterChips(list),
                  Expanded(child: _buildBody(list, resolver, canEdit)),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  SessionDisplayResolver _buildResolver(CustomersProvider provider) {
    return SessionDisplayResolver(
      customerName: (id) => provider.customerById(id)?.name ?? id,
      hatcheryName: (id) => provider.hatcheryById(id)?.name ?? '',
      flockLabel: (id) => provider.flockById(id)?.flockId ?? (id ?? ''),
      flockBreed: (id) => provider.flockById(id)?.breed,
    );
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
                      _syncIcon(settings, isSyncing),
                      size: 18,
                      color: _syncColor(settings, isSyncing),
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
          hintText: 'Search customer, hatchery, flock, breed…',
          prefixIcon: const Icon(Icons.search, size: 20),
          suffixIcon: _searchController.text.isEmpty
              ? null
              : IconButton(
                  icon: const Icon(Icons.close, size: 18),
                  onPressed: () {
                    _searchController.clear();
                    _listProvider.setSearch('');
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
          _listProvider.setSearch(value);
        },
      ),
    );
  }

  Widget _buildActiveFilterChips(AuditsListProvider list) {
    final filter = list.filter;
    if (!filter.hasFilters) return const SizedBox.shrink();
    final provider = context.read<CustomersProvider>();
    final chips = <Widget>[];

    for (final status in filter.statuses) {
      chips.add(
        _filterChip(_statusLabel(status), () {
          final next = {...filter.statuses}..remove(status);
          list.setFilter(filter.copyWith(statuses: next));
        }),
      );
    }
    for (final sync in filter.syncStatuses) {
      chips.add(
        _filterChip('Sync: ${_capitalize(sync)}', () {
          final next = {...filter.syncStatuses}..remove(sync);
          list.setFilter(filter.copyWith(syncStatuses: next));
        }),
      );
    }
    if (filter.dateFrom != null && filter.dateTo != null) {
      chips.add(
        _filterChip(
          '${HatchDateUtils.formatDisplayDate(filter.dateFrom!)}–'
          '${HatchDateUtils.formatDisplayDate(filter.dateTo!)}',
          () => list.setFilter(filter.copyWith(clearDateRange: true)),
        ),
      );
    }
    if (filter.customerId != null) {
      chips.add(
        _filterChip(
          provider.customerById(filter.customerId!)?.name ?? 'Customer',
          () => list.setFilter(
            filter.copyWith(clearCustomerId: true, clearFlockId: true),
          ),
        ),
      );
    }
    if (filter.flockId != null) {
      chips.add(
        _filterChip(
          provider.flockById(filter.flockId)?.flockId ?? 'Flock',
          () => list.setFilter(filter.copyWith(clearFlockId: true)),
        ),
      );
    }
    chips.add(
      ActionChip(
        label: const Text('Clear all'),
        onPressed: list.clearFilters,
        visualDensity: VisualDensity.compact,
      ),
    );

    return Align(
      alignment: Alignment.centerLeft,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: Wrap(spacing: 6, runSpacing: 2, children: chips),
      ),
    );
  }

  Widget _filterChip(String label, VoidCallback onClear) {
    return InputChip(
      label: Text(label),
      onDeleted: onClear,
      visualDensity: VisualDensity.compact,
    );
  }

  Widget _buildBody(
    AuditsListProvider list,
    SessionDisplayResolver resolver,
    bool canEdit,
  ) {
    if (list.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }
    final sessions = list.visibleSessions;
    if (sessions.isEmpty) {
      return _buildEmptyState(list);
    }

    return RefreshIndicator(
      onRefresh: _syncNow,
      child: ListView.builder(
        controller: _scrollController,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        itemCount: sessions.length + 1,
        itemBuilder: (context, index) {
          if (index >= sessions.length) {
            return _buildListFooter(list);
          }
          final view = sessions[index];
          return SessionCard(
            view: view,
            resolver: resolver,
            canEdit: canEdit,
            onResumeVisit: () => _openStation(view.session),
            onOpenStation: (stationIndex) =>
                _openStation(view.session, stationIndex: stationIndex),
            onDelete: () => _deleteVisit(view.session),
            onClearStation: (stationKey) =>
                _clearStation(view.session, stationKey),
          );
        },
      ),
    );
  }

  Widget _buildListFooter(AuditsListProvider list) {
    if (list.isLoadingMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    if (!list.hasMore) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 16),
        child: Center(
          child: Text(
            'All visits loaded',
            style: TextStyle(color: AppColors.textSecondary),
          ),
        ),
      );
    }
    return const SizedBox(height: 24);
  }

  Widget _buildEmptyState(AuditsListProvider list) {
    final hasQuery = list.search.trim().isNotEmpty || list.filter.hasFilters;
    return RefreshIndicator(
      onRefresh: _syncNow,
      child: ListView(
        children: [
          const SizedBox(height: 120),
          Icon(Icons.assignment_outlined, size: 64, color: Colors.grey[400]),
          const SizedBox(height: 16),
          Center(
            child: Text(
              hasQuery ? 'No visits match your filters' : 'No visits yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              hasQuery
                  ? 'Try adjusting search or filters'
                  : 'Completed and in-progress visits will appear here',
              style: const TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ),
        ],
      ),
    );
  }

  void _handleScroll() {
    if (!_scrollController.hasClients) return;
    if (_scrollController.position.pixels >
        _scrollController.position.maxScrollExtent - 300) {
      _listProvider.loadMore();
    }
  }

  Future<void> _openFilters() async {
    final next = await showModalBottomSheet<SessionFilter>(
      context: context,
      isScrollControlled: true,
      builder: (_) => SessionFilterSheet(initialFilter: _listProvider.filter),
    );
    if (!mounted || next == null) return;
    await _listProvider.setFilter(next);
  }

  Future<void> _syncNow() async {
    if (_bgSync.isSyncing) return;
    final auth = context.read<AuthProvider>();
    final customers = context.read<CustomersProvider>();
    final settings = context.read<SettingsProvider>();
    await _bgSync.runBackgroundSync(
      authProvider: auth,
      customersProvider: customers,
      settingsProvider: settings,
    );
    if (!mounted) return;
    await _listProvider.refresh();
  }

  Future<void> _openStation(
    AuditSessionModel session, {
    int? stationIndex,
  }) async {
    final sessionProvider = context.read<AuditSessionProvider>();
    await sessionProvider.resumeSession(
      session.id,
      initialStationIndex: stationIndex,
    );
    if (!mounted) return;
    if (sessionProvider.error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(sessionProvider.error!)));
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChangeNotifierProvider.value(
          value: sessionProvider,
          child: const AuditSessionScreen(),
        ),
      ),
    );
    if (!mounted) return;
    await _listProvider.reloadSession(session.id);
  }

  Future<void> _deleteVisit(AuditSessionModel session) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete visit?'),
        content: const Text(
          'This permanently removes the visit, all its station data, and linked '
          'photos. This cannot be undone.',
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
      await context.read<AuditSessionProvider>().deleteSession(session.id);
      _listProvider.removeSession(session.id);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Visit removed')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not remove visit: $error')));
    }
  }

  Future<void> _clearStation(
    AuditSessionModel session,
    String stationKey,
  ) async {
    final label =
        AuditSessionProvider.stationDisplayLabels[stationKey] ?? 'station';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear station?'),
        content: Text('This removes all saved data for $label in this visit.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: AppColors.statusError,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    try {
      await _listProvider.clearStation(session, stationKey);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Station cleared')));
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not clear station: $error')),
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

  IconData _syncIcon(SettingsProvider settings, bool isSyncing) {
    if (isSyncing) return Icons.sync;
    if (!settings.lastSyncOnline) return Icons.cloud_off_outlined;
    return Icons.cloud_done_outlined;
  }

  Color _syncColor(SettingsProvider settings, bool isSyncing) {
    if (isSyncing) return AppColors.primary;
    if (!settings.lastSyncOnline) return AppColors.statusError;
    return AppColors.statusGood;
  }

  String _statusLabel(String status) =>
      status == 'completed' ? 'Completed' : 'In Progress';

  String _capitalize(String value) =>
      value.isEmpty ? value : value[0].toUpperCase() + value.substring(1);

  static String _relativeTime(DateTime time) {
    final diff = DateTime.now().difference(time);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return HatchDateUtils.formatDisplayDate(time);
  }
}
