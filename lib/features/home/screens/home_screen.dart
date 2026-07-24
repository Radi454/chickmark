import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/app_page_route.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/constants/supabase_config.dart';
import 'package:hatchaudit/core/navigation/shell_navigation_scope.dart';
import 'package:hatchaudit/core/security/security_policy.dart';
import 'package:hatchaudit/core/utils/date_utils.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/audit_session_model.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/incoming_change.dart';
import 'package:hatchaudit/data/repositories/audit_session_repository.dart';
import 'package:hatchaudit/data/repositories/sync_conflict_repository.dart';
import 'package:hatchaudit/features/audits/providers/audit_session_provider.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/audits/screens/audit_session_screen.dart';
import 'package:hatchaudit/features/audits/screens/audit_station_selection_screen.dart';
import 'package:hatchaudit/features/customers/widgets/add_customer_sheet.dart';
import 'package:hatchaudit/features/customers/screens/customer_detail_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/home/providers/home_provider.dart';
import 'package:hatchaudit/features/home/widgets/incomplete_visit_card.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/widgets/app_card.dart';
import 'package:hatchaudit/widgets/flock_pair_icon.dart';
import 'package:hatchaudit/widgets/scale_button.dart';

class HomeScreen extends StatefulWidget {
  final bool loadInitialData;
  final HomeProvider? homeProvider;

  const HomeScreen({super.key, this.loadInitialData = true, this.homeProvider});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeProvider _homeProvider;
  bool _isOpeningIncompleteSession = false;
  // Tracks the previously observed cloud status so we only fire the offline
  // SnackBar on a transition INTO offline (online→offline, syncing→offline,
  // error→offline). This avoids:
  //  - spamming the bar on every rebuild while still offline,
  //  - missing a re-offline event after the user briefly went online again.
  CloudStatus? _lastSeenStatus;

