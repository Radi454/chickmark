import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../providers/broiler_daily_entry_provider.dart';
import '../widgets/house_daily_entry_card.dart';

class BroilerDailyEntryScreen extends StatefulWidget {
  const BroilerDailyEntryScreen({super.key, this.provider, this.enteredBy});

  final BroilerDailyEntryProvider? provider;
  final String? enteredBy;

  @override
  State<BroilerDailyEntryScreen> createState() =>
      _BroilerDailyEntryScreenState();
}

class _BroilerDailyEntryScreenState extends State<BroilerDailyEntryScreen> {
  late final BroilerDailyEntryProvider _provider;
  late final bool _ownsProvider;

  @override
  void initState() {
    super.initState();
    _ownsProvider = widget.provider == null;
    _provider = widget.provider ?? BroilerDailyEntryProvider();
    if (_ownsProvider) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _provider.load(enteredBy: widget.enteredBy ?? 'local-user');
      });
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
      child: const _DailyEntryView(),
    );
  }
}

class _DailyEntryView extends StatelessWidget {
  const _DailyEntryView();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Broiler daily entry'),
      body: Consumer<BroilerDailyEntryProvider>(
        builder: (context, provider, _) {
          return Column(
            children: [
              _SelectorBar(provider: provider),
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
              Expanded(child: _HouseEntryBody(provider: provider)),
              if (provider.houseEntries.isNotEmpty)
                SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                    child: FilledButton.icon(
                      key: const ValueKey('daily-entry-save'),
                      onPressed: provider.isLoading
                          ? null
                          : () => _save(context, provider),
                      icon: const Icon(Icons.save_outlined),
                      label: const Text('Review and save valid houses'),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  Future<void> _save(
    BuildContext context,
    BroilerDailyEntryProvider provider,
  ) async {
    final result = await provider.saveValidDrafts();
    if (!context.mounted) return;
    final message = result.hasErrors
        ? '${result.savedPlacementIds.length} saved · '
              '${result.errorsByPlacement.length} need attention'
        : '${result.savedPlacementIds.length} houses saved';
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(context.tr(message))));
  }
}

class _SelectorBar extends StatelessWidget {
  const _SelectorBar({required this.provider});

  final BroilerDailyEntryProvider provider;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.all(12),
      child: Row(
        children: [
          SizedBox(
            key: const ValueKey('daily-entry-customer'),
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: provider.selectedCustomerId,
              decoration: InputDecoration(labelText: context.tr('Customer')),
              items: provider.customers
                  .map(
                    (customer) => DropdownMenuItem(
                      value: customer.id,
                      child: Text(customer.name),
                    ),
                  )
                  .toList(),
              onChanged: provider.selectCustomer,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            key: const ValueKey('daily-entry-farm'),
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: provider.selectedFarmId,
              decoration: InputDecoration(
                labelText: context.tr('Broiler farm'),
              ),
              items: provider.farms
                  .map(
                    (farm) => DropdownMenuItem(
                      value: farm.id,
                      child: Text(farm.name),
                    ),
                  )
                  .toList(),
              onChanged: provider.selectedCustomerId == null
                  ? null
                  : provider.selectFarm,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            key: const ValueKey('daily-entry-flock'),
            width: 210,
            child: DropdownButtonFormField<String>(
              initialValue: provider.selectedFlockId,
              decoration: InputDecoration(labelText: context.tr('Flock')),
              items: provider.flocks
                  .map(
                    (flock) => DropdownMenuItem(
                      value: flock.id,
                      child: Text(flock.flockId),
                    ),
                  )
                  .toList(),
              onChanged: provider.selectedFarmId == null
                  ? null
                  : provider.selectFlock,
            ),
          ),
          const SizedBox(width: 10),
          SizedBox(
            key: const ValueKey('daily-entry-date'),
            width: 180,
            child: OutlinedButton.icon(
              onPressed: () => _pickDate(context),
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(_dateLabel(provider.selectedDate)),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickDate(BuildContext context) async {
    final selected = await showDatePicker(
      context: context,
      initialDate: provider.selectedDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (selected != null) provider.setDate(selected);
  }
}

class _HouseEntryBody extends StatelessWidget {
  const _HouseEntryBody({required this.provider});

  final BroilerDailyEntryProvider provider;

  @override
  Widget build(BuildContext context) {
    if (provider.houseEntries.isEmpty) {
      return Center(
        child: Text(
          provider.selectedFlockId == null
              ? 'Select a customer, farm, flock, and date'
              : 'No active house placements',
        ),
      );
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 1000) {
          return GridView.builder(
            key: const ValueKey('daily-entry-wide-grid'),
            padding: const EdgeInsets.all(10),
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              crossAxisSpacing: 8,
              mainAxisSpacing: 8,
              childAspectRatio: 0.72,
            ),
            itemCount: provider.houseEntries.length,
            itemBuilder: (context, index) {
              final entry = provider.houseEntries[index];
              return SingleChildScrollView(
                child: HouseDailyEntryCard(
                  entry: entry,
                  onDraftChanged: (draft) =>
                      provider.updateDraft(entry.placement.id, draft),
                ),
              );
            },
          );
        }
        return ListView.builder(
          key: const ValueKey('daily-entry-narrow-list'),
          padding: const EdgeInsets.all(10),
          itemCount: provider.houseEntries.length,
          itemBuilder: (context, index) {
            final entry = provider.houseEntries[index];
            return HouseDailyEntryCard(
              entry: entry,
              onDraftChanged: (draft) =>
                  provider.updateDraft(entry.placement.id, draft),
            );
          },
        );
      },
    );
  }
}

String _dateLabel(DateTime date) {
  return '${date.year.toString().padLeft(4, '0')}-'
      '${date.month.toString().padLeft(2, '0')}-'
      '${date.day.toString().padLeft(2, '0')}';
}
