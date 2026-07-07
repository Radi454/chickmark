import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/customer_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/hatchery_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../providers/customers_provider.dart';
import '../../customers/widgets/add_customer_sheet.dart';
import '../../customers/widgets/add_hatchery_sheet.dart';
import '../providers/govee_capture_provider.dart';
import '../utils/govee_place_flow.dart';

/// Sentinel dropdown values that trigger the registration sheets instead of
/// selecting an existing record.
const String _kAddCustomerValue = '__govee_add_customer__';
const String _kAddHatcheryValue = '__govee_add_hatchery__';

class GoveeScopePicker extends StatelessWidget {
  const GoveeScopePicker({super.key});

  @override
  Widget build(BuildContext context) {
    final govee = context.watch<GoveeCaptureProvider>();
    if (govee.supportsMachineChoice) {
      return const Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _CustomerHatcheryScopeCard(showDatePlaceControls: false),
          SizedBox(height: AppSizes.spaceSm),
          _StationScopeCard(),
        ],
      );
    }
    return const _CustomerHatcheryScopeCard();
  }
}

class _CustomerHatcheryScopeCard extends StatefulWidget {
  final bool showDatePlaceControls;

  const _CustomerHatcheryScopeCard({this.showDatePlaceControls = true});

  @override
  State<_CustomerHatcheryScopeCard> createState() =>
      _CustomerHatcheryScopeCardState();
}

