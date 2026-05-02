import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../data/models/flock_model.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../providers/customers_provider.dart';
import '../models/audit_filter.dart';

class AuditFilterSheet extends StatefulWidget {
  final AuditFilter initialFilter;

  const AuditFilterSheet({super.key, required this.initialFilter});

  @override
  State<AuditFilterSheet> createState() => _AuditFilterSheetState();
}

class _AuditFilterSheetState extends State<AuditFilterSheet> {
  static const Map<String, String> _auditTypeLabels = {
    'Chicks': 'Chicks',
    'Hatch Analysis & Egg Breakouts': 'Hatch Analysis & Egg Breakouts',
    AuditTypeLabels.eggAuditType: AuditTypeLabels.eggStationLabel,
    'Setters': 'Setters',
    'Hatchers': 'Hatchers',
  };

  AuditFilter _filter = AuditFilter.empty;

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomersProvider>();
    final flocks = _availableFlocks(provider);

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          left: 16,
          right: 16,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  const Expanded(
                    child: Text(
                      'Filter Audits',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () {
                      setState(() => _filter = AuditFilter.empty);
                    },
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_dateRangeLabel()),
              ),
              const SizedBox(height: 16),
              const Text(
                'Audit Types',
                style: TextStyle(fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: _auditTypeLabels.entries.map((entry) {
                  final type = entry.key;
                  final selected = _filter.auditTypes.contains(type);
                  return FilterChip(
                    label: Text(entry.value),
                    selected: selected,
                    onSelected: (value) {
                      final next = [..._filter.auditTypes];
                      if (value) {
                        next.add(type);
                      } else {
                        next.remove(type);
                      }
                      setState(
                        () => _filter = _filter.copyWith(auditTypes: next),
                      );
                    },
                  );
                }).toList(),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _filter.customerId,
                decoration: const InputDecoration(labelText: 'Customer'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All customers'),
                  ),
                  ...provider.allCustomers.map(
                    (customer) => DropdownMenuItem<String?>(
                      value: customer.id,
                      child: Text(customer.name),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _filter = _filter.copyWith(
                      customerId: value,
                      clearCustomerId: value == null,
                      clearFlockId: true,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: flocks.any((flock) => flock.id == _filter.flockId)
                    ? _filter.flockId
                    : null,
                decoration: const InputDecoration(labelText: 'Flock'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All flocks'),
                  ),
                  ...flocks.map(
                    (flock) => DropdownMenuItem<String?>(
                      value: flock.id,
                      child: Text(flock.flockId),
                    ),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _filter = _filter.copyWith(
                      flockId: value,
                      clearFlockId: value == null,
                    );
                  });
                },
              ),
              const SizedBox(height: 12),
              DropdownButtonFormField<String?>(
                initialValue: _filter.status,
                decoration: const InputDecoration(labelText: 'Status'),
                items: const [
                  DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All statuses'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'active',
                    child: Text('Active'),
                  ),
                  DropdownMenuItem<String?>(
                    value: 'completed',
                    child: Text('Completed'),
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _filter = _filter.copyWith(
                      status: value,
                      clearStatus: value == null,
                    );
                  });
                },
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () => Navigator.of(context).pop(_filter),
                  child: const Text('Apply'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<FlockModel> _availableFlocks(CustomersProvider provider) {
    final seen = <String, FlockModel>{};
    for (final audit in provider.allAudits) {
      if (_filter.customerId != null &&
          audit.customerId != _filter.customerId) {
        continue;
      }
      final flock = provider.flockById(audit.flockId);
      if (flock != null) {
        seen[flock.id] = flock;
      }
    }
    final values = seen.values.toList()
      ..sort((a, b) => a.flockId.compareTo(b.flockId));
    return values;
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDateRange: _filter.dateFrom != null && _filter.dateTo != null
          ? DateTimeRange(start: _filter.dateFrom!, end: _filter.dateTo!)
          : null,
    );
    if (picked == null) return;
    setState(() {
      _filter = _filter.copyWith(dateFrom: picked.start, dateTo: picked.end);
    });
  }

  String _dateRangeLabel() {
    if (_filter.dateFrom == null || _filter.dateTo == null) {
      return 'Any date';
    }
    final from = _filter.dateFrom!;
    final to = _filter.dateTo!;
    return '${from.year}-${from.month.toString().padLeft(2, '0')}-${from.day.toString().padLeft(2, '0')}'
        ' to '
        '${to.year}-${to.month.toString().padLeft(2, '0')}-${to.day.toString().padLeft(2, '0')}';
  }
}
