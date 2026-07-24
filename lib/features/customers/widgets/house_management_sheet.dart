import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../providers/customers_provider.dart';

class HouseManagementSheet extends StatefulWidget {
  const HouseManagementSheet({super.key, required this.farm});

  final FarmModel farm;

  @override
  State<HouseManagementSheet> createState() => _HouseManagementSheetState();
}

class _HouseManagementSheetState extends State<HouseManagementSheet> {
  final _name = TextEditingController();
  bool _saving = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomersProvider>();
    final houses = provider.housesForFarm(widget.farm.id);
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
                '${context.tr('Houses')} · ${widget.farm.name}',
                style: Theme.of(
                  context,
                ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 12),
              for (final house in houses)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.home_work_outlined),
                  title: Text(house.name),
                  subtitle: house.capacity == null
                      ? null
                      : Text(
                          '${house.capacity} ${context.tr('bird capacity')}',
                        ),
                ),
              if (houses.isEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(context.tr('No houses added')),
                ),
              TextField(
                controller: _name,
                decoration: InputDecoration(
                  labelText: context.tr('House name'),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
                  icon: const Icon(Icons.add_home_work_outlined),
                  label: Text(context.tr('Add house')),
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
    if (name.isEmpty) return;
    setState(() => _saving = true);
    try {
      await context.read<CustomersProvider>().saveHouse(
        HouseModel(id: const Uuid().v4(), farmId: widget.farm.id, name: name),
      );
      _name.clear();
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }
}
