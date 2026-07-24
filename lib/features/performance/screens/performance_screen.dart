import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../data/models/broiler_daily_record_models.dart';
import '../providers/performance_provider.dart';
import '../widgets/active_concerns_panel.dart';
import '../widgets/performance_actions_panel.dart';
import '../widgets/performance_status_grid.dart';
import '../widgets/performance_trend_panel.dart';
import 'broiler_daily_entry_screen.dart';

class PerformanceScreen extends StatefulWidget {
  const PerformanceScreen({super.key, this.provider, this.onOpenQuickEntry});

  final PerformanceProvider? provider;
  final VoidCallback? onOpenQuickEntry;

  @override
  State<PerformanceScreen> createState() => _PerformanceScreenState();
}

class _PerformanceScreenState extends State<PerformanceScreen> {
  late final PerformanceProvider _provider;
  late final bool _ownsProvider;

  @override
  void initState() {
    super.initState();
    _ownsProvider = widget.provider == null;
    _provider = widget.provider ?? PerformanceProvider();
    if (_ownsProvider) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _provider.load());
    }
  }

  @override
  void dispose() {
    if (_ownsProvider) _provider.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _provider,
      child: _PerformanceView(onOpenQuickEntry: widget.onOpenQuickEntry),
    );
  }
}

class _PerformanceView extends StatelessWidget {
  const _PerformanceView({this.onOpenQuickEntry});

  final VoidCallback? onOpenQuickEntry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Broiler performance'),
      body: Consumer<PerformanceProvider>(
        builder: (context, provider, _) {
          final snapshot = provider.snapshot;
          return Column(
            children: [
              _ScopeBar(provider: provider),
              if (provider.isLoading) const LinearProgressIndicator(),
              if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Text(
                    provider.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: provider.refresh,
                  child: ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                    children: [
                      _ContextStrip(snapshot: snapshot),
                      const SizedBox(height: 12),
                      _Section(
                        title: 'Current status',
                        icon: Icons.speed_outlined,
                        child: PerformanceStatusGrid(metrics: snapshot.metrics),
                      ),
                      _Section(
                        title: 'Trends',
                        icon: Icons.show_chart,
                        child: PerformanceTrendPanel(
                          points: snapshot.trendPoints,
                        ),
                      ),
                      _Section(
                        title: 'Active concerns',
                        icon: Icons.warning_amber_outlined,
                        child: ActiveConcernsPanel(concerns: snapshot.concerns),
                      ),
                      _Section(
                        title: 'Audits and corrective actions',
                        icon: Icons.assignment_turned_in_outlined,
                        child: PerformanceActionsPanel(
                          visits: snapshot.visits,
                          actions: snapshot.actions,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('performance-quick-entry'),
        onPressed: () => _openQuickEntry(context),
        icon: const Icon(Icons.edit_note_outlined),
        label: Text(context.tr('Daily quick entry')),
      ),
    );
  }

  void _openQuickEntry(BuildContext context) {
    if (onOpenQuickEntry != null) {
      onOpenQuickEntry!();
      return;
    }
    Navigator.of(context)
        .push(
          MaterialPageRoute<void>(
            builder: (_) => const BroilerDailyEntryScreen(),
          ),
        )
        .then((_) {
          if (context.mounted) context.read<PerformanceProvider>().refresh();
        });
  }
}

class _ScopeBar extends StatelessWidget {
  const _ScopeBar({required this.provider});

  final PerformanceProvider provider;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerLowest,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
        child: Row(
          children: [
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: provider.selectedCustomerId,
                decoration: InputDecoration(labelText: context.tr('Customer')),
                items: provider.customers
                    .map(
                      (customer) => DropdownMenuItem(
                        value: customer.id,
                        child: Text(
                          customer.name,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: provider.selectCustomer,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: provider.selectedFarmId,
                decoration: InputDecoration(
                  labelText: context.tr('Broiler farm'),
                ),
                items: provider.farms
                    .map(
                      (farm) => DropdownMenuItem(
                        value: farm.id,
                        child: Text(farm.name, overflow: TextOverflow.ellipsis),
                      ),
                    )
                    .toList(),
                onChanged: provider.selectedCustomerId == null
                    ? null
                    : provider.selectFarm,
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 190,
              child: DropdownButtonFormField<String>(
                initialValue: provider.selectedFlockId,
                decoration: InputDecoration(labelText: context.tr('Flock')),
                items: provider.flocks
                    .map(
                      (flock) => DropdownMenuItem(
                        value: flock.id,
                        child: Text(
                          flock.flockId,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    )
                    .toList(),
                onChanged: provider.selectedFarmId == null
                    ? null
                    : provider.selectFlock,
              ),
            ),
            const SizedBox(width: 8),
            OutlinedButton.icon(
              onPressed: () => _pickRange(context),
              icon: const Icon(Icons.date_range_outlined),
              label: Text(
                '${_dateLabel(provider.rangeStart)} – '
                '${_dateLabel(provider.rangeEnd)}',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickRange(BuildContext context) async {
    final selected = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: DateTimeRange(
        start: provider.rangeStart,
        end: provider.rangeEnd,
      ),
    );
    if (selected != null) {
      await provider.setDateRange(selected.start, selected.end);
    }
  }
}

class _ContextStrip extends StatelessWidget {
  const _ContextStrip({required this.snapshot});

  final PerformanceWorkspaceSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (snapshot.reportedData)
          const Chip(
            avatar: Icon(Icons.cloud_download_outlined, size: 17),
            label: Text('Reported'),
          ),
        Chip(
          avatar: const Icon(Icons.verified_outlined, size: 17),
          label: Text(
            context.tr(_verificationLabel(snapshot.verificationStatus)),
          ),
        ),
        if (snapshot.targetSourceLabel != null)
          Chip(
            avatar: const Icon(Icons.track_changes_outlined, size: 17),
            label: Text(
              '${context.tr('Target source')}: '
              '${snapshot.targetSourceLabel}',
            ),
          ),
        Text(
          '${_dateLabel(snapshot.rangeStart)} – '
          '${_dateLabel(snapshot.rangeEnd)}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.icon,
    required this.child,
  });

  final String title;
  final IconData icon;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 7),
              Text(
                context.tr(title),
                style: Theme.of(
                  context,
                ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
              ),
            ],
          ),
          const SizedBox(height: 9),
          child,
        ],
      ),
    );
  }
}

String _verificationLabel(VerificationStatus status) {
  switch (status) {
    case VerificationStatus.pendingEntry:
      return 'Pending entry';
    case VerificationStatus.entered:
      return 'Entered';
    case VerificationStatus.reviewed:
      return 'Reviewed';
    case VerificationStatus.verified:
      return 'Verified';
    case VerificationStatus.requiresClarification:
      return 'Requires clarification';
    case VerificationStatus.corrected:
      return 'Corrected';
  }
}

String _dateLabel(DateTime date) =>
    '${date.day.toString().padLeft(2, '0')}-'
    '${date.month.toString().padLeft(2, '0')}-${date.year}';
