import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/date_utils.dart';
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
        side: const BorderSide(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.spaceMd),
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
            const SizedBox(height: AppSizes.spaceSm),
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
            const SizedBox(height: AppSizes.spaceSm),
            _DatePlaceControls(govee: govee, configure: _configure),
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
}

class _DatePlaceControls extends StatelessWidget {
  const _DatePlaceControls({required this.govee, required this.configure});

  final GoveeCaptureProvider govee;
  final Future<void> Function(
    BuildContext context,
    String? customerId,
    String? hatcheryId, {
    TemperaturePlace? place,
    String? captureDate,
  })
  configure;

  @override
  Widget build(BuildContext context) {
    final dateButton = _ReadOnlyCaptureDate(
      date: govee.captureDate ?? _formatDate(DateTime.now()),
    );

    final placeDropdown = DropdownButtonFormField<TemperaturePlace>(
      initialValue: govee.place ?? TemperaturePlace.eggStorageRoom,
      isExpanded: true,
      decoration: const InputDecoration(
        labelText: 'Place',
        border: OutlineInputBorder(),
      ),
      items: goveePlaceFlow
          .map(
            (place) => DropdownMenuItem(
              value: place,
              child: Text(place.label, overflow: TextOverflow.ellipsis),
            ),
          )
          .toList(),
      onChanged: (place) async {
        if (place == null) return;
        await configure(
          context,
          govee.customerId,
          govee.hatcheryId,
          place: place,
        );
      },
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              dateButton,
              const SizedBox(height: AppSizes.spaceSm),
              placeDropdown,
            ],
          );
        }

        return Row(
          children: [
            Expanded(child: dateButton),
            const SizedBox(width: AppSizes.spaceSm),
            Expanded(child: placeDropdown),
          ],
        );
      },
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
        side: const BorderSide(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.spaceMd),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Record environment', style: AppTextStyles.title),
            const SizedBox(height: AppSizes.spaceSm),
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
                const SizedBox(width: AppSizes.spaceSm),
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
            const SizedBox(height: AppSizes.spaceSm),
            _ReadOnlyCaptureDate(
              date: govee.captureDate ?? _formatDate(DateTime.now()),
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

class _ReadOnlyCaptureDate extends StatelessWidget {
  final String date;

  const _ReadOnlyCaptureDate({required this.date});

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: null,
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(
        HatchDateUtils.formatDisplayDateKey(date),
        overflow: TextOverflow.ellipsis,
        textDirection: TextDirection.ltr,
      ),
    );
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
        padding: const EdgeInsets.all(AppSizes.spaceSm),
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
              size: AppSizes.iconSm,
            ),
            const SizedBox(height: AppSizes.spaceSm),
            Text(
              title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.title.copyWith(fontSize: 14),
            ),
            const SizedBox(height: 4),
            Text(
              subtitle,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
