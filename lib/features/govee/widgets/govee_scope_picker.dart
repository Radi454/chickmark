import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/hatchery_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../providers/customers_provider.dart';
import '../providers/govee_capture_provider.dart';
import '../utils/govee_place_flow.dart';

class GoveeScopePicker extends StatelessWidget {
  const GoveeScopePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final govee = context.watch<GoveeCaptureProvider>();
    if (govee.supportsMachineChoice) {
      return const _StationScopeCard();
    }

    final customers = context.watch<CustomersProvider>();
    final selectedCustomer = _selectedCustomer(customers, govee.customerId);
    final hatcheries = selectedCustomer == null
        ? const <HatcheryModel>[]
        : customers.hatcheries
              .where((hatchery) => hatchery.customerId == selectedCustomer.id)
              .toList();

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          children: [
            DropdownButtonFormField<String>(
              initialValue: selectedCustomer?.id,
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
              ),
              items: customers.allCustomers
                  .map(
                    (customer) => DropdownMenuItem(
                      value: customer.id,
                      child: Text(customer.name),
                    ),
                  )
                  .toList(),
              onChanged: (value) async {
                final customer = customers.allCustomers
                    .where((customer) => customer.id == value)
                    .firstOrNull;
                if (customer == null) return;
                await customers.selectCustomer(customer);
                if (!context.mounted) return;
                final nextHatchery = customers.hatcheries
                    .where((hatchery) => hatchery.customerId == customer.id)
                    .firstOrNull;
                if (nextHatchery != null) {
                  await _configure(context, customer.id, nextHatchery.id);
                }
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue:
                  hatcheries.any((item) => item.id == govee.hatcheryId)
                  ? govee.hatcheryId
                  : null,
              decoration: const InputDecoration(
                labelText: 'Hatchery',
                border: OutlineInputBorder(),
              ),
              items: hatcheries
                  .map(
                    (hatchery) => DropdownMenuItem(
                      value: hatchery.id,
                      child: Text(hatchery.name),
                    ),
                  )
                  .toList(),
              onChanged: selectedCustomer == null
                  ? null
                  : (value) async {
                      if (value == null) return;
                      await _configure(context, selectedCustomer.id, value);
                    },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () async {
                      final current =
                          DateTime.tryParse(govee.captureDate ?? '') ??
                          DateTime.now();
                      final selected = await showDatePicker(
                        context: context,
                        initialDate: current,
                        firstDate: DateTime(2020),
                        lastDate: DateTime(2035),
                      );
                      if (selected == null || !context.mounted) return;
                      await _configure(
                        context,
                        govee.customerId,
                        govee.hatcheryId,
                        captureDate: _formatDate(selected),
                      );
                    },
                    icon: const Icon(Icons.calendar_today_outlined),
                    label: Text(
                      govee.captureDate ?? _formatDate(DateTime.now()),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: DropdownButtonFormField<TemperaturePlace>(
                    initialValue:
                        govee.place ?? TemperaturePlace.eggStorageRoom,
                    decoration: const InputDecoration(
                      labelText: 'Place',
                      border: OutlineInputBorder(),
                    ),
                    items: goveePlaceFlow
                        .map(
                          (place) => DropdownMenuItem(
                            value: place,
                            child: Text(place.label),
                          ),
                        )
                        .toList(),
                    onChanged: (place) async {
                      if (place == null) return;
                      await _configure(
                        context,
                        govee.customerId,
                        govee.hatcheryId,
                        place: place,
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  CustomerModel? _selectedCustomer(CustomersProvider provider, String? id) {
    if (id == null) return null;
    return provider.allCustomers
        .where((customer) => customer.id == id)
        .firstOrNull;
  }

  Future<void> _configure(
    BuildContext context,
    String? customerId,
    String? hatcheryId, {
    TemperaturePlace? place,
    String? captureDate,
  }) async {
    final govee = context.read<GoveeCaptureProvider>();
    final selectedPlace =
        place ?? govee.place ?? TemperaturePlace.eggStorageRoom;
    if (customerId == null || hatcheryId == null) return;
    await govee.configure(
      customerId: customerId,
      hatcheryId: hatcheryId,
      place: selectedPlace,
      captureDate: captureDate ?? govee.captureDate,
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _StationScopeCard extends StatelessWidget {
  const _StationScopeCard();

  @override
  Widget build(BuildContext context) {
    final govee = context.watch<GoveeCaptureProvider>();
    final roomPlace = govee.roomPlace ?? govee.place;
    final machinePlace = govee.insideMachinePlace;
    final machineLabel = govee.machineDisplayLabel ?? 'Inside machine';

    return Card(
      elevation: 0,
      color: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Record environment',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: _ScopeChoice(
                    key: const ValueKey('govee-scope-room-choice'),
                    selected: govee.captureTarget == GoveeCaptureTarget.room,
                    icon: Icons.meeting_room_outlined,
                    title: roomPlace?.label ?? 'Room environment',
                    subtitle: 'Room environment',
                    onTap: () => context
                        .read<GoveeCaptureProvider>()
                        .selectCaptureTarget(GoveeCaptureTarget.room),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _ScopeChoice(
                    key: const ValueKey('govee-scope-machine-choice'),
                    selected:
                        govee.captureTarget == GoveeCaptureTarget.insideMachine,
                    icon: Icons.precision_manufacturing_outlined,
                    title: machineLabel,
                    subtitle: machinePlace?.label ?? 'Inside machine',
                    onTap: () => context
                        .read<GoveeCaptureProvider>()
                        .selectCaptureTarget(GoveeCaptureTarget.insideMachine),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            OutlinedButton.icon(
              onPressed: () async {
                final current =
                    DateTime.tryParse(govee.captureDate ?? '') ??
                    DateTime.now();
                final selected = await showDatePicker(
                  context: context,
                  initialDate: current,
                  firstDate: DateTime(2020),
                  lastDate: DateTime(2035),
                );
                if (selected == null || !context.mounted) return;
                await context.read<GoveeCaptureProvider>().configure(
                  customerId: govee.customerId!,
                  hatcheryId: govee.hatcheryId!,
                  place:
                      govee.place ?? roomPlace ?? TemperaturePlace.hatcherRoom,
                  captureDate: _formatDate(selected),
                  stationKey: govee.stationKey,
                  machineId: govee.availableMachineId,
                  captureTarget: govee.captureTarget,
                );
              },
              icon: const Icon(Icons.calendar_today_outlined),
              label: Text(govee.captureDate ?? _formatDate(DateTime.now())),
            ),
          ],
        ),
      ),
    );
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');
    return '${date.year}-$month-$day';
  }
}

class _ScopeChoice extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _ScopeChoice({
    super.key,
    required this.selected,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? AppColors.statusActiveBg : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          border: Border.all(
            color: selected ? AppColors.primary : AppColors.borderDefault,
            width: selected ? 2 : 1,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              icon,
              color: selected ? AppColors.primary : AppColors.textSecondary,
            ),
            const SizedBox(height: 10),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontWeight: FontWeight.w900),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: AppColors.textSecondary,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
