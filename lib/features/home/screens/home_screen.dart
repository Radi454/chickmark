import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/app_page_route.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/navigation/shell_navigation_scope.dart';
import 'package:hatchaudit/core/utils/audit_type_labels.dart';
import 'package:hatchaudit/providers/customers_provider.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/audit_model.dart';
import 'package:hatchaudit/widgets/status_badge.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';
import 'package:hatchaudit/features/customers/widgets/add_customer_sheet.dart';
import 'package:hatchaudit/features/customers/screens/customer_detail_screen.dart';
import 'package:hatchaudit/features/customers/screens/audit_detail_screen.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/home/providers/home_provider.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/services/supabase/startup_sync_service.dart';
import 'package:hatchaudit/widgets/app_card.dart';
import 'package:hatchaudit/widgets/scale_button.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  bool _isSyncing = false;
  late final HomeProvider _homeProvider;

  @override
  void initState() {
    super.initState();
    _homeProvider = HomeProvider();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final currentUser = context.read<AuthProvider>().user;
      context.read<CustomersProvider>().loadCustomers(currentUser: currentUser);
      _homeProvider.load(currentUser: currentUser);
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
      appBar: const GradientAppBar(title: 'ChickMark'),
      body: ChangeNotifierProvider<HomeProvider>.value(
        value: _homeProvider,
        child: Consumer3<CustomersProvider, SettingsProvider, HomeProvider>(
          builder: (context, provider, settings, home, child) {
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
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                children: [
                  _buildKpiRow(home),
                  const SizedBox(height: AppSizes.spaceLg),
                  _buildQuickActions(context),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildRecentAudits(provider, home),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildAuditBreakdown(home),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildStatsRow(provider),
                  const SizedBox(height: AppSizes.spaceLg),
                  _buildActionButtons(context),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildTodayFocus(provider),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildContinueActiveAudits(provider),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildAttentionNeeded(context, provider),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildQuickShortcuts(provider),
                  const SizedBox(height: AppSizes.spaceXl),
                  _buildSyncStatus(context, provider, settings),
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
        final useRow = constraints.maxWidth >= 700;
        final cards = [
          _KpiCard(
            label: 'Audits this month',
            value: provider.auditsThisMonth.toString(),
            icon: Icons.assignment_outlined,
          ),
          _KpiCard(
            label: 'Active flocks',
            value: provider.activeFlocksCount.toString(),
            icon: Icons.egg_alt_outlined,
          ),
          _KpiCard(
            label: 'Last audit',
            value: provider.lastAuditDate ?? '—',
            icon: Icons.calendar_today_outlined,
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
    );
  }

  Widget _buildQuickActions(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;
    return _HomeSection(
      title: 'Quick Actions',
      child: Row(
        children: [
          Expanded(
            child: _QuickActionButton(
              label: 'New Audit',
              icon: Icons.add_circle_outline,
              onTap: canEdit ? () => _openAuditTypeSelection(context) : null,
            ),
          ),
          const SizedBox(width: AppSizes.spaceMd),
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
      child: home.recentAudits.isEmpty
          ? const _EmptyHomeMessage(
              icon: Icons.history_outlined,
              title: 'No recent audits',
              message: 'Recent audit activity will appear here.',
              color: AppColors.primary,
            )
          : Column(
              children: [
                for (var i = 0; i < home.recentAudits.length; i++) ...[
                  _RecentAuditTile(
                    audit: home.recentAudits[i],
                    customerName:
                        customers
                            .customerById(home.recentAudits[i].customerId)
                            ?.name ??
                        home.recentAudits[i].customerId,
                    flockLabel:
                        customers
                            .flockById(home.recentAudits[i].flockId)
                            ?.flockId ??
                        home.recentAudits[i].flockId ??
                        '--',
                    breed: customers
                        .flockById(home.recentAudits[i].flockId)
                        ?.breed,
                    onTap: () => _openAuditDetail(home.recentAudits[i]),
                  ),
                  if (i < home.recentAudits.length - 1)
                    const SizedBox(height: AppSizes.spaceMd),
                ],
              ],
            ),
    );
  }

  Widget _buildAuditBreakdown(HomeProvider provider) {
    return _HomeSection(
      title: 'Audit Type Breakdown',
      child: provider.auditsByType.isEmpty
          ? const _EmptyHomeMessage(
              icon: Icons.bar_chart_outlined,
              title: 'No audits this month',
              message: 'The monthly audit mix will appear here.',
              color: AppColors.primary,
            )
          : Column(
              children: provider.auditsByType.entries.map((entry) {
                final total = provider.auditsByType.values.fold<int>(
                  0,
                  (sum, value) => sum + value,
                );
                final ratio = total == 0 ? 0.0 : entry.value / total;
                return Padding(
                  padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
                  child: _BreakdownBar(
                    label: AuditTypeLabels.forAuditType(entry.key),
                    count: entry.value,
                    ratio: ratio,
                  ),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildStatsRow(CustomersProvider provider) {
    return Row(
      children: [
        Expanded(child: _buildStatCard('Customers', provider.customersCount)),
        const SizedBox(width: AppSizes.spaceMd),
        Expanded(
          child: _buildStatCard('Active Audits', provider.activeAuditsCount),
        ),
        const SizedBox(width: AppSizes.spaceMd),
        Expanded(
          child: _buildStatCard('Total Audits', provider.totalAuditsCount),
        ),
      ],
    );
  }

  Widget _buildStatCard(String label, int value) {
    return AppCard(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      child: Column(
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceXs),
          Text(
            '$value',
            style: AppTextStyles.metricLarge.copyWith(color: AppColors.primary),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons(BuildContext context) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;
    if (!canEdit) {
      return const SizedBox.shrink();
    }

    return Row(
      children: [
        Expanded(
          child: ScaleButton(
            onTap: () => _showAddCustomerSheet(context),
            child: OutlinedButton.icon(
              onPressed: () => _showAddCustomerSheet(context),
              icon: const Icon(Icons.add_business_outlined, size: 18),
              label: const Text('New Customer'),
              style: OutlinedButton.styleFrom(
                foregroundColor: AppColors.primary,
                side: const BorderSide(color: AppColors.primary),
                padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceMd),
              ),
            ),
          ),
        ),
        const SizedBox(width: AppSizes.spaceMd),
        Expanded(
          child: ScaleButton(
            onTap: () => _openAuditTypeSelection(context),
            child: ElevatedButton.icon(
              onPressed: () => _openAuditTypeSelection(context),
              icon: const Icon(Icons.add, size: 18),
              label: const Text('New Audit'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceMd),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildTodayFocus(CustomersProvider provider) {
    final activeAudits = _activeAudits(provider);
    final attentionCount = _attentionItems(context, provider).length;
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
            ),
            _FocusMetricCard(
              icon: Icons.priority_high_outlined,
              label: 'Attention',
              value: '$attentionCount',
              helper: attentionCount == 1 ? 'item to check' : 'items to check',
              color: AppColors.statusWarning,
            ),
            _FocusMetricCard(
              icon: Icons.fact_check_outlined,
              label: 'Ready',
              value: '$readyCustomers',
              helper: readyCustomers == 1
                  ? 'customer setup'
                  : 'customer setups',
              color: AppColors.completedText,
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

  Widget _buildContinueActiveAudits(CustomersProvider provider) {
    final activeAudits = _activeAudits(provider);

    return _HomeSection(
      title: 'Continue Active Audits',
      trailing: activeAudits.length > 3
          ? Text(
              '+${activeAudits.length - 3} more',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w700,
              ),
            )
          : null,
      child: activeAudits.isEmpty
          ? const _EmptyHomeMessage(
              icon: Icons.check_circle_outline,
              title: 'No active audits',
              message: 'Open audit work is clear.',
              color: AppColors.completedText,
            )
          : Column(
              children: [
                for (final audit in activeAudits.take(3)) ...[
                  _ActiveAuditCard(
                    audit: audit,
                    customerName:
                        provider.customerById(audit.customerId)?.name ??
                        audit.customerId,
                    flockLabel:
                        provider.flockById(audit.flockId)?.flockId ??
                        audit.flockId ??
                        '--',
                    breed:
                        provider.flockById(audit.flockId)?.breed ??
                        audit.soBreed ??
                        audit.hoBreed,
                    ageWeeks: provider
                        .flockById(audit.flockId)
                        ?.currentAgeWeeks
                        .round(),
                    onTap: () => _openAuditDetail(audit),
                  ),
                  if (audit != activeAudits.take(3).last)
                    const SizedBox(height: AppSizes.spaceMd),
                ],
              ],
            ),
    );
  }

  Widget _buildAttentionNeeded(
    BuildContext context,
    CustomersProvider provider,
  ) {
    final items = _attentionItems(context, provider);

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

  Widget _buildQuickShortcuts(CustomersProvider provider) {
    final shortcuts = _shortcuts(provider);

    return _HomeSection(
      title: 'Quick Shortcuts',
      child: shortcuts.isEmpty
          ? const _EmptyHomeMessage(
              icon: Icons.shortcut_outlined,
              title: 'No shortcuts yet',
              message: 'Recent customers and flocks will appear here.',
              color: AppColors.primary,
            )
          : LayoutBuilder(
              builder: (context, constraints) {
                final useTwoColumns = constraints.maxWidth >= 620;
                final tileWidth = useTwoColumns
                    ? (constraints.maxWidth - AppSizes.spaceMd) / 2
                    : constraints.maxWidth;

                return Wrap(
                  spacing: AppSizes.spaceMd,
                  runSpacing: AppSizes.spaceMd,
                  children: shortcuts
                      .map(
                        (shortcut) => SizedBox(
                          width: tileWidth,
                          child: _ShortcutTile(shortcut: shortcut),
                        ),
                      )
                      .toList(),
                );
              },
            ),
    );
  }

  Widget _buildSyncStatus(
    BuildContext context,
    CustomersProvider provider,
    SettingsProvider settings,
  ) {
    return _HomeSection(
      title: 'Sync & Offline',
      child: AppCard(
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
                    color: AppColors.infoBg,
                    borderRadius: BorderRadius.circular(AppSizes.iconRadius),
                  ),
                  child: const Icon(
                    Icons.cloud_done_outlined,
                    color: AppColors.infoText,
                  ),
                ),
                const SizedBox(width: AppSizes.spaceMd),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Local database ready', style: AppTextStyles.title),
                      const SizedBox(height: AppSizes.spaceSm),
                      Text(
                        _syncSubtitle(provider, settings),
                        style: AppTextStyles.caption,
                      ),
                    ],
                  ),
                ),
              ],
            );

            final syncButton = ElevatedButton.icon(
              onPressed: _isSyncing ? null : () => _syncNow(context, settings),
              icon: _isSyncing
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.sync, size: 18),
              label: Text(_isSyncing ? 'Syncing' : 'Sync Now'),
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
    );
  }

  List<_AttentionItem> _attentionItems(
    BuildContext context,
    CustomersProvider provider,
  ) {
    final canEdit = context.watch<AuthProvider>().user?.canEditAudits ?? false;
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

    if (provider.totalAuditsCount == 0 && canEdit) {
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

  List<_HomeShortcut> _shortcuts(CustomersProvider provider) {
    final shortcuts = <_HomeShortcut>[];
    final seenCustomerIds = <String>{};
    final recentCustomerIds = <String>[];

    for (final audit in provider.allAudits) {
      if (seenCustomerIds.add(audit.customerId)) {
        recentCustomerIds.add(audit.customerId);
      }
      if (recentCustomerIds.length == 3) break;
    }

    for (final customer in provider.allCustomers) {
      if (recentCustomerIds.length == 3) break;
      if (seenCustomerIds.add(customer.id)) {
        recentCustomerIds.add(customer.id);
      }
    }

    for (final customerId in recentCustomerIds) {
      final customer = provider.customerById(customerId);
      if (customer == null) continue;
      final flockCount = provider.flockCounts[customer.id] ?? 0;
      final hatcheryCount = provider.hatcheryCounts[customer.id] ?? 0;
      shortcuts.add(
        _HomeShortcut(
          icon: Icons.business_outlined,
          title: customer.name,
          subtitle: '$flockCount flocks · $hatcheryCount hatcheries',
          onTap: () => _openCustomerDetail(customer),
        ),
      );
    }

    final seenFlockIds = <String>{};
    for (final audit in provider.allAudits) {
      final flockId = audit.flockId;
      if (flockId == null || !seenFlockIds.add(flockId)) continue;
      final flock = provider.flockById(flockId);
      if (flock == null) continue;
      final customer = provider.customerById(flock.customerId);
      shortcuts.add(
        _HomeShortcut(
          icon: Icons.egg_outlined,
          title: flock.flockId,
          subtitle:
              '${customer?.name ?? flock.customerId} · ${flock.currentAgeWeeks.round()}w',
          onTap: customer == null ? null : () => _openCustomerDetail(customer),
        ),
      );
      if (seenFlockIds.length == 2) break;
    }

    return shortcuts.take(5).toList();
  }

  List<AuditModel> _activeAudits(CustomersProvider provider) {
    final audits = provider.allAudits
        .where((audit) => audit.status.toLowerCase() == 'active')
        .toList();
    audits.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return audits;
  }

  String _syncSubtitle(CustomersProvider provider, SettingsProvider settings) {
    final lastSync = settings.lastSyncTimestamp == null
        ? 'No manual sync yet'
        : 'Last sync ${_formatSyncTime(settings.lastSyncTimestamp!)}';
    return '$lastSync · ${provider.activeAuditsCount} active local audits';
  }

  String _formatSyncTime(String timestamp) {
    final parsed = DateTime.tryParse(timestamp)?.toLocal();
    if (parsed == null) return timestamp;
    return '${_formatDate(parsed)} ${_twoDigits(parsed.hour)}:${_twoDigits(parsed.minute)}';
  }

  String _formatDate(DateTime date) {
    return '${date.year}-${_twoDigits(date.month)}-${_twoDigits(date.day)}';
  }

  String _twoDigits(int value) => value.toString().padLeft(2, '0');

  void _openAuditTypeSelection(BuildContext context) {
    Navigator.push(
      context,
      AppPageRoute(builder: (context) => const AuditContextScreen()),
    );
  }

  void _openAuditDetail(AuditModel audit) {
    Navigator.push(
      context,
      AppPageRoute(builder: (context) => AuditDetailScreen(audit: audit)),
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
    setState(() => _isSyncing = true);
    try {
      final currentUser = context.read<AuthProvider>().user;
      await StartupSyncService().run(userId: currentUser?.id);
      if (!context.mounted) return;
      await context.read<CustomersProvider>().loadCustomers(
        currentUser: currentUser,
      );
      await _homeProvider.load(currentUser: currentUser);
      await settings.updateLastSync(DateTime.now().toIso8601String());
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Sync complete')));
    } catch (error) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Sync could not finish: $error')));
    } finally {
      if (mounted) {
        setState(() => _isSyncing = false);
      }
    }
  }
}

class _KpiCard extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;

  const _KpiCard({
    required this.label,
    required this.value,
    required this.icon,
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
              color: AppColors.activeBg,
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: Icon(icon, color: AppColors.primary),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.caption),
                const SizedBox(height: AppSizes.spaceSm),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.heading,
                ),
              ],
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

  const _QuickActionButton({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final button = ElevatedButton.icon(
      onPressed: onTap,
      icon: Icon(icon, size: 18),
      label: Text(label),
      style: ElevatedButton.styleFrom(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        disabledBackgroundColor: AppColors.textDisabled,
        disabledForegroundColor: AppColors.surface,
        padding: const EdgeInsets.symmetric(vertical: AppSizes.spaceMd),
      ),
    );

    if (onTap == null) {
      return button;
    }

    return ScaleButton(onTap: onTap, child: button);
  }
}

class _RecentAuditTile extends StatelessWidget {
  final AuditModel audit;
  final String customerName;
  final String flockLabel;
  final String? breed;
  final VoidCallback onTap;

  const _RecentAuditTile({
    required this.audit,
    required this.customerName,
    required this.flockLabel,
    this.breed,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final breedPart = breed != null && breed!.isNotEmpty ? ' · $breed' : '';
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
          AuditTypeLabels.forAuditType(audit.auditType),
          style: AppTextStyles.title,
        ),
        subtitle: Text(
          '$customerName · $flockLabel$breedPart · ${audit.date.toIso8601String().split('T').first}',
          style: AppTextStyles.caption,
        ),
        trailing: const Icon(Icons.chevron_right, color: AppColors.primary),
      ),
    );
  }
}

class _BreakdownBar extends StatelessWidget {
  final String label;
  final int count;
  final double ratio;

  const _BreakdownBar({
    required this.label,
    required this.count,
    required this.ratio,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: AppTextStyles.body)),
            Text('$count', style: AppTextStyles.caption),
          ],
        ),
        const SizedBox(height: AppSizes.spaceSm),
        ClipRRect(
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          child: LinearProgressIndicator(
            value: ratio,
            minHeight: AppSizes.spaceMd,
            backgroundColor: AppColors.inactiveTab,
            valueColor: const AlwaysStoppedAnimation<Color>(AppColors.primary),
          ),
        ),
      ],
    );
  }
}

class _HomeSection extends StatelessWidget {
  final String title;
  final Widget child;
  final Widget? trailing;

  const _HomeSection({required this.title, required this.child, this.trailing});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(child: Text(title, style: AppTextStyles.sectionTitle)),
            ?trailing,
          ],
        ),
        const SizedBox(height: AppSizes.spaceMd),
        child,
      ],
    );
  }
}

class _FocusMetricCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final String helper;
  final Color color;

  const _FocusMetricCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.helper,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
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
        ],
      ),
    );
  }
}

