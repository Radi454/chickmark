import 'package:flutter/material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/dashboard/models/govee_capture_summary.dart';
import 'package:hatchaudit/features/dashboard/widgets/govee_capture_chart.dart';
import 'package:hatchaudit/widgets/app_card.dart';

class GoveeEnvironmentalReadingsSection extends StatefulWidget {
  final List<GoveeCaptureSummary> captures;
  final bool isLoading;

  const GoveeEnvironmentalReadingsSection({
    super.key,
    required this.captures,
    required this.isLoading,
  });

  @override
  State<GoveeEnvironmentalReadingsSection> createState() =>
      _GoveeEnvironmentalReadingsSectionState();
}

class _GoveeEnvironmentalReadingsSectionState
    extends State<GoveeEnvironmentalReadingsSection> {
  TemperaturePlace? _selectedPlace;
  String? _selectedMachine;

  @override
  void didUpdateWidget(GoveeEnvironmentalReadingsSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    final places = _placeOptions(widget.captures);
    if (_selectedPlace != null && !places.contains(_selectedPlace)) {
      _selectedPlace = null;
    }
    final machines = _machineOptions(_placeFiltered(widget.captures));
    if (_selectedMachine != null && !machines.contains(_selectedMachine)) {
      _selectedMachine = null;
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.isLoading && widget.captures.isEmpty) {
      return const SizedBox.shrink();
    }

    final placeOptions = _placeOptions(widget.captures);
    final placeFiltered = _placeFiltered(widget.captures);
    final machineOptions = _machineOptions(placeFiltered);
    final visibleCaptures = _machineFiltered(placeFiltered);

    return AppCard(
      margin: EdgeInsets.zero,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Expanded(
                child: Text(
                  'Govee Environmental Readings',
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              if (widget.isLoading)
                const SizedBox(
                  height: 18,
                  width: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
            ],
          ),
          if (widget.isLoading) ...[
            const SizedBox(height: AppSizes.spaceSm),
            const LinearProgressIndicator(minHeight: 2),
          ],
          if (placeOptions.length > 1) ...[
            const SizedBox(height: AppSizes.spaceMd),
            _PlaceFilterGroup(
              places: placeOptions,
              selectedPlace: _selectedPlace,
              onSelected: (place) {
                setState(() {
                  _selectedPlace = place;
                  _selectedMachine = null;
                });
              },
            ),
          ],
          if (machineOptions.length > 1) ...[
            const SizedBox(height: AppSizes.spaceSm),
            _MachineFilterGroup(
              machines: machineOptions,
              selectedMachine: _selectedMachine,
              onSelected: (machine) {
                setState(() {
                  _selectedMachine = machine;
                });
              },
            ),
          ],
          if (visibleCaptures.isNotEmpty) ...[
            const SizedBox(height: AppSizes.spaceMd),
            ...visibleCaptures.map(
              (summary) => Padding(
                key: ValueKey('govee-capture-card-${summary.capture.id}'),
                padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
                child: GoveeCaptureChart(summary: summary),
              ),
            ),
          ] else if (!widget.isLoading) ...[
            const SizedBox(height: AppSizes.spaceMd),
            Text(
              'No Govee captures for these filters',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ],
        ],
      ),
    );
  }

  List<GoveeCaptureSummary> _placeFiltered(List<GoveeCaptureSummary> captures) {
    final place = _selectedPlace;
    if (place == null) return captures;
    return captures
        .where((summary) => summary.capture.place == place)
        .toList(growable: false);
  }

  List<GoveeCaptureSummary> _machineFiltered(
    List<GoveeCaptureSummary> captures,
  ) {
    final machine = _selectedMachine;
    if (machine == null) return captures;
    return captures
        .where((summary) => summary.capture.machineId == machine)
        .toList(growable: false);
  }

  List<TemperaturePlace> _placeOptions(List<GoveeCaptureSummary> captures) {
    final seen = <TemperaturePlace>{};
    final places = <TemperaturePlace>[];
    for (final summary in captures) {
      final place = summary.capture.place;
      if (seen.add(place)) places.add(place);
    }
    places.sort((a, b) => a.index.compareTo(b.index));
    return places;
  }

  List<String> _machineOptions(List<GoveeCaptureSummary> captures) {
    final machines = <String>{};
    for (final summary in captures) {
      if (!_hasMachineScope(summary.capture.place)) continue;
      final machineId = summary.capture.machineId?.trim();
      if (machineId != null && machineId.isNotEmpty) {
        machines.add(machineId);
      }
    }
    return machines.toList()..sort();
  }

  bool _hasMachineScope(TemperaturePlace place) {
    return place == TemperaturePlace.insideSetter ||
        place == TemperaturePlace.insideHatcher;
  }
}

class _PlaceFilterGroup extends StatelessWidget {
  final List<TemperaturePlace> places;
  final TemperaturePlace? selectedPlace;
  final ValueChanged<TemperaturePlace?> onSelected;

  const _PlaceFilterGroup({
    required this.places,
    required this.selectedPlace,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('govee-place-filter-group'),
      spacing: AppSizes.spaceSm,
      runSpacing: AppSizes.spaceXs,
      children: [
        ChoiceChip(
          key: const ValueKey('govee-place-filter-all'),
          label: const Text('All places'),
          selected: selectedPlace == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final place in places)
          ChoiceChip(
            key: ValueKey('govee-place-filter-${place.name}'),
            label: Text(place.label),
            selected: selectedPlace == place,
            onSelected: (_) => onSelected(place),
          ),
      ],
    );
  }
}

class _MachineFilterGroup extends StatelessWidget {
  final List<String> machines;
  final String? selectedMachine;
  final ValueChanged<String?> onSelected;

  const _MachineFilterGroup({
    required this.machines,
    required this.selectedMachine,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: const ValueKey('govee-machine-filter-group'),
      spacing: AppSizes.spaceSm,
      runSpacing: AppSizes.spaceXs,
      children: [
        ChoiceChip(
          key: const ValueKey('govee-machine-filter-all'),
          label: const Text('All machines'),
          selected: selectedMachine == null,
          onSelected: (_) => onSelected(null),
        ),
        for (final machine in machines)
          ChoiceChip(
            key: ValueKey('govee-machine-filter-$machine'),
            label: Text(machine),
            selected: selectedMachine == machine,
            onSelected: (_) => onSelected(machine),
          ),
      ],
    );
  }
}