  @override
  void initState() {
    super.initState();
    _homeProvider = widget.homeProvider ?? HomeProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!widget.loadInitialData) return;
      final currentUser = context.read<AuthProvider>().user;
      context.read<CustomersProvider>().loadCustomers(currentUser: currentUser);
      _homeProvider.load(currentUser: currentUser);
    });
  }

  void _maybeShowOfflineSnackBar(SettingsProvider settings) {
    final current = settings.cloudStatus;
    final previous = _lastSeenStatus;
    // Update synchronously — multiple builds inside one frame must not each
    // schedule a SnackBar callback.
    _lastSeenStatus = current;
    if (current != CloudStatus.offline) return;
    if (previous == CloudStatus.offline) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Offline — sync paused. Local data still available.'),
          duration: Duration(seconds: 4),
        ),
      );
    });
  }

  @override
  void dispose() {
    _homeProvider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Home',
        titleLeading: SizedBox(
          key: const ValueKey('home-appbar-logo'),
          width: 44,
          height: 52,
          child: Center(
            child: Semantics(
              label: context.tr('Home'),
              child: const Icon(
                Icons.home_rounded,
                color: Colors.white,
                size: 28,
              ),
            ),
          ),
        ),
      ),
      body: ChangeNotifierProvider<HomeProvider>.value(
        value: _homeProvider,
        child: Consumer3<CustomersProvider, SettingsProvider, HomeProvider>(
          builder: (context, provider, settings, home, child) {
            _maybeShowOfflineSnackBar(settings);
            if (provider.isLoading &&
                provider.allCustomers.isEmpty &&
                home.isLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            return RefreshIndicator(
              onRefresh: () async {
                final currentUser = context.read<AuthProvider>().user;
                await provider.loadCustomers(currentUser: currentUser);
                await home.load(currentUser: currentUser);
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.spaceMd,
                  AppSizes.spaceMd,
                  AppSizes.spaceMd,
                  AppSizes.cardPadding,
                ),
                children: [
                  _buildKpiRow(home),
                  const SizedBox(height: AppSizes.spaceLg),
                  _buildQuickActions(context),
                  if (home.activeSessions.isNotEmpty) ...[
                    const SizedBox(height: AppSizes.spaceLg),
                    _buildIncompleteVisits(provider, home),
                  ],
                  const SizedBox(height: AppSizes.spaceLg),
                  _buildRecentAudits(provider, home),
                  const SizedBox(height: AppSizes.spaceLg),
                  _buildTodayFocus(provider, home),
                  const SizedBox(height: AppSizes.spaceLg),
                  _buildAttentionNeeded(context, provider, home),
                  const SizedBox(height: AppSizes.spaceLg),
                  _buildSyncStatus(context, provider, settings, home),
                  const SizedBox(height: AppSizes.fabBottomPadding),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildKpiRow(HomeProvider provider) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final useRow = constraints.maxWidth >= 360;
        final cards = [
          _KpiCard(
            label: 'Audits this month',
            value: provider.auditsThisMonth.toString(),
            icon: Icons.assignment_outlined,
          ),
          _KpiCard(
            label: 'Active flocks',
            value: provider.activeFlocksCount.toString(),
            iconWidget: const FlockPairIcon(
              key: ValueKey('home-active-flocks-flock-icon'),
              color: AppColors.primary,
              size: 20,
            ),
          ),
          _KpiCard(
            label: 'Last audit',
            value: provider.lastAuditDate ?? '—',
            icon: Icons.calendar_today_outlined,
          ),
        ];

        if (useRow) {
          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSizes.spaceSm),
                  Expanded(child: cards[i]),
                ],
              ],
            ),
          );
        }

        return Column(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(height: AppSizes.spaceMd),
              cards[i],
            ],
          ],
        );
      },
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final canEdit =
        AuthSecurityPolicy.isDebugAuthBypassEnabled ||
        (context.watch<AuthProvider>().user?.canEditAudits ?? false);
    return _HomeSection(
      title: 'Quick Actions',
      child: Row(
        children: [
          Expanded(
            child: _QuickActionButton(
              label: 'New Audit',
              icon: Icons.add_circle_outline,
              isPrimary: true,
              onTap: canEdit ? () => _openAuditTypeSelection(context) : null,
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: _QuickActionButton(
              label: 'Dashboard',
              icon: Icons.dashboard_outlined,
              onTap: () => ShellNavigationScope.maybeOf(context)?.switchTab(1),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRecentAudits(CustomersProvider customers, HomeProvider home) {
    return _HomeSection(
      title: 'Recent Audits',
      child: home.recentSessions.isEmpty
          ? const _EmptyHomeMessage(
              icon: Icons.history_outlined,
              title: 'No recent audits',
              message: 'Recent audit activity will appear here.',
              color: AppColors.primary,
            )
          : Column(
              children: [
                for (var i = 0; i < home.recentSessions.length; i++) ...[
                  _RecentSessionTile(
                    session: home.recentSessions[i],
                    customerName:
                        customers
                            .customerById(home.recentSessions[i].customerId)
                            ?.name ??
                        home.recentSessions[i].customerId,
                    flockLabel:
                        customers
                            .flockById(home.recentSessions[i].flockId)
                            ?.flockId ??
                        home.recentSessions[i].flockId,
                    breed: customers
                        .flockById(home.recentSessions[i].flockId)
                        ?.breed,
                    onTap: () => _openSession(home.recentSessions[i]),
                  ),
                  if (i < home.recentSessions.length - 1)
                    const SizedBox(height: AppSizes.spaceMd),
                ],
              ],
            ),
    );
  }

  Widget _buildIncompleteVisits(
    CustomersProvider customers,
    HomeProvider home,
  ) {
    return KeyedSubtree(
      key: const ValueKey('home-incomplete-visits-section'),
      child: _HomeSection(
        title: 'Incomplete Visits',
        child: Column(
          children: [
            for (var i = 0; i < home.activeSessions.length; i++) ...[
              IncompleteVisitCard(
                session: home.activeSessions[i],
                customerName:
                    customers
                        .customerById(home.activeSessions[i].customerId)
                        ?.name ??
                    home.activeSessions[i].customerId,
                flockLabel:
                    customers
                        .flockById(home.activeSessions[i].flockId)
                        ?.flockId ??
                    home.activeSessions[i].flockId,
                breed: customers
                    .flockById(home.activeSessions[i].flockId)
                    ?.breed,
                missingStationLabels: home.activeSessions[i].selectedStationKeys
                    .where(
                      (key) => !home.activeSessions[i].stationsCompleted
                          .contains(key),
                    )
                    .map(
                      (key) =>
                          AuditSessionProvider.stationDisplayLabels[key] ?? key,
                    )
                    .toList(growable: false),
                onTap: () => _openIncompleteSession(home.activeSessions[i]),
              ),
              if (i < home.activeSessions.length - 1)
                const SizedBox(height: AppSizes.spaceMd),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTodayFocus(CustomersProvider provider, HomeProvider home) {
    final activeAudits = home.activeSessions;
    final attentionItems = _attentionItems(context, provider, home);
    final attentionCount = attentionItems.length;
    final canEdit =
        AuthSecurityPolicy.isDebugAuthBypassEnabled ||
        (context.watch<AuthProvider>().user?.canEditAudits ?? false);
    final readyCustomers = provider.allCustomers.where((customer) {
      final flockCount = provider.flockCounts[customer.id] ?? 0;
      final hatcheryCount = provider.hatcheryCounts[customer.id] ?? 0;
      return flockCount > 0 && hatcheryCount > 0;
    }).length;

    return _HomeSection(
      title: 'Today\'s Focus',
      child: LayoutBuilder(
        builder: (context, constraints) {
          final useRow = constraints.maxWidth >= 700;
          final cards = [
            _FocusMetricCard(
              icon: Icons.play_circle_outline,
              label: 'Continue',
              value: '${activeAudits.length}',
              helper: activeAudits.length == 1
                  ? 'active audit'
                  : 'active audits',
              color: AppColors.primary,
              onTap: activeAudits.isEmpty
                  ? null
                  : () => _openSession(activeAudits.first),
            ),
            _FocusMetricCard(
              icon: Icons.priority_high_outlined,
              label: 'Attention',
              value: '$attentionCount',
              helper: attentionCount == 1 ? 'item to check' : 'items to check',
              color: AppColors.statusWarning,
              onTap: attentionItems.isNotEmpty
                  ? attentionItems.first.onAction
                  : null,
            ),
            _FocusMetricCard(
              icon: Icons.fact_check_outlined,
              label: 'Ready',
              value: '$readyCustomers',
              helper: readyCustomers == 1
                  ? 'customer setup'
                  : 'customer setups',
              color: AppColors.completedText,
              onTap: canEdit && readyCustomers > 0
                  ? () => _openAuditTypeSelection(context)
                  : null,
            ),
          ];

          if (useRow) {
            return Row(
              children: [
                for (var i = 0; i < cards.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSizes.spaceMd),
                  Expanded(child: cards[i]),
                ],
              ],
            );
          }

          return Column(
            children: [
              for (var i = 0; i < cards.length; i++) ...[
                if (i > 0) const SizedBox(height: AppSizes.spaceMd),
                cards[i],
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _buildAttentionNeeded(
    BuildContext context,
    CustomersProvider provider,
    HomeProvider home,
  ) {
    final items = _attentionItems(context, provider, home);

    return _HomeSection(
      title: 'Attention Needed',
      child: items.isEmpty
          ? const _EmptyHomeMessage(
              icon: Icons.verified_outlined,
              title: 'All clear',
              message: 'Customer, flock, and hatchery setup looks ready.',
              color: AppColors.completedText,
            )
          : Column(
              children: [
                for (var i = 0; i < items.length; i++) ...[
                  _AttentionTile(item: items[i]),
                  if (i < items.length - 1)
                    const SizedBox(height: AppSizes.spaceMd),
                ],
              ],
            ),
    );
  }

  Widget _buildSyncStatus(
    BuildContext context,
    CustomersProvider provider,
    SettingsProvider settings,
    HomeProvider home,
  ) {
    var visuals = _cloudStatusVisuals(settings.cloudStatus);
    if (settings.cloudStatus == CloudStatus.offline &&
        !SupabaseConfig.isConfigured) {
      visuals = _CloudStatusVisuals(
        icon: visuals.icon,
        bg: visuals.bg,
        fg: visuals.fg,
        title: 'Cloud not configured',
      );
    }
    return _HomeSection(
      title: 'Sync & Offline',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (settings.hasIncomingChanges) ...[
            _buildIncomingChangesCard(context, settings),
            const SizedBox(height: AppSizes.spaceMd),
          ],
          AppCard(
            margin: EdgeInsets.zero,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final useRow = constraints.maxWidth >= 620;
                final statusContent = Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: AppSizes.iconContainerMd,
                      height: AppSizes.iconContainerMd,
                      decoration: BoxDecoration(
                        color: visuals.bg,
                        borderRadius: BorderRadius.circular(
                          AppSizes.iconRadius,
                        ),
                      ),
                      child: Icon(visuals.icon, color: visuals.fg),
                    ),
                    const SizedBox(width: AppSizes.spaceMd),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(visuals.title, style: AppTextStyles.title),
                          const SizedBox(height: AppSizes.spaceSm),
                          Text(
                            _syncSubtitle(provider, settings, home),
                            style: AppTextStyles.caption,
                          ),
                        ],
                      ),
                    ),
                  ],
                );

                final syncButton = ElevatedButton.icon(
                  onPressed: settings.isSyncing
                      ? null
                      : () => _syncNow(context, settings),
                  icon: settings.isSyncing
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Icon(
                          settings.isOffline ? Icons.cloud_off : Icons.sync,
                          size: 18,
                        ),
                  label: Text(
                    settings.isSyncing
                        ? 'Syncing'
                        : (settings.isOffline ? 'Retry' : 'Sync Now'),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                  ),
                );

                if (useRow) {
                  return Row(
                    children: [
                      Expanded(child: statusContent),
                      const SizedBox(width: AppSizes.spaceLg),
                      syncButton,
                    ],
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    statusContent,
                    const SizedBox(height: AppSizes.spaceLg),
                    syncButton,
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Highlighted notice at the top of the Sync sector listing audit sessions
  /// that arrived from another device. Tapping one opens it (and acknowledges
  /// just that item); "Dismiss all" clears the whole set.
  Widget _buildIncomingChangesCard(
    BuildContext context,
    SettingsProvider settings,
  ) {
    final sessions = settings.incomingChanges;
    final other = settings.otherIncomingCount;
    final total = sessions.length + other;
    final shown = sessions.take(3).toList();
    final moreSessions = sessions.length - shown.length;

    return AppCard(
      margin: EdgeInsets.zero,
      color: AppColors.infoBg,
      border: Border.all(color: AppColors.primary.withValues(alpha: 0.35)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(
                Icons.cloud_download_outlined,
                color: AppColors.infoText,
                size: AppSizes.iconSm,
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text(
                  total == 1 ? '1 new from cloud' : '$total new from cloud',
                  style: AppTextStyles.title.copyWith(
                    color: AppColors.infoText,
                  ),
                ),
              ),
              TextButton(
                onPressed: () => settings.clearIncomingChanges(),
                style: TextButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSizes.spaceSm,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: const Text('Dismiss all'),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceXs),
          const Text(
            'Synced from another device',
            style: AppTextStyles.caption,
          ),
          if (shown.isNotEmpty) const SizedBox(height: AppSizes.spaceMd),
          for (var i = 0; i < shown.length; i++) ...[
            _IncomingChangeTile(
              item: shown[i],
              onTap: () => _openIncomingSession(shown[i], settings),
            ),
            if (i < shown.length - 1) const SizedBox(height: AppSizes.spaceSm),
          ],
          if (moreSessions > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.spaceSm),
              child: Text(
                '+$moreSessions more session${moreSessions == 1 ? '' : 's'}',
                style: AppTextStyles.caption,
              ),
            ),
          if (other > 0)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.spaceXs),
              child: Text(
                'and $other other record${other == 1 ? '' : 's'} updated',
                style: AppTextStyles.caption,
              ),
            ),
        ],
      ),
    );
  }

  Future<void> _openIncomingSession(
    IncomingChange item,
    SettingsProvider settings,
  ) async {
    await settings.acknowledgeIncomingChange(item.key);
    final session = await AuditSessionRepository().getSessionById(item.rowId);
    if (!mounted) return;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That audit is no longer available.')),
      );
      return;
    }
    await _openSession(session);
  }

  List<_AttentionItem> _attentionItems(
    BuildContext context,
    CustomersProvider provider,
    HomeProvider home,
  ) {
    final canEdit =
        AuthSecurityPolicy.isDebugAuthBypassEnabled ||
        (context.watch<AuthProvider>().user?.canEditAudits ?? false);
    final items = <_AttentionItem>[];

    if (provider.allCustomers.isEmpty) {
      items.add(
        _AttentionItem(
          icon: Icons.add_business_outlined,
          title: 'Add your first customer',
          message:
              'Customers are needed before flocks, hatcheries, and audits.',
          color: AppColors.primary,
          actionLabel: canEdit ? 'Add' : null,
          onAction: canEdit ? () => _showAddCustomerSheet(context) : null,
        ),
      );
      return items;
    }

    final customersWithoutFlocks = provider.allCustomers
        .where((customer) => (provider.flockCounts[customer.id] ?? 0) == 0)
        .toList();
    if (customersWithoutFlocks.isNotEmpty) {
      final first = customersWithoutFlocks.first;
      items.add(
        _AttentionItem(
          icon: Icons.egg_alt_outlined,
          title: '${customersWithoutFlocks.length} customer setup incomplete',
          message: 'Add a flock before starting audits for ${first.name}.',
          color: AppColors.statusWarning,
          actionLabel: 'Open',
          onAction: () => _openCustomerDetail(first),
        ),
      );
    }

    final customersWithoutHatcheries = provider.allCustomers
        .where((customer) => (provider.hatcheryCounts[customer.id] ?? 0) == 0)
        .toList();
    if (customersWithoutHatcheries.isNotEmpty) {
      final first = customersWithoutHatcheries.first;
      items.add(
        _AttentionItem(
          icon: Icons.factory_outlined,
          title: '${customersWithoutHatcheries.length} hatchery record missing',
          message: 'Register hatchery details for ${first.name}.',
          color: AppColors.statusWarning,
          actionLabel: 'Open',
          onAction: () => _openCustomerDetail(first),
        ),
      );
    }

    if (canEdit && home.openConflictCount > 0) {
      items.add(
        _AttentionItem(
          icon: Icons.merge_type_outlined,
          title:
              '${home.openConflictCount} sync conflict'
              '${home.openConflictCount == 1 ? '' : 's'} — review',
          message:
              'Local edits won over cloud on these rows. Confirm or restore.',
          color: AppColors.statusWarning,
          actionLabel: 'Review',
          onAction: () => _openSyncConflicts(),
        ),
      );
    }

    final estimatedCustomers = provider.allCustomers
        .where((customer) => provider.customerHasEstimatedFlockAge(customer.id))
        .toList();
    if (estimatedCustomers.isNotEmpty) {
      final first = estimatedCustomers.first;
      items.add(
        _AttentionItem(
          icon: Icons.event_available_outlined,
          title: '${estimatedCustomers.length} estimated flock age',
          message:
              'Confirm entry dates when you have records for ${first.name}.',
          color: AppColors.primaryDark,
          actionLabel: 'Review',
          onAction: () => _openCustomerDetail(first),
        ),
      );
    }

    if (home.recentSessions.isEmpty && canEdit) {
      items.add(
        _AttentionItem(
          icon: Icons.assignment_add,
          title: 'Create the first audit',
          message: 'Start a new audit when customer setup is ready.',
          color: AppColors.primary,
          actionLabel: 'Start',
          onAction: () => _openAuditTypeSelection(context),
        ),
      );
    }

    return items.take(4).toList();
  }

  String _syncSubtitle(
    CustomersProvider provider,
    SettingsProvider settings,
    HomeProvider home,
  ) {
    final lastSync = settings.lastSyncTimestamp == null
        ? 'No manual sync yet'
        : 'Last sync ${_formatSyncTime(settings.lastSyncTimestamp!)} · ↑${settings.lastSyncPushed} ↓${settings.lastSyncPulled}';
    return '$lastSync · ${home.activeSessions.length} active local audits';
  }

  _CloudStatusVisuals _cloudStatusVisuals(CloudStatus status) {
    switch (status) {
      case CloudStatus.online:
        return const _CloudStatusVisuals(
          icon: Icons.cloud_done_outlined,
          bg: AppColors.infoBg,
          fg: AppColors.infoText,
          title: 'Local database ready',
        );
      case CloudStatus.syncing:
        return const _CloudStatusVisuals(
          icon: Icons.cloud_sync_outlined,
          bg: AppColors.infoBg,
          fg: AppColors.infoText,
          title: 'Syncing with cloud',
        );
      case CloudStatus.offline:
        return _CloudStatusVisuals(
          icon: Icons.cloud_off_outlined,
          bg: AppColors.statusWarning.withValues(alpha: 0.1),
          fg: AppColors.statusWarning,
          title: 'Offline — using local data',
        );
      case CloudStatus.error:
        return _CloudStatusVisuals(
          icon: Icons.cloud_off,
          bg: AppColors.statusWarning.withValues(alpha: 0.1),
          fg: AppColors.statusWarning,
          title: 'Sync error — tap Retry',
        );
    }
  }

  String _formatSyncTime(String timestamp) {
    final parsed = DateTime.tryParse(timestamp)?.toLocal();
    if (parsed == null) return timestamp;
    return HatchDateUtils.formatDisplayDateTime(parsed);
  }

  void _openAuditTypeSelection(BuildContext context) {
    Navigator.push(
      context,
      AppPageRoute(builder: (context) => const AuditContextScreen()),
    );
  }

  Future<void> _openIncompleteSession(AuditSessionModel session) async {
    if (_isOpeningIncompleteSession) return;
    _isOpeningIncompleteSession = true;
    try {
      await _openStationWorkflow(session);
      if (!mounted) return;
      await _reloadHomeData();
    } finally {
      _isOpeningIncompleteSession = false;
    }
  }

  Future<void> _openSession(AuditSessionModel session) async {
    if (session.status == 'in_progress') {
      await _openStationSelectionForSession(session);
    } else {
      await _openStationWorkflow(session, initialStationIndex: 0);
    }

    if (!mounted) return;
    await _reloadHomeData();
  }

  Future<void> _openStationSelectionForSession(
    AuditSessionModel session,
  ) async {
    final customersProvider = context.read<CustomersProvider>();
    final selectedFlock = customersProvider.flockById(session.flockId);
    if (selectedFlock == null) {
      await _openStationWorkflow(session);
      return;
    }

    await Navigator.push(
      context,
      AppPageRoute(
        builder: (context) => AuditStationSelectionScreen(
          customerId: session.customerId,
          flockId: session.flockId,
          hatcheryId: session.hatcheryId,
          selectedFlock: selectedFlock,
          visitDate: session.date,
          existingSessionId: session.id,
        ),
      ),
    );
  }

  Future<void> _openStationWorkflow(
    AuditSessionModel session, {
    int? initialStationIndex,
  }) async {
    final sessionProvider = context.read<AuditSessionProvider>();
    await sessionProvider.resumeSession(
      session.id,
      initialStationIndex: initialStationIndex,
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
      AppPageRoute(
        builder: (context) => ChangeNotifierProvider.value(
          value: sessionProvider,
          child: const AuditSessionScreen(),
        ),
      ),
    );
  }

  void _openCustomerDetail(CustomerModel customer) {
    Navigator.push(
      context,
      AppPageRoute(
        builder: (context) => CustomerDetailScreen(customer: customer),
      ),
    );
  }

  Future<void> _openSyncConflicts() async {
    final repo = SyncConflictRepository();
    final conflicts = await repo.getOpenConflicts();
    if (!mounted) return;
    final user = context.read<AuthProvider>().user;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => _SyncConflictsSheet(
        conflicts: conflicts,
        onMarkAllReviewed: () async {
          await repo.markAllReviewed(reviewedBy: user?.id ?? 'unknown');
        },
      ),
    );
    if (!mounted) return;
    await _homeProvider.load(currentUser: user);
  }

  Future<void> _showAddCustomerSheet(BuildContext context) async {
    final customer = await showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => const AddCustomerSheet(),
    );
    if (!context.mounted || customer == null) return;
    _openCustomerDetail(customer);
  }

  Future<void> _syncNow(BuildContext context, SettingsProvider settings) async {
    final collectIncoming = settings.hasSyncedBefore;
    settings.markSyncing();
    try {
      final currentUser = context.read<AuthProvider>().user;
      final outcome = await StartupSyncService().run(
        userId: currentUser?.id,
        collectIncoming: collectIncoming,
      );
      if (!context.mounted) return;
      await context.read<CustomersProvider>().loadCustomers(
        currentUser: currentUser,
      );
      await _homeProvider.load(currentUser: currentUser);
      await settings.recordSync(
        online: outcome.online,
        pushed: outcome.pushed,
        pulled: outcome.pulled,
        incoming: outcome.incomingSessions,
        otherIncoming: outcome.otherIncomingCount,
        acknowledgeIncoming: true,
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            outcome.online
                ? 'Sync complete · ↑${outcome.pushed} ↓${outcome.pulled}'
                : 'Offline — using local data',
          ),
        ),
      );
    } catch (error) {
      await settings.recordSync(
        online: false,
        pushed: 0,
        pulled: 0,
        error: error.toString(),
      );
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync could not finish: $error')));
    }
  }

  Future<void> _reloadHomeData() async {
    final currentUser = context.read<AuthProvider>().user;
    await context.read<CustomersProvider>().loadCustomers(
      currentUser: currentUser,
    );
    await _homeProvider.load(currentUser: currentUser);
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData? icon;
  final Widget? iconWidget;

  const _KpiCard({
    required this.label,
    required this.value,
    this.icon,
    this.iconWidget,
  }) : assert(icon != null || iconWidget != null);

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  color: AppColors.activeBg,
                  borderRadius: BorderRadius.circular(AppSizes.iconRadius),
                ),
                child: Center(
                  child:
                      iconWidget ??
                      Icon(icon, color: AppColors.primary, size: 18),
                ),
              ),
              const Spacer(),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            label,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSizes.spaceXs),
          SizedBox(
            height: 40,
            child: Align(
              alignment: AlignmentDirectional.topStart,
              child: Text(
                value,
                key: label == 'Last audit'
                    ? const ValueKey('home-last-audit-value')
                    : null,
                maxLines: 2,
                softWrap: true,
                overflow: TextOverflow.visible,
                style: AppTextStyles.heading.copyWith(
                  fontSize: 16,
                  height: 1.2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _QuickActionButton extends StatelessWidget {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isPrimary;

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
    this.isPrimary = false,
  });

  @override
  Widget build(BuildContext context) {
    final style = isPrimary
        ? ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.textDisabled,
            disabledForegroundColor: AppColors.surface,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceSm),
            minimumSize: const Size.fromHeight(42),
          )
        : ElevatedButton.styleFrom(
            backgroundColor: AppColors.surface,
            foregroundColor: AppColors.primary,
            disabledBackgroundColor: AppColors.textDisabled,
            disabledForegroundColor: AppColors.surface,
            side: const BorderSide(color: AppColors.borderDefault),
            elevation: 0,
            padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceSm),
            minimumSize: const Size.fromHeight(42),
          );
    final button = ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 17),
      label: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      style: style,
    );

    if (onTap == null) {
      return button;
    }

    return ScaleButton(onTap: onTap, child: button);
  }
}

class _RecentSessionTile extends StatelessWidget {
  final AuditSessionModel session;
  final String customerName;
  final String flockLabel;
  final String? breed;
  final VoidCallback onTap;

  const _RecentSessionTile({
    required this.session,
    required this.customerName,
    required this.flockLabel,
    this.breed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final breedPart = breed != null && breed!.isNotEmpty ? ' · $breed' : '';
    final stationCount = session.selectedStationKeys.length;
    final completedCount = session.stationsCompleted.length;
    final statusColor = session.status == 'completed'
        ? AppColors.completedText
        : AppColors.primary;
    return AppCard(
      margin: EdgeInsets.zero,
      padding: EdgeInsets.zero,
      onTap: onTap,
      child: ListTile(
        onTap: onTap,
        leading: const Icon(
          Icons.assignment_outlined,
          color: AppColors.primary,
        ),
        title: Text(
          session.status == 'completed' ? 'Completed visit' : 'Active visit',
          style: AppTextStyles.title,
        ),
        subtitle: Text(
          '$customerName · $flockLabel$breedPart · ${HatchDateUtils.formatDisplayDate(session.date)}',
          style: AppTextStyles.caption,
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              '$completedCount/$stationCount',
              style: AppTextStyles.caption.copyWith(
                color: statusColor,
                fontWeight: FontWeight.w800,
              ),
            ),
            const Icon(Icons.chevron_right, color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}

class _HomeSection extends StatelessWidget {
  final String title;
  final Widget child;

  const _HomeSection({required this.title, required this.child});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                title,
                style: AppTextStyles.title.copyWith(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceSm),
        child,
      ],
    );
  }
}

class _IncomingChangeTile extends StatelessWidget {
  final IncomingChange item;
  final VoidCallback onTap;

  const _IncomingChangeTile({required this.item, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final isNew = item.isNew;
    final chipFg = isNew ? AppColors.statusGood : AppColors.statusActive;
    final chipBg = isNew ? AppColors.statusGoodBg : AppColors.statusActiveBg;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceXs),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.title.copyWith(
                      fontSize: 13,
                      color: AppColors.textPrimary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    item.subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.caption,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSizes.spaceSm),
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.spaceSm,
                vertical: 2,
              ),
              decoration: BoxDecoration(
                color: chipBg,
                borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
              ),
              child: Text(
                isNew ? 'NEW' : 'UPDATED',
                style: AppTextStyles.caption.copyWith(
                  color: chipFg,
                  fontWeight: FontWeight.w800,
                  fontSize: 11,
                ),
              ),
            ),
            const Icon(
              Icons.chevron_right,
              color: AppColors.primary,
              size: AppSizes.iconSm,
            ),
          ],
        ),
      ),
    );
  }
}