class _ActiveAuditCard extends StatelessWidget {
  final AuditModel audit;
  final String customerName;
  final String flockLabel;
  final String? breed;
  final int? ageWeeks;
  final VoidCallback onTap;

  const _ActiveAuditCard({
    required this.audit,
    required this.customerName,
    required this.flockLabel,
    required this.breed,
    required this.ageWeeks,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final setterId = audit.setterId ?? audit.soSetterId;
    final hatcherId = audit.hatcherId ?? audit.hoHatcherId;

    return AppCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.spaceSm,
                  vertical: AppSizes.spaceXs,
                ),
                decoration: BoxDecoration(
                  color: AppColors.ageBadgeBg,
                  borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
                ),
                child: Text(
                  ageWeeks != null ? '${ageWeeks}w' : '--',
                  style: AppTextStyles.badgeLabel.copyWith(
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.spaceSm),
              Expanded(
                child: Text(
                  customerName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
              ),
              StatusBadge(status: audit.status),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Text(
            '$flockLabel${breed != null ? ' · $breed' : ''} · ${audit.date.toString().split(' ')[0]}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption,
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Row(
            children: [
              Expanded(
                child: Text(
                  '${AuditTypeLabels.forAuditType(audit.auditType)}${setterId != null ? ' · $setterId' : ''}${hatcherId != null ? ' · $hatcherId' : ''}',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ),
              const SizedBox(width: AppSizes.spaceMd),
              Text(
                'Continue',
                style: AppTextStyles.caption.copyWith(
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
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

class _HomeShortcut {
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  const _HomeShortcut({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });
}

class _ShortcutTile extends StatelessWidget {
  final _HomeShortcut shortcut;

  const _ShortcutTile({required this.shortcut});

  @override
  Widget build(BuildContext context) {
    return AppCard(
      margin: EdgeInsets.zero,
      onTap: shortcut.onTap,
      child: Row(
        children: [
          Container(
            width: AppSizes.iconContainerSm,
            height: AppSizes.iconContainerSm,
            decoration: BoxDecoration(
              color: AppColors.infoBg,
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: Icon(shortcut.icon, color: AppColors.infoText),
          ),
          const SizedBox(width: AppSizes.spaceMd),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  shortcut.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title,
                ),
                const SizedBox(height: AppSizes.spaceXs),
                Text(
                  shortcut.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          const Icon(Icons.chevron_right, color: AppColors.primary),
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
