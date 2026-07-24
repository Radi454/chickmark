import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../providers/customers_provider.dart';

class CustomerSectorManagementSheet extends StatefulWidget {
  const CustomerSectorManagementSheet({super.key, required this.customerId});

  final String customerId;

  @override
  State<CustomerSectorManagementSheet> createState() =>
      _CustomerSectorManagementSheetState();
}

class _CustomerSectorManagementSheetState
    extends State<CustomerSectorManagementSheet> {
  late Set<PoultrySector> _selected;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _selected = {...context.read<CustomersProvider>().enabledSectors};
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.tr('Customer sectors'),
              style: Theme.of(
                context,
              ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              context.tr(
                'A customer can use multiple sectors. Each farm belongs to '
                'exactly one enabled sector.',
              ),
            ),
            const SizedBox(height: 14),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final sector in PoultrySector.values)
                  FilterChip(
                    key: ValueKey('customer-sector-${sector.storageKey}'),
                    selected: _selected.contains(sector),
                    avatar: Icon(_sectorIcon(sector), size: 18),
                    label: Text(context.tr(_sectorLabel(sector))),
                    onSelected: (selected) {
                      setState(() {
                        if (selected) {
                          _selected.add(sector);
                        } else {
                          _selected.remove(sector);
                        }
                      });
                    },
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              context.tr(
                'Hatcheries belong to Breeder customers and are available '
                'when Breeder is enabled.',
              ),
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: _saving ? null : _save,
                icon: const Icon(Icons.save_outlined),
                label: Text(context.tr('Save sectors')),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _save() async {
    setState(() => _saving = true);
    try {
      await context.read<CustomersProvider>().replaceCustomerSectors(
        widget.customerId,
        _selected,
      );
      if (mounted && Navigator.canPop(context)) Navigator.pop(context);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}

String sectorLabel(PoultrySector sector) => _sectorLabel(sector);

String _sectorLabel(PoultrySector sector) {
  switch (sector) {
    case PoultrySector.breeder:
      return 'Breeder';
    case PoultrySector.broiler:
      return 'Broiler';
    case PoultrySector.layer:
      return 'Layer';
  }
}

IconData _sectorIcon(PoultrySector sector) {
  switch (sector) {
    case PoultrySector.breeder:
      return Icons.egg_outlined;
    case PoultrySector.broiler:
      return Icons.monitor_heart_outlined;
    case PoultrySector.layer:
      return Icons.egg_alt_outlined;
  }
}