class _FocusMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;
  final VoidCallback? onTap;

  const _FocusMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: Icon(icon, color: color, size: AppSizes.iconSm),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: AppSizes.spaceXs),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      value,
                      style: AppTextStyles.heading.copyWith(color: color),
                    ),
                    const SizedBox(width: AppSizes.spaceSm),
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(
                          bottom: AppSizes.spaceXs,
                        ),
                        child: Text(
                          helper,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.caption,
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (onTap != null) ...[
            const SizedBox(width: AppSizes.spaceSm),
            Icon(Icons.chevron_right, color: color, size: AppSizes.iconSm),
          ],
        ],
      ),
    );
  }
}

class _CloudStatusVisuals {
  final IconData icon;
  final Color bg;
  final Color fg;
  final String title;

  const _CloudStatusVisuals({
    required this.icon,
    required this.bg,
    required this.fg,
    required this.title,
  });
}

class _AttentionItem {
  final IconData icon;
  final String title;
  final String message;
  final Color color;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _AttentionItem({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
    this.actionLabel,
    this.onAction,
  });
}

class _AttentionTile extends StatelessWidget {
  final _AttentionItem item;

  const _AttentionTile({required this.item});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      border: Border.all(color: item.color.withValues(alpha: 0.18)),
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              color: item.color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: Icon(item.icon, color: item.color, size: AppSizes.iconSm),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
                const SizedBox(height: AppSizes.spaceXs),
                Text(
                  item.message,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          if (item.actionLabel != null && item.onAction != null) ...[
            const SizedBox(width: AppSizes.spaceSm),
            TextButton(
              onPressed: item.onAction,
              child: Text(item.actionLabel!),
            ),
          ],
        ],
      ),
    );
  }
}

