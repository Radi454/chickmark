import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/date_utils.dart';
import '../../../data/models/flock_model.dart';
import '../../../providers/customers_provider.dart';
import '../models/session_filter.dart';

/// Collapsible bottom sheet for filtering audit sessions by status, sync state,
/// date range, customer, and flock. Returns the chosen [SessionFilter] (or null
/// if dismissed).
class SessionFilterSheet extends StatefulWidget {
  final SessionFilter initialFilter;

  const SessionFilterSheet({super.key, required this.initialFilter});

  @override
  State<SessionFilterSheet> createState() => _SessionFilterSheetState();
}

class _SessionFilterSheetState extends State<SessionFilterSheet> {
  static const _statusLabels = {
    'in_progress': 'In Progress',
    'completed': 'Completed',
  };
  static const _syncLabels = {
    'pending': 'Pending',
    'synced': 'Synced',
    'failed': 'Failed',
  };

  late SessionFilter _filter = widget.initialFilter;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<CustomersProvider>();
    final flocks = _flocksForCustomer(provider);

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
                      'Filter Visits',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () =>
                        setState(() => _filter = SessionFilter.empty),
                    child: const Text('Reset'),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              _sectionLabel('Status'),
              _chips(_statusLabels, _filter.statuses, (next) {
                setState(() => _filter = _filter.copyWith(statuses: next));
              }),
              const SizedBox(height: 16),
              _sectionLabel('Sync status'),
              _chips(_syncLabels, _filter.syncStatuses, (next) {
                setState(() => _filter = _filter.copyWith(syncStatuses: next));
              }),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: _pickDateRange,
                icon: const Icon(Icons.date_range_outlined),
                label: Text(_dateRangeLabel()),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _filter.customerId,
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Customer'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All customers'),
                  ),
                  ...provider.allCustomers.map(
                    (customer) => DropdownMenuItem<String?>(
                      value: customer.id,
                      child: Text(
                        customer.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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
                isExpanded: true,
                decoration: const InputDecoration(labelText: 'Flock'),
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('All flocks'),
                  ),
                  ...flocks.map(
                    (flock) => DropdownMenuItem<String?>(
                      value: flock.id,
                      child: Text(
                        flock.flockId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
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

  Widget _sectionLabel(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
  );

  Widget _chips(
    Map<String, String> options,
    Set<String> selected,
    ValueChanged<Set<String>> onChanged,
  ) {
    return Wrap(
      spacing: AppSizes.spaceSm,
      runSpacing: AppSizes.spaceSm,
      children: options.entries.map((entry) {
        final isSelected = selected.contains(entry.key);
        return FilterChip(
          label: Text(entry.value),
          selected: isSelected,
          onSelected: (value) {
            final next = {...selected};
            if (value) {
              next.add(entry.key);
            } else {
              next.remove(entry.key);
            }
            onChanged(next);
          },
        );
      }).toList(),
    );
  }

  List<FlockModel> _flocksForCustomer(CustomersProvider provider) {
    final customerId = _filter.customerId;
    final flocks = customerId == null
        ? provider.flocks
        : provider.flocks.where((flock) => flock.customerId == customerId);
    final values = flocks.toList()
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
    return '${HatchDateUtils.formatDisplayDate(_filter.dateFrom!)} '
        'to ${HatchDateUtils.formatDisplayDate(_filter.dateTo!)}';
  }
}
