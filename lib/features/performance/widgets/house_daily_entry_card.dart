import 'package:hatchaudit/localized_material.dart';

import '../../../data/models/broiler_daily_record_models.dart';
import '../../../widgets/app_card.dart';
import '../providers/broiler_daily_entry_provider.dart';
import 'daily_entry_source_section.dart';

class HouseDailyEntryCard extends StatelessWidget {
  const HouseDailyEntryCard({
    super.key,
    required this.entry,
    required this.onDraftChanged,
  });

  final HouseDailyEntryState entry;
  final ValueChanged<BroilerDailyRecordDraft> onDraftChanged;

  @override
  Widget build(BuildContext context) {
    final draft = entry.draft;
    return AppCard(
      margin: const EdgeInsets.all(6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            entry.house.name,
            style: Theme.of(
              context,
            ).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: [
              _ContextChip(label: 'Age ${entry.ageDay} days'),
              _ContextChip(label: entry.flock.breed),
              _ContextChip(
                label: 'Placed ${_formatNumber(entry.placement.placedBirds)}',
              ),
              if (entry.currentPopulation != null)
                _ContextChip(
                  label: 'Current ${_formatNumber(entry.currentPopulation!)}',
                ),
              if (entry.target?.bodyWeightG != null)
                _ContextChip(
                  label:
                      'Target ${_formatNumber(entry.target!.bodyWeightG!.round())} g',
                ),
            ],
          ),
          if (entry.previous?.revision.dailyMortality != null) ...[
            const SizedBox(height: 8),
            Text(
              'Previous mortality '
              '${entry.previous!.revision.dailyMortality}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ],
          const SizedBox(height: 12),
          DropdownButtonFormField<VerificationStatus>(
            key: ValueKey('verification-${entry.placement.id}'),
            initialValue: draft.verificationStatus,
            decoration: InputDecoration(labelText: context.tr('Status')),
            items: VerificationStatus.values
                .map(
                  (status) => DropdownMenuItem(
                    value: status,
                    child: Text(_statusLabel(status)),
                  ),
                )
                .toList(),
            onChanged: (status) {
              if (status != null) {
                onDraftChanged(draft.copyWith(verificationStatus: status));
              }
            },
          ),
          if (draft.verificationStatus == VerificationStatus.corrected) ...[
            const SizedBox(height: 8),
            TextFormField(
              key: ValueKey('correction-reason-${entry.placement.id}'),
              initialValue: draft.correctionReason,
              decoration: InputDecoration(
                labelText: context.tr('Correction reason'),
              ),
              onChanged: (value) =>
                  onDraftChanged(draft.copyWith(correctionReason: value)),
            ),
          ],
          const SizedBox(height: 14),
          Text('Population', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: 8),
          _InputGrid(
            children: [
              _numberField(
                context,
                label: 'Opening birds',
                value: draft.openingBirdCount,
                onChanged: (value) => onDraftChanged(
                  draft.copyWith(openingBirdCount: _int(value)),
                ),
              ),
              _numberField(
                context,
                label: 'Mortality',
                value: draft.dailyMortality,
                onChanged: (value) =>
                    onDraftChanged(draft.copyWith(mortality: _int(value))),
              ),
              _numberField(
                context,
                label: 'Culls',
                value: draft.dailyCulls,
                onChanged: (value) =>
                    onDraftChanged(draft.copyWith(dailyCulls: _int(value))),
              ),
              _numberField(
                context,
                label: 'Closing live birds',
                value: draft.closingLiveBirdCount,
                onChanged: (value) => onDraftChanged(
                  draft.copyWith(closingLiveBirdCount: _int(value)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            'Feed and water',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 8),
          _InputGrid(
            children: [
              _numberField(
                context,
                label: 'Feed consumed (kg)',
                value: draft.dailyFeedConsumedKg,
                decimal: true,
                onChanged: (value) => onDraftChanged(
                  draft.copyWith(dailyFeedConsumedKg: _double(value)),
                ),
              ),
              _numberField(
                context,
                label: 'Water consumed (L)',
                value: draft.waterConsumedLiters,
                decimal: true,
                onChanged: (value) => onDraftChanged(
                  draft.copyWith(waterConsumedLiters: _double(value)),
                ),
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Body weight and uniformity'),
            children: [
              _InputGrid(
                children: [
                  _numberField(
                    context,
                    label: 'Average body weight (g)',
                    value: draft.averageBodyWeightG,
                    decimal: true,
                    onChanged: (value) => onDraftChanged(
                      draft.copyWith(averageBodyWeightG: _double(value)),
                    ),
                  ),
                  _numberField(
                    context,
                    label: 'Birds weighed',
                    value: draft.birdsWeighed,
                    onChanged: (value) => onDraftChanged(
                      draft.copyWith(birdsWeighed: _int(value)),
                    ),
                  ),
                  _numberField(
                    context,
                    label: 'Uniformity (%)',
                    value: draft.uniformityPct,
                    decimal: true,
                    onChanged: (value) => onDraftChanged(
                      draft.copyWith(uniformityPct: _double(value)),
                    ),
                  ),
                  _numberField(
                    context,
                    label: 'CV (%)',
                    value: draft.cvPct,
                    decimal: true,
                    onChanged: (value) =>
                        onDraftChanged(draft.copyWith(cvPct: _double(value))),
                  ),
                ],
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Environment'),
            children: [
              _InputGrid(
                children: [
                  _numberField(
                    context,
                    label: 'Minimum temperature (°C)',
                    value: draft.minTemperatureC,
                    decimal: true,
                    onChanged: (value) => onDraftChanged(
                      draft.copyWith(minTemperatureC: _double(value)),
                    ),
                  ),
                  _numberField(
                    context,
                    label: 'Maximum temperature (°C)',
                    value: draft.maxTemperatureC,
                    decimal: true,
                    onChanged: (value) => onDraftChanged(
                      draft.copyWith(maxTemperatureC: _double(value)),
                    ),
                  ),
                  _numberField(
                    context,
                    label: 'Relative humidity (%)',
                    value: draft.relativeHumidityPct,
                    decimal: true,
                    onChanged: (value) => onDraftChanged(
                      draft.copyWith(relativeHumidityPct: _double(value)),
                    ),
                  ),
                  _numberField(
                    context,
                    label: 'CO₂ (ppm)',
                    value: draft.co2Ppm,
                    decimal: true,
                    onChanged: (value) =>
                        onDraftChanged(draft.copyWith(co2Ppm: _double(value))),
                  ),
                ],
              ),
            ],
          ),
          ExpansionTile(
            tilePadding: EdgeInsets.zero,
            title: const Text('Events, causes, and sources'),
            children: [DailyEntrySourceSection(sources: draft.sources)],
          ),
          if (entry.validationErrors.isNotEmpty)
            Container(
              margin: const EdgeInsets.only(top: 10),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.errorContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final error in entry.validationErrors)
                    Text(
                      '• $error',
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.onErrorContainer,
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _numberField(
    BuildContext context, {
    required String label,
    required num? value,
    required ValueChanged<String> onChanged,
    bool decimal = false,
  }) {
    return TextFormField(
      initialValue: value?.toString(),
      keyboardType: TextInputType.numberWithOptions(decimal: decimal),
      decoration: InputDecoration(labelText: context.tr(label)),
      onChanged: onChanged,
    );
  }
}

class _ContextChip extends StatelessWidget {
  const _ContextChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label),
    );
  }
}

class _InputGrid extends StatelessWidget {
  const _InputGrid({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth >= 480
            ? (constraints.maxWidth - 10) / 2
            : constraints.maxWidth;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final child in children) SizedBox(width: width, child: child),
          ],
        );
      },
    );
  }
}

int? _int(String value) => int.tryParse(value.trim());
double? _double(String value) => double.tryParse(value.trim());

String _formatNumber(int value) {
  final digits = value.toString();
  return digits.replaceAllMapped(
    RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
    (match) => '${match[1]},',
  );
}

String _statusLabel(VerificationStatus status) {
  return switch (status) {
    VerificationStatus.pendingEntry => 'Pending entry',
    VerificationStatus.entered => 'Entered',
    VerificationStatus.reviewed => 'Reviewed',
    VerificationStatus.verified => 'Verified',
    VerificationStatus.requiresClarification => 'Requires clarification',
    VerificationStatus.corrected => 'Corrected',
  };
}