class _EmptyHomeMessage extends StatelessWidget {
  final IconData icon;
  final String title;
  final String message;
  final Color color;

  const _EmptyHomeMessage({
    required this.icon,
    required this.title,
    required this.message,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerMd,
            height: AppSizes.iconContainerMd,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: Icon(icon, color: color),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.title),
                const SizedBox(height: AppSizes.spaceXs),
                Text(message, style: AppTextStyles.caption),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _SyncConflictsSheet extends StatelessWidget {
  final List<SyncConflict> conflicts;
  final Future<void> Function() onMarkAllReviewed;

  const _SyncConflictsSheet({
    required this.conflicts,
    required this.onMarkAllReviewed,
  });

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
          ),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSizes.spaceLg,
                  AppSizes.spaceMd,
                  AppSizes.spaceLg,
                  AppSizes.spaceSm,
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        'Sync conflicts (${conflicts.length})',
                        style: AppTextStyles.heading.copyWith(fontSize: 16),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ],
                ),
              ),
              const Padding(
                padding: EdgeInsets.symmetric(horizontal: AppSizes.spaceLg),
                child: Text(
                  'These rows were edited on this device after the cloud copy. Local edits were kept. Mark reviewed once confirmed.',
                  style: AppTextStyles.caption,
                ),
              ),
              const SizedBox(height: AppSizes.spaceMd),
              Expanded(
                child: conflicts.isEmpty
                    ? const Center(child: Text('No open conflicts'))
                    : ListView.separated(
                        controller: scrollController,
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSizes.spaceLg,
                        ),
                        itemCount: conflicts.length,
                        separatorBuilder: (_, _) =>
                            const SizedBox(height: AppSizes.spaceSm),
                        itemBuilder: (context, index) {
                          final conflict = conflicts[index];
                          return AppCard(
                            margin: EdgeInsets.zero,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  '${conflict.tableName} · ${conflict.rowId}',
                                  style: AppTextStyles.title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: AppSizes.spaceXs),
                                Text(
                                  'Local: ${conflict.localUpdatedAt?.toLocal() ?? '—'}',
                                  style: AppTextStyles.caption,
                                ),
                                Text(
                                  'Cloud: ${conflict.remoteUpdatedAt?.toLocal() ?? '—'}',
                                  style: AppTextStyles.caption,
                                ),
                                Text(
                                  'Kept: ${conflict.winner}',
                                  style: AppTextStyles.caption.copyWith(
                                    color: AppColors.statusWarning,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSizes.spaceLg),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: conflicts.isEmpty
                        ? null
                        : () async {
                            await onMarkAllReviewed();
                            if (context.mounted) Navigator.of(context).pop();
                          },
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Mark all reviewed'),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
