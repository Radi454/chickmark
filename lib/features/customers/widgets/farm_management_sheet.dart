import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../providers/customers_provider.dart';
import 'customer_sector_management_sheet.dart';
import 'house_management_sheet.dart';

class FarmManagementSheet extends StatefulWidget {
  const FarmManagementSheet({super.key, required this.customerId});

  final String customerId;

  @override
  State<FarmManagementSheet> createState() => _FarmManagementSheetState();
}

class _FarmManagementSheetState extends State<FarmManagementSheet> {
  final _name = TextEditingController();
  PoultrySector? _sector;
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomersProvider>();
    final sectors = provider.enabledSectors.toList()
      ..sort((left, right) => left.storageKey.compareTo(right.storageKey));
    if (_sector != null && !sectors.contains(_sector)) _sector = null;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          18,
          20,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                context.tr('Farm and house hierarchy'),
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 10),
              for (final farm in provider.farms)
                Card(
                  margin: const EdgeInsets.only(bottom: 8),
                  child: ListTile(
                    leading: const Icon(Icons.agriculture_outlined),
                    title: Text(farm.name),
                    subtitle: Text(context.tr(sectorLabel(farm.sector))),
                    trailing: TextButton(
                      onPressed: () => _manageHouses(context, farm),
                      child: Text(
                        '${provider.housesForFarm(farm.id).length} '
                        '${context.tr('houses')}',
                      ),
                    ),
                  ),
                ),
              if (provider.farms.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(context.tr('No farms added')),
                ),
              TextField(
                controller: _name,
                decoration: InputDecoration(labelText: context.tr('Farm name')),
              ),
              const SizedBox(height: 8),
              DropdownButtonFormField<PoultrySector>(
                initialValue: _sector,
                decoration: InputDecoration(labelText: context.tr('Sector')),
                items: [
                  for (final sector in sectors)
                    DropdownMenuItem(
                      value: sector,
                      child: Text(context.tr(sectorLabel(sector))),
                    ),
                ],
                onChanged: sectors.isEmpty
                    ? null
                    : (value) => setState(() => _sector = value),
              ),
              if (sectors.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 7),
                  child: Text(
                    context.tr(
                      'Enable a customer sector before adding a farm.',
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving || sectors.isEmpty ? null : _save,
                  icon: const Icon(Icons.add_business_outlined),
                  label: Text(context.tr('Add farm')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _save() async {
    final name = _name.text.trim();
    final sector = _sector;
    if (name.isEmpty || sector == null) return;
    setState(() => _saving = true);
    try {
      await context.read<CustomersProvider>().saveFarm(
        FarmModel(
          id: const Uuid().v4(),
          customerId: widget.customerId,
          sector: sector,
          name: name,
        ),
      );
      _name.clear();
      setState(() => _sector = null);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _manageHouses(BuildContext context, FarmModel farm) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ChangeNotifierProvider<CustomersProvider>.value(
        value: context.read<CustomersProvider>(),
        child: HouseManagementSheet(farm: farm),
      ),
    );
  }
}
