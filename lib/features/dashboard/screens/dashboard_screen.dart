import 'dart:async';

import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/utils/date_utils.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_intelligence_models.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/scope/scope_insights_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/govee_environmental_readings_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/sections/lab_analysis_dashboard_section.dart';
import 'package:hatchaudit/features/dashboard/widgets/dashboard_portfolio_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/dashboard_quality_strip.dart';
import 'package:hatchaudit/features/dashboard/widgets/dashboard_attention_section.dart';
import 'package:hatchaudit/features/dashboard/scope/scope_config.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/settings/providers/settings_provider.dart';
import 'package:hatchaudit/widgets/app_card.dart';

class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  final ScrollController _scrollController = ScrollController();
  final Set<String> _collapsedScopeStations = <String>{};
  SettingsProvider? _settingsProvider;
  String? _observedSyncTimestamp;
  bool _refreshingAfterSync = false;
  String? _preparedUserScope;
  bool _goveeExpanded = true;
  final GlobalKey _goveeKey = GlobalKey();
  late final Map<String, GlobalKey> _stationKeys = {
    for (final station in ScopeConfigRegistry.stations) station: GlobalKey(),
  };
  late final Map<String, GlobalKey> _sectorKeys = {
    for (final sector in ScopeConfigRegistry.sectors) sector.id: GlobalKey(),
  };

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final user = context.watch<AuthProvider>().user;
    final userScope = user == null
        ? 'signed-out'
        : '${user.id}|${user.role}|${user.status}|${user.customerId ?? ''}';
    if (_preparedUserScope != userScope) {
      _preparedUserScope = userScope;
      final dashboard = context.read<DashboardProvider>();
      dashboard.prepareForUser(user);
      context.read<ScopeComparisonProvider>().prepareForAccountChange();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _preparedUserScope != userScope) return;
        unawaited(dashboard.init(currentUser: user));
      });
    }
    SettingsProvider? settings;
    try {
      settings = context.read<SettingsProvider>();
    } on ProviderNotFoundException {
      // Some focused widget tests render DashboardScreen without app providers.
    }
    if (identical(settings, _settingsProvider)) return;
    _settingsProvider?.removeListener(_handleSettingsChange);
    _settingsProvider = settings;
    _observedSyncTimestamp = settings?.lastSyncTimestamp;
    settings?.addListener(_handleSettingsChange);
  }

  @override
  void dispose() {
    _settingsProvider?.removeListener(_handleSettingsChange);
    _scrollController.dispose();
    super.dispose();
  }

  void _handleSettingsChange() {
    final settings = _settingsProvider;
    final timestamp = settings?.lastSyncTimestamp;
    if (!mounted ||
        settings == null ||
        timestamp == null ||
        timestamp == _observedSyncTimestamp) {
      return;
    }
    _observedSyncTimestamp = timestamp;
    // Only a run that never reached the cloud (online == false) has nothing to
    // refresh from. A run that completed with some push failures still pulled
    // fresh rows, so it must still refresh the dashboard.
    if (!settings.lastSyncOnline) return;
    unawaited(_refreshAfterSync());
  }

  Future<void> _refreshAfterSync() async {
    if (_refreshingAfterSync) return;
    _refreshingAfterSync = true;
    try {
      await Future.wait([
        context.read<DashboardProvider>().refresh(),
        context.read<ScopeComparisonProvider>().refresh(),
      ]);
    } finally {
      _refreshingAfterSync = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<DashboardProvider>(
      builder: (context, provider, child) {
        // Keep the scope comparison in sync with the dashboard filter
        // (idempotent: only reloads when the filter actually changes).
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          context.read<ScopeComparisonProvider>().applyFilter(
            customerId: provider.selectedCustomerId,
            hatcheryId: provider.selectedHatcheryId,
            flockId: provider.selectedFlockId,
            bmkAge: provider.selectedBmkAge,
          );
        });
        return Scaffold(
          appBar: const GradientAppBar(title: 'Dashboard'),
          body: _buildContent(context, provider),
        );
      },
    );
  }

  Widget _buildCascadeFilter(DashboardProvider provider) {
    final selectedFlock = _selectedFlock(provider);

    return AppCard(
      key: const ValueKey('dashboard-filter-card'),
      margin: EdgeInsets.zero,
      color: AppColors.surfaceVariant,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Age is no longer a global filter — each sector carries its own
              // period picker + Incremental/Cumulative toggle.
              final customerFilter = _customerFilter(context, provider);
              final hatcheryFilter = _hatcheryFilter(context, provider);
              final flockFilter = _flockFilter(context, provider);

              if (constraints.maxWidth < 520) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    customerFilter,
                    const SizedBox(height: AppSizes.spaceSm),
                    hatcheryFilter,
                    const SizedBox(height: AppSizes.spaceSm),
                    Row(
                      children: [
                        Expanded(child: flockFilter),
                        if (provider.hasActiveFilters) ...[
                          const SizedBox(width: AppSizes.spaceXs),
                          _clearFilterButton(provider, compact: true),
                        ],
                      ],
                    ),
                  ],
                );
              }

              return Row(
                children: [
                  Expanded(child: customerFilter),
                  const SizedBox(width: AppSizes.spaceSm),
                  Expanded(child: hatcheryFilter),
                  const SizedBox(width: AppSizes.spaceSm),
                  Expanded(child: flockFilter),
                  if (provider.hasActiveFilters) ...[
                    const SizedBox(width: AppSizes.spaceSm),
                    _clearFilterButton(provider),
                  ],
                ],
              );
            },
          ),
          if (selectedFlock != null) ...[
            const SizedBox(height: AppSizes.spaceMd),
            const Divider(height: 1),
            const SizedBox(height: AppSizes.spaceMd),
            _buildCurrentFlockDetails(selectedFlock),
          ],
        ],
      ),
    );
  }

  FlockModel? _selectedFlock(DashboardProvider provider) {
    final selectedId = provider.selectedFlockId;
    if (selectedId == null) return null;

    for (final flock in provider.flocks) {
      if (flock.id == selectedId) return flock;
    }
    return null;
  }

  Widget _buildCurrentFlockDetails(FlockModel flock) {
    final ageWeeks = flock.currentAgeWeeks.toInt().clamp(0, 999);

    return LayoutBuilder(
      builder: (context, constraints) {
        final columnCount = constraints.maxWidth < 280
            ? 1
            : constraints.maxWidth < 700
            ? 2
            : 4;
        final gaps = (columnCount - 1) * AppSizes.spaceMd;
        final itemWidth = (constraints.maxWidth - gaps) / columnCount;
        final details = [
          _FlockDetailItem(
            icon: Icons.badge_outlined,
            label: 'Name',
            value: flock.flockId,
          ),
          _FlockDetailItem(
            icon: Icons.calendar_today_outlined,
            label: 'Current age',
            value: '$ageWeeks weeks',
          ),
          _FlockDetailItem(
            icon: Icons.category_outlined,
            label: 'Breed',
            value: flock.breed,
          ),
          _FlockDetailItem(
            icon: Icons.login_outlined,
            label: 'Entrance date',
            value: HatchDateUtils.formatDisplayDate(flock.entryDate),
          ),
        ];

        return Wrap(
          spacing: AppSizes.spaceMd,
          runSpacing: AppSizes.spaceMd,
          children: [
            for (final detail in details)
              SizedBox(width: itemWidth, child: detail),
          ],
        );
      },
    );
  }

  Widget _customerFilter(BuildContext context, DashboardProvider provider) {
    if (provider.isLoading && provider.customers.isEmpty) {
      return InputDecorator(
        decoration: _filterDecoration(context, 'Customer'),
        child: Text(
          context.tr('Loading customer…'),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: AppTextStyles.caption,
        ),
      );
    }
    final entries = <({String? value, String label})>[
      if (provider.canUseAllCustomers) (value: null, label: 'All customers'),
      ...provider.customers.map((c) => (value: c.id, label: c.name)),
    ];

    return DropdownButtonFormField<String>(
      initialValue: provider.selectedCustomerId,
      isExpanded: true,
      decoration: _filterDecoration(context, 'Customer'),
      selectedItemBuilder: (context) => [
        for (final entry in entries) _menuText(entry.label),
      ],
      items: [
        for (final entry in entries)
          DropdownMenuItem(value: entry.value, child: _menuText(entry.label)),
      ],
      onChanged: provider.setCustomer,
    );
  }

  Widget _flockFilter(BuildContext context, DashboardProvider provider) {
    final entries = <({String? value, String label})>[
      (value: null, label: 'All flocks'),
      ...provider.flocks.map((f) => (value: f.id, label: f.flockId)),
    ];

    return DropdownButtonFormField<String>(
      initialValue: provider.selectedFlockId,
      isExpanded: true,
      decoration: _filterDecoration(context, 'Flock'),
      selectedItemBuilder: (context) => [
        for (final entry in entries) _menuText(entry.label),
      ],
      items: [
        for (final entry in entries)
          DropdownMenuItem(value: entry.value, child: _menuText(entry.label)),
      ],
      onChanged: provider.setFlock,
    );
  }

  Widget _hatcheryFilter(BuildContext context, DashboardProvider provider) {
    final entries = <({String? value, String label})>[
      (value: null, label: 'Select hatchery'),
      ...provider.hatcheries.map((h) => (value: h.id, label: h.name)),
    ];
    return DropdownButtonFormField<String>(
      initialValue: provider.selectedHatcheryId,
      isExpanded: true,
      decoration: _filterDecoration(context, 'Hatchery'),
      selectedItemBuilder: (context) => [
        for (final entry in entries) _menuText(entry.label),
      ],
      items: [
        for (final entry in entries)
          DropdownMenuItem(value: entry.value, child: _menuText(entry.label)),
      ],
      onChanged: provider.selectedCustomerId == null
          ? null
          : provider.setHatchery,
    );
  }

  InputDecoration _filterDecoration(BuildContext context, String label) {
    return InputDecoration(
      labelText: context.tr(label),
      isDense: true,
      contentPadding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceSm,
        vertical: AppSizes.spaceSm,
      ),
    );
  }

  Widget _menuText(String text) {
    return Text(text, maxLines: 1, overflow: TextOverflow.ellipsis);
  }

  Widget _clearFilterButton(
    DashboardProvider provider, {
    bool compact = false,
  }) {
    if (compact) {
      return IconButton.filledTonal(
        tooltip: context.tr('Clear filters'),
        onPressed: provider.clearFilters,
        icon: const Icon(Icons.clear, size: 18),
      );
    }

    return TextButton.icon(
      onPressed: provider.clearFilters,
      icon: const Icon(Icons.clear, size: 16),
      label: const Text('Clear'),
    );
  }

  /// Pull-to-refresh: re-query both the dashboard data and the scope comparison
  /// for the current filter. Runs concurrently; the RefreshIndicator spins until
  /// both settle.
  Future<void> _handleRefresh(BuildContext context) {
    return Future.wait([
      context.read<DashboardProvider>().refresh(),
      context.read<ScopeComparisonProvider>().refresh(),
    ]);
  }

  void _toggleScopeStation(String station) {
    setState(() {
      if (!_collapsedScopeStations.add(station)) {
        _collapsedScopeStations.remove(station);
      }
    });
  }

  void _toggleGoveeSection() {
    setState(() => _goveeExpanded = !_goveeExpanded);
  }

  void _openDashboardSource(DashboardFinding finding) {
    final station = finding.station;
    final isGovee = station == 'Govee Environmental Readings';
    setState(() {
      if (isGovee) {
        _goveeExpanded = true;
      } else {
        _collapsedScopeStations.remove(station);
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final target = isGovee
          ? _goveeKey.currentContext
          : _sectorKeys[finding.sectorId]?.currentContext ??
                _stationKeys[station]?.currentContext;
      if (target != null) {
        Scrollable.ensureVisible(
          target,
          duration: const Duration(milliseconds: 350),
          curve: Curves.easeOut,
          alignment: 0.05,
        );
      }
    });
  }

  Widget _buildContent(BuildContext context, DashboardProvider provider) {
    if (provider.isLoading) {
      return ListView(
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceSm,
          vertical: AppSizes.spaceMd,
        ),
        children: [
          _buildCascadeFilter(provider),
          const SizedBox(
            height: 240,
            child: Center(child: CircularProgressIndicator()),
          ),
        ],
      );
    }

    if (provider.customers.isEmpty && provider.flocks.isEmpty) {
      return RefreshIndicator(
        onRefresh: () => _handleRefresh(context),
        child: LayoutBuilder(
          builder: (context, constraints) => SingleChildScrollView(
            controller: _scrollController,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.spaceSm,
              vertical: AppSizes.spaceMd,
            ),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Column(
                children: [
                  _buildCascadeFilter(provider),
                  const SizedBox(height: AppSizes.spaceXxl),
                  const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.dashboard_outlined,
                          size: 64,
                          color: AppColors.textDisabled,
                        ),
                        SizedBox(height: AppSizes.spaceLg),
                        Text(
                          'No customer or flock data yet',
                          style: AppTextStyles.title,
                        ),
                        SizedBox(height: AppSizes.spaceSm),
                        Text(
                          'Add a customer and flock to see dashboard insights.',
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () => _handleRefresh(context),
      child: ListView(
        key: const PageStorageKey('dashboard-main-scroll'),
        controller: _scrollController,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceSm,
          vertical: AppSizes.spaceMd,
        ),
        children: [
          _buildCascadeFilter(provider),
          const SizedBox(height: AppSizes.spaceLg),
          LabAnalysisDashboardSection(
            summaries: provider.labAnalysisSummaries,
            isLoading: provider.isLoadingLabAnalysis,
          ),
          const SizedBox(height: AppSizes.spaceLg),
          if (!provider.isOperationalScope) ...[
            DashboardPortfolioSummary(
              customerCount: provider.customers.length,
              hatcheryCount: provider.hatcheries.length,
              customerSelected: provider.selectedCustomerId != null,
            ),
          ] else ...[
            const DashboardQualityStrip(),
            const SizedBox(height: AppSizes.spaceLg),
            DashboardAttentionSection(onOpenSource: _openDashboardSource),
            const SizedBox(height: AppSizes.spaceLg),
            // Egg Storage & Egg Quality are presented by the Scopes section below
            // (same station card as every other audit station). The legacy bespoke
            // EggStorageSection / EggQualitySection cards were dropped to avoid
            // showing those two sectors twice on the dashboard.
            GoveeEnvironmentalReadingsSection(
              key: _goveeKey,
              captures: provider.goveeCaptures,
              isLoading: provider.isLoadingGoveeCaptures,
              expanded: _goveeExpanded,
              onToggle: _toggleGoveeSection,
              error: provider.goveeError,
            ),
            const SizedBox(height: AppSizes.spaceLg),
            ScopeInsightsSection(
              collapsedStations: _collapsedScopeStations,
              onStationToggle: _toggleScopeStation,
              stationKeys: _stationKeys,
              sectorKeys: _sectorKeys,
            ),
          ],
        ],
      ),
    );
  }
}

class _FlockDetailItem extends StatelessWidget {
  const _FlockDetailItem({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.primary),
        const SizedBox(width: AppSizes.spaceSm),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.caption),
              const SizedBox(height: AppSizes.spaceXs),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.subtitle.copyWith(
                  color: AppColors.textPrimary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
