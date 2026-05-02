import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

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
    final dateButton = OutlinedButton.icon(
      onPressed: () async {
        final current =
            DateTime.tryParse(govee.captureDate ?? '') ?? DateTime.now();
        final selected = await showDatePicker(
          context: context,
          initialDate: current,
          firstDate: DateTime(2020),
          lastDate: DateTime(2035),
        );
        if (selected == null || !context.mounted) return;
        await configure(
          context,
          govee.customerId,
          govee.hatcheryId,
          captureDate: _formatDate(selected),
        );
      },
      icon: const Icon(Icons.calendar_today_outlined),
      label: Text(
        govee.captureDate ?? _formatDate(DateTime.now()),
        overflow: TextOverflow.ellipsis,
      ),
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
            children: [dateButton, const SizedBox(height: 12), placeDropdown],
          );
        }

        return Row(
          children: [
            Expanded(child: dateButton),
            const SizedBox(width: 12),
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