class _CustomerHatcheryScopeCardState
    extends State<_CustomerHatcheryScopeCard> {
  // Bumped whenever a registration sheet closes so the dropdowns are rebuilt
  // from `initialValue`. Flutter only re-seeds a DropdownButtonFormField when
  // its initialValue changes, so a cancelled "Add new…" selection would
  // otherwise stay stuck on the sentinel item.
  int _nonce = 0;

  void _resetDropdowns() {
    if (!mounted) return;
    setState(() => _nonce++);
  }

  @override
  Widget build(BuildContext context) {
    final govee = context.watch<GoveeCaptureProvider>();
    final customers = context.watch<CustomersProvider>();
    final selectedCustomer = _selectedCustomer(customers, govee.customerId);
    final flocks = selectedCustomer == null
        ? const <FlockModel>[]
        : _flocksForCustomer(customers, selectedCustomer.id, govee.flockId);
    final selectedFlock = _selectedFlock(flocks, govee.flockId);
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
              key: ValueKey('govee-customer-$_nonce'),
              initialValue: selectedCustomer?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Customer',
                border: OutlineInputBorder(),
              ),
              items: [
                ...customers.allCustomers.map(
                  (customer) => DropdownMenuItem(
                    value: customer.id,
                    child: Text(
                      customer.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                const DropdownMenuItem(
                  value: _kAddCustomerValue,
                  child: _AddNewRow(label: 'Add new customer'),
                ),
              ],
              onChanged: (value) async {
                if (value == null) return;
                if (value == _kAddCustomerValue) {
                  await _handleAddCustomer(context);
                  return;
                }
                final customer = customers.allCustomers
                    .where((customer) => customer.id == value)
                    .firstOrNull;
                if (customer == null) return;
                await customers.selectCustomer(customer);
                if (!context.mounted) return;
                final nextHatchery = customers.hatcheries
                    .where((hatchery) => hatchery.customerId == customer.id)
                    .firstOrNull;
                final nextFlock = customers.flocks
                    .where((flock) => flock.customerId == customer.id)
                    .firstOrNull;
                if (nextHatchery != null) {
                  await _configure(
                    context,
                    customer.id,
                    nextHatchery.id,
                    flockId: nextFlock?.id,
                  );
                } else {
                  // Customer has no hatchery yet — go straight to registering
                  // one so the scope can be completed.
                  await _handleAddHatchery(context, customer.id);
                }
              },
            ),
            const SizedBox(height: AppSizes.spaceSm),
            DropdownButtonFormField<String>(
              key: ValueKey('govee-flock-$_nonce'),
              initialValue: selectedFlock?.id,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Flock',
                border: OutlineInputBorder(),
              ),
              items: flocks
                  .map(
                    (flock) => DropdownMenuItem(
                      value: flock.id,
                      child: Text(
                        flock.flockId,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: selectedCustomer == null
                  ? null
                  : (value) async {
                      await _configure(
                        context,
                        selectedCustomer.id,
                        govee.hatcheryId,
                        flockId: value,
                      );
                    },
            ),
            const SizedBox(height: AppSizes.spaceSm),
            DropdownButtonFormField<String>(
              key: ValueKey('govee-hatchery-$_nonce'),
              initialValue:
                  hatcheries.any((item) => item.id == govee.hatcheryId)
                  ? govee.hatcheryId
                  : null,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Hatchery',
                border: OutlineInputBorder(),
              ),
              items: [
                ...hatcheries.map(
                  (hatchery) => DropdownMenuItem(
                    value: hatchery.id,
                    child: Text(
                      hatchery.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
                if (selectedCustomer != null)
                  const DropdownMenuItem(
                    value: _kAddHatcheryValue,
                    child: _AddNewRow(label: 'Add new hatchery'),
                  ),
              ],
              onChanged: selectedCustomer == null
                  ? null
                  : (value) async {
                      if (value == null) return;
                      if (value == _kAddHatcheryValue) {
                        await _handleAddHatchery(context, selectedCustomer.id);
                        return;
                      }
                      await _configure(
                        context,
                        selectedCustomer.id,
                        value,
                        flockId: selectedFlock?.id ?? govee.flockId,
                      );
                    },
            ),
            if (widget.showDatePlaceControls) ...[
              const SizedBox(height: AppSizes.spaceSm),
              _PlaceControl(govee: govee, configure: _configure),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _handleAddCustomer(BuildContext context) async {
    final customer = await showModalBottomSheet<CustomerModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const AddCustomerSheet(),
    );
    if (customer == null) {
      _resetDropdowns();
      return;
    }
    if (!context.mounted) {
      _resetDropdowns();
      return;
    }
    // A new customer has no hatchery yet — chain into hatchery registration so
    // recording can start.
    await _handleAddHatchery(
      context,
      customer.id,
      missingHint: 'Add a hatchery for ${customer.name} to start recording.',
    );
  }

  Future<void> _handleAddHatchery(
    BuildContext context,
    String customerId, {
    String? missingHint,
  }) async {
    final hatchery = await showModalBottomSheet<HatcheryModel>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddHatcherySheet(customerId: customerId),
    );
    if (!context.mounted) {
      _resetDropdowns();
      return;
    }
    if (hatchery != null) {
      await _configure(context, customerId, hatchery.id);
      _resetDropdowns();
      return;
    }
    _resetDropdowns();
    if (missingHint != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(missingHint)));
    }
  }

  CustomerModel? _selectedCustomer(CustomersProvider provider, String? id) {
    if (id == null) return null;
    return provider.allCustomers
        .where((customer) => customer.id == id)
        .firstOrNull;
  }

  FlockModel? _selectedFlock(List<FlockModel> flocks, String? id) {
    if (id != null) {
      final selected = flocks.where((flock) => flock.id == id).firstOrNull;
      if (selected != null) return selected;
    }
    return flocks.length == 1 ? flocks.first : null;
  }

  List<FlockModel> _flocksForCustomer(
    CustomersProvider provider,
    String customerId,
    String? selectedFlockId,
  ) {
    final flocks = provider.flocks
        .where((flock) => flock.customerId == customerId)
        .toList();
    final selected = provider.flockById(selectedFlockId);
    if (selected != null &&
        selected.customerId == customerId &&
        flocks.every((flock) => flock.id != selected.id)) {
      flocks.insert(0, selected);
    }
    return flocks;
  }

  Future<void> _configure(
    BuildContext context,
    String? customerId,
    String? hatcheryId, {
    String? flockId,
    TemperaturePlace? place,
    String? captureDate,
  }) async {
    final govee = context.read<GoveeCaptureProvider>();
    final selectedPlace =
        place ?? govee.place ?? TemperaturePlace.eggStorageRoom;
    if (customerId == null || hatcheryId == null) return;
    await govee.configure(
      customerId: customerId,
      flockId: flockId ?? govee.flockId,
      hatcheryId: hatcheryId,
      place: selectedPlace,
      captureDate: captureDate ?? govee.captureDate,
      stationKey: govee.stationKey,
      machineId: govee.availableMachineId,
      captureTarget: govee.captureTarget,
    );
  }
}

class _AddNewRow extends StatelessWidget {
  final String label;

  const _AddNewRow({required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.add, size: AppSizes.iconSm, color: AppColors.primary),
        const SizedBox(width: 8),
        Text(
          label,
          style: AppTextStyles.body.copyWith(
            color: AppColors.primary,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

class _PlaceControl extends StatelessWidget {
  const _PlaceControl({required this.govee, required this.configure});

  final GoveeCaptureProvider govee;
  final Future<void> Function(
    BuildContext context,
    String? customerId,
    String? hatcheryId, {
    String? flockId,
    TemperaturePlace? place,
    String? captureDate,
  })
  configure;

  @override
  Widget build(BuildContext context) {
    return DropdownButtonFormField<TemperaturePlace>(
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
          flockId: govee.flockId,
          place: place,
        );
      },
    );
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
    final locked = govee.isRecording;

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
                    onTap: locked
                        ? null
                        : () => context
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
                    onTap: locked
                        ? null
                        : () => context
                              .read<GoveeCaptureProvider>()
                              .selectCaptureTarget(
                                GoveeCaptureTarget.insideMachine,
                              ),
                  ),
                ),
              ],
            ),
            if (locked) ...[
              const SizedBox(height: AppSizes.spaceSm),
              Row(
                children: [
                  const Icon(
                    Icons.lock_outline,
                    size: AppSizes.iconSm,
                    color: AppColors.textSecondary,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      'Locked while recording. Stop and save to switch.',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ScopeChoice extends StatelessWidget {
  final bool selected;
  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

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
    final enabled = onTap != null;
    return Opacity(
      opacity: enabled ? 1 : 0.55,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.all(AppSizes.spaceSm),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.statusActiveBg
                : AppColors.surfaceVariant,
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
      ),
    );
  }
}
