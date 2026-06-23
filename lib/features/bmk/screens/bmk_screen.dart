import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/theme/app_elevation.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/bmk/providers/bmk_provider.dart';
import 'package:hatchaudit/widgets/section_card.dart';

enum _BmkMode { reference, admin }

class BmkScreen extends StatefulWidget {
  const BmkScreen({super.key});

  @override
  State<BmkScreen> createState() => _BmkScreenState();
}

class _BmkScreenState extends State<BmkScreen> {
  final _breedFormKey = GlobalKey<FormState>();
  final _eggBreakoutFormKey = GlobalKey<FormState>();
  final _operationalFormKey = GlobalKey<FormState>();
  final _breedHatchabilityController = TextEditingController();
  final _breedFertilityController = TextEditingController();
  final _breedHofController = TextEditingController();
  final _breedProductionController = TextEditingController();
  final _breedEggWeightController = TextEditingController();
  final _breedChickWeightController = TextEditingController();
  final _ebInfertileController = TextEditingController();
  final _ebEarly24hController = TextEditingController();
  final _ebEarly48hController = TextEditingController();
  final _ebBloodRingController = TextEditingController();
  final _ebBlackEyeController = TextEditingController();
  final _ebEarlyDeadController = TextEditingController();
  final _ebMidDeadController = TextEditingController();
  final _ebLateDeadController = TextEditingController();
  final _ebExternalPipController = TextEditingController();
  final _ebCrackedController = TextEditingController();
  final _ebContamController = TextEditingController();
  final _opMinController = TextEditingController();
  final _opMaxController = TextEditingController();
  final _opTargetController = TextEditingController();
  final _opNotesController = TextEditingController();

  _BmkMode _mode = _BmkMode.reference;
  String? _breedEditKey;
  String? _ebEditKey;
  String? _opEditKey;
  bool _savingBreed = false;
  bool _savingEggBreakout = false;
  bool _savingOperational = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<BmkProvider>().ensureInitialized();
    });
  }

  @override
  void dispose() {
    _breedHatchabilityController.dispose();
    _breedFertilityController.dispose();
    _breedHofController.dispose();
    _breedProductionController.dispose();
    _breedEggWeightController.dispose();
    _breedChickWeightController.dispose();
    _ebInfertileController.dispose();
    _ebEarly24hController.dispose();
    _ebEarly48hController.dispose();
    _ebBloodRingController.dispose();
    _ebBlackEyeController.dispose();
    _ebEarlyDeadController.dispose();
    _ebMidDeadController.dispose();
    _ebLateDeadController.dispose();
    _ebExternalPipController.dispose();
    _ebCrackedController.dispose();
    _ebContamController.dispose();
    _opMinController.dispose();
    _opMaxController.dispose();
    _opTargetController.dispose();
    _opNotesController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradientAppBar(title: 'BMK', toolbarHeight: isCompact ? 48 : 52),
      body: Consumer<BmkProvider>(
        builder: (context, bmk, child) {
          final user = context.watch<AuthProvider>().user;
          final canEditStandards =
              (user?.isApproved ?? false) &&
              ((user?.isAdmin ?? false) || (user?.isAuditor ?? false));
          if (!canEditStandards && _mode == _BmkMode.admin) {
            _mode = _BmkMode.reference;
          }
          _syncAdminControllers(bmk);

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
              isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
              isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
              AppSizes.spaceXl,
            ),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1180),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (canEditStandards) ...[
                      _buildModeToolbar(),
                      SizedBox(
                        height: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
                      ),
                    ],
                    if (_mode == _BmkMode.reference) ...[
                      _buildBreedSection(context, bmk),
                      SizedBox(
                        height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
                      ),
                      _buildEggBreakoutSection(context, bmk),
                      SizedBox(
                        height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg,
                      ),
                      _buildOperationalSection(context, bmk),
                    ] else ...[
                      _buildBreedAdminSection(context, bmk),
                      const SizedBox(height: AppSizes.spaceLg),
                      _buildEggBreakoutAdminSection(context, bmk),
                      const SizedBox(height: AppSizes.spaceLg),
                      _buildOperationalAdminSection(context, bmk),
                    ],
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildBreedSection(BuildContext context, BmkProvider bmk) {
    return _BmkSectorCard(
      title: 'Breed Benchmarks',
      icon: Icons.analytics_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControlShelf(
            primary: _buildBreedSelectorBar(bmk),
            secondary: _buildAgeControl(
              label: 'Reference age',
              value: bmk.breedAges.contains(bmk.selectedBreedAge)
                  ? bmk.selectedBreedAge
                  : null,
              ages: bmk.breedAges,
              onChanged: (age) {
                if (age != null) bmk.setBreedAge(age);
              },
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 520
                ? AppSizes.spaceSm
                : AppSizes.spaceLg,
          ),
          if (bmk.breedRow == null)
            const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          else
            _buildMetricGrid(
              key: const ValueKey('bmk-breed-metric-grid'),
              metrics: [
                _BmkMetric(
                  label: 'Hatchability',
                  value: '${_formatNumber(bmk.breedRow!.hatchabilityPct)}%',
                ),
                _BmkMetric(
                  label: 'Fertility',
                  value: '${_formatNumber(bmk.breedRow!.fertilityPct)}%',
                ),
                _BmkMetric(
                  label: 'HOF',
                  value: '${_formatNumber(bmk.breedRow!.hofPct)}%',
                ),
                _BmkMetric(
                  label: 'Production',
                  value: '${_formatNumber(bmk.breedRow!.productionPct)}%',
                ),
                _BmkMetric(
                  label: 'Egg weight',
                  value: '${_formatNumber(bmk.breedRow!.eggWeightG)} g',
                ),
                _BmkMetric(
                  label: 'Chick weight',
                  value: '${_formatNumber(bmk.breedRow!.chickWeightG)} g',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildModeToolbar() {
    return Container(
      key: const ValueKey('bmk-reference-mode-toolbar'),
      padding: const EdgeInsets.all(AppSizes.spaceXs),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildModeButton(
            label: 'Reference',
            icon: Icons.visibility_outlined,
            selected: _mode == _BmkMode.reference,
            onTap: () => setState(() => _mode = _BmkMode.reference),
          ),
          const SizedBox(width: AppSizes.spaceXs),
          _buildModeButton(
            label: 'Admin',
            icon: Icons.admin_panel_settings_outlined,
            selected: _mode == _BmkMode.admin,
            onTap: () => setState(() => _mode = _BmkMode.admin),
          ),
        ],
      ),
    );
  }

  Widget _buildModeButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return _buildSelectablePill(
      label: label,
      icon: icon,
      selected: selected,
      onTap: onTap,
    );
  }

  Widget _buildControlShelf({
    required Widget primary,
    required Widget secondary,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 680) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              primary,
              const SizedBox(height: AppSizes.spaceSm),
              secondary,
            ],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: primary),
            const SizedBox(width: AppSizes.spaceMd),
            secondary,
          ],
        );
      },
    );
  }

  Widget _buildBreedSelectorBar(BmkProvider bmk) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 900
            ? 6
            : width >= 620
            ? 3
            : width >= 300
            ? 3
            : 2;
        const spacing = AppSizes.spaceXs;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          key: const ValueKey('bmk-breed-selector-bar'),
          spacing: spacing,
          runSpacing: spacing,
          children: BmkProvider.breeds.map((breed) {
            return SizedBox(
              width: itemWidth,
              child: _buildSelectablePill(
                label: breed,
                icon: bmk.selectedBreed == breed ? Icons.check : null,
                selected: bmk.selectedBreed == breed,
                onTap: () => bmk.setBreed(breed),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAgeControl({
    required String label,
    required int? value,
    required List<int> ages,
    required ValueChanged<int?> onChanged,
  }) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;

    return Container(
      constraints: BoxConstraints(minHeight: isCompact ? 34 : 44),
      padding: EdgeInsets.symmetric(
        horizontal: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
        vertical: isCompact ? 2 : AppSizes.spaceXs,
      ),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              fontSize: isCompact ? 11 : null,
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          DropdownButtonHideUnderline(
            child: DropdownButton<int>(
              value: value,
              isDense: true,
              icon: const Icon(Icons.keyboard_arrow_down_rounded),
              style: AppTextStyles.title.copyWith(
                fontSize: isCompact ? 14 : null,
              ),
              items: ages.map((age) {
                return DropdownMenuItem(value: age, child: Text('${age}w'));
              }).toList(),
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectablePill({
    required String label,
    IconData? icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final foreground = selected ? AppColors.textOnPrimary : AppColors.textBody;
    final borderColor = selected ? AppColors.primary : AppColors.borderDefault;
    final background = selected ? AppColors.primary : AppColors.surface;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          constraints: BoxConstraints(minHeight: isCompact ? 34 : 44),
          padding: EdgeInsets.symmetric(
            horizontal: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
            vertical: isCompact ? AppSizes.spaceXs : AppSizes.spaceSm,
          ),
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
            border: Border.all(color: borderColor),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: isCompact ? 15 : 18, color: foreground),
                SizedBox(
                  width: isCompact ? AppSizes.spaceXs : AppSizes.spaceSm,
                ),
              ],
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title.copyWith(
                    color: foreground,
                    fontSize: isCompact ? 13 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricGrid({
    required Key key,
    required List<_BmkMetric> metrics,
  }) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 820
            ? 3
            : width >= 300
            ? 2
            : 1;
        final spacing = width < 520 ? AppSizes.spaceXs : AppSizes.spaceSm;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          key: key,
          spacing: spacing,
          runSpacing: spacing,
          children: metrics.map((metric) {
            return SizedBox(width: itemWidth, child: _buildMetricTile(metric));
          }).toList(),
        );
      },
    );
  }

  Widget _buildMetricTile(_BmkMetric metric) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;

    return Container(
      constraints: BoxConstraints(minHeight: isCompact ? 54 : 76),
      padding: EdgeInsets.all(isCompact ? AppSizes.spaceSm : AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  metric.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    fontSize: isCompact ? 11 : null,
                  ),
                ),
                SizedBox(height: isCompact ? 1 : AppSizes.spaceXs),
                Text(
                  metric.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.metricLarge.copyWith(
                    color: AppColors.primary,
                    fontSize: isCompact ? 18 : 22,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBreedAdminSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Breed BMK Admin',
      icon: Icons.edit_note_outlined,
      child: Form(
        key: _breedFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Column(
              children: [
                _buildBreedRow(bmk, BmkProvider.breeds.take(3).toList()),
                const SizedBox(height: 8),
                _buildBreedRow(bmk, BmkProvider.breeds.skip(3).toList()),
              ],
            ),
            const SizedBox(height: 16),
            _buildAgePicker(
              label: 'Age',
              value: bmk.breedAges.contains(bmk.selectedBreedAge)
                  ? bmk.selectedBreedAge
                  : null,
              ages: bmk.breedAges,
              onChanged: (age) {
                if (age != null) bmk.setBreedAge(age);
              },
            ),
            const SizedBox(height: 18),
            if (bmk.breedRow == null)
              const Center(
                child: Text('No data', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              _buildFieldGrid([
                _AdminNumberField(
                  label: 'Hatchability',
                  suffix: '%',
                  controller: _breedHatchabilityController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Fertility',
                  suffix: '%',
                  controller: _breedFertilityController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'HOF',
                  suffix: '%',
                  controller: _breedHofController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Production',
                  suffix: '%',
                  controller: _breedProductionController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Egg weight',
                  suffix: 'g',
                  controller: _breedEggWeightController,
                ),
                _AdminNumberField(
                  label: 'Chick weight',
                  suffix: 'g',
                  controller: _breedChickWeightController,
                ),
              ]),
              const SizedBox(height: 16),
              _buildAdminActions(
                isSaving: _savingBreed,
                onReset: () => _syncBreedControllers(bmk.breedRow, force: true),
                onSave: () => _saveBreedBenchmark(context, bmk),
                saveLabel: 'Save breed BMK',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildEggBreakoutAdminSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Egg Breakout BMK Admin',
      icon: Icons.edit_note_outlined,
      child: Form(
        key: _eggBreakoutFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildAgePicker(
              label: 'Age',
              value: bmk.ebAges.contains(bmk.selectedEbAge)
                  ? bmk.selectedEbAge
                  : null,
              ages: bmk.ebAges,
              onChanged: (age) {
                if (age != null) bmk.setEbAge(age);
              },
            ),
            const SizedBox(height: 18),
            if (bmk.ebRow == null)
              const Center(
                child: Text('No data', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              _buildFieldGrid([
                _AdminNumberField(
                  label: 'Infertile',
                  suffix: '%',
                  controller: _ebInfertileController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: '24 hours',
                  suffix: '%',
                  controller: _ebEarly24hController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: '48 hours',
                  suffix: '%',
                  controller: _ebEarly48hController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Blood Ring',
                  suffix: '%',
                  controller: _ebBloodRingController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Black Eye',
                  suffix: '%',
                  controller: _ebBlackEyeController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Early Dead',
                  suffix: '%',
                  controller: _ebEarlyDeadController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Mid Dead',
                  suffix: '%',
                  controller: _ebMidDeadController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Late Dead',
                  suffix: '%',
                  controller: _ebLateDeadController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'External Pip',
                  suffix: '%',
                  controller: _ebExternalPipController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Cracked',
                  suffix: '%',
                  controller: _ebCrackedController,
                  isPercent: true,
                ),
                _AdminNumberField(
                  label: 'Contaminated',
                  suffix: '%',
                  controller: _ebContamController,
                  isPercent: true,
                ),
              ]),
              const SizedBox(height: 16),
              _buildAdminActions(
                isSaving: _savingEggBreakout,
                onReset: () =>
                    _syncEggBreakoutControllers(bmk.ebRow, force: true),
                onSave: () => _saveEggBreakoutBenchmark(context, bmk),
                saveLabel: 'Save breakout BMK',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildOperationalAdminSection(BuildContext context, BmkProvider bmk) {
    final selected = bmk.selectedOperationalStandard;
    return SectionCard(
      title: 'Operational BMK Admin',
      icon: Icons.tune_outlined,
      child: Form(
        key: _operationalFormKey,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildOperationalHatcherySelector(bmk),
            const SizedBox(height: AppSizes.spaceMd),
            _buildOperationalSelector(bmk),
            const SizedBox(height: 18),
            if (selected == null)
              const Center(
                child: Text('No data', style: TextStyle(color: Colors.grey)),
              )
            else ...[
              Text(
                '${selected.stationKey} · ${selected.sectorKey}',
                style: AppTextStyles.caption,
              ),
              const SizedBox(height: AppSizes.spaceSm),
              _buildFieldGrid([
                _AdminNumberField(
                  label: 'Min',
                  suffix: selected.unit,
                  controller: _opMinController,
                  isPercent: selected.unit == '%',
                  requiredField: false,
                ),
                _AdminNumberField(
                  label: 'Max',
                  suffix: selected.unit,
                  controller: _opMaxController,
                  isPercent: selected.unit == '%',
                  requiredField: false,
                ),
                _AdminNumberField(
                  label: 'Target',
                  suffix: selected.unit,
                  controller: _opTargetController,
                  isPercent: selected.unit == '%',
                  requiredField: false,
                ),
              ]),
              const SizedBox(height: AppSizes.spaceMd),
              TextFormField(
                controller: _opNotesController,
                minLines: 2,
                maxLines: 4,
                decoration: const InputDecoration(
                  labelText: 'Operational notes',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
              const SizedBox(height: AppSizes.spaceMd),
              if (selected.source != null && selected.source!.isNotEmpty)
                Text(
                  'Source: ${selected.source}',
                  style: AppTextStyles.caption,
                ),
              const SizedBox(height: AppSizes.spaceMd),
              _buildAdminActions(
                isSaving: _savingOperational,
                onReset: () =>
                    _syncOperationalControllers(selected, force: true),
                onSave: () => _saveOperationalBenchmark(context, bmk),
                saveLabel: 'Save operational BMK',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAgePicker({
    required String label,
    required int? value,
    required List<int> ages,
    required ValueChanged<int?> onChanged,
  }) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('$label: ', style: const TextStyle(fontWeight: FontWeight.w500)),
        DropdownButton<int>(
          value: value,
          items: ages.map((age) {
            return DropdownMenuItem(value: age, child: Text('${age}w'));
          }).toList(),
          onChanged: onChanged,
        ),
      ],
    );
  }

  Widget _buildFieldGrid(List<_AdminNumberField> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 760
            ? 3
            : width >= 520
            ? 2
            : 1;
        final spacing = AppSizes.spaceMd;
        final itemWidth = (width - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: fields.map((field) {
            return SizedBox(
              width: itemWidth,
              child: TextFormField(
                controller: field.controller,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                decoration: InputDecoration(
                  labelText: field.label,
                  suffixText: field.suffix,
                  border: const OutlineInputBorder(),
                  isDense: true,
                ),
                validator: (value) {
                  return _numberValidator(
                    value,
                    isPercent: field.isPercent,
                    requiredField: field.requiredField,
                  );
                },
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildAdminActions({
    required bool isSaving,
    required VoidCallback onReset,
    required VoidCallback onSave,
    required String saveLabel,
  }) {
    return Wrap(
      spacing: 12,
      runSpacing: 8,
      children: [
        FilledButton.icon(
          onPressed: isSaving ? null : onSave,
          icon: isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.save_outlined),
          label: Text(isSaving ? 'Saving' : saveLabel),
        ),
        OutlinedButton.icon(
          onPressed: isSaving ? null : onReset,
          icon: const Icon(Icons.refresh_outlined),
          label: const Text('Reset'),
        ),
      ],
    );
  }

  Widget _buildEggBreakoutSection(BuildContext context, BmkProvider bmk) {
    return _BmkSectorCard(
      title: 'Egg Breakout BMK',
      icon: Icons.egg_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildControlShelf(
            primary: _buildBreakoutTypeSelector(bmk),
            secondary: _buildAgeControl(
              label: 'Benchmark age',
              value: bmk.ebAges.contains(bmk.selectedEbAge)
                  ? bmk.selectedEbAge
                  : null,
              ages: bmk.ebAges,
              onChanged: (age) {
                if (age != null) bmk.setEbAge(age);
              },
            ),
          ),
          SizedBox(
            height: MediaQuery.sizeOf(context).width < 520
                ? AppSizes.spaceSm
                : AppSizes.spaceLg,
          ),
          if (bmk.ebRow == null)
            const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          else
            _buildEbParameters(bmk),
        ],
      ),
    );
  }

  Widget _buildOperationalSection(BuildContext context, BmkProvider bmk) {
    return _BmkSectorCard(
      title: 'Operational BMKs',
      icon: Icons.tune_outlined,
      child: bmk.operationalStandards.isEmpty
          ? const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          : _buildMetricGrid(
              key: const ValueKey('bmk-operational-metric-grid'),
              metrics: bmk.operationalStandards.map((row) {
                return _BmkMetric(
                  label: row.metricLabel,
                  value: _formatOperationalValue(row),
                );
              }).toList(),
            ),
    );
  }

  Widget _buildOperationalSelector(BmkProvider bmk) {
    final rows = bmk.operationalStandards;
    final selected = bmk.selectedOperationalStandard;
    return Container(
      key: const ValueKey('bmk-operational-standard-selector'),
      constraints: const BoxConstraints(maxWidth: 520),
      child: DropdownButtonFormField<String>(
        initialValue: selected?.metricKey,
        decoration: const InputDecoration(
          labelText: 'Operational BMK',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: rows.map((row) {
          return DropdownMenuItem(
            value: row.metricKey,
            child: Text(
              row.metricLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          );
        }).toList(),
        onChanged: (metricKey) {
          if (metricKey != null) bmk.setOperationalMetric(metricKey);
        },
      ),
    );
  }

  Widget _buildOperationalHatcherySelector(BmkProvider bmk) {
    return Container(
      key: const ValueKey('bmk-operational-hatchery-selector'),
      constraints: const BoxConstraints(maxWidth: 520),
      child: DropdownButtonFormField<String>(
        initialValue: bmk.selectedHatcheryId ?? '',
        decoration: const InputDecoration(
          labelText: 'BMK scope',
          border: OutlineInputBorder(),
          isDense: true,
        ),
        items: [
          const DropdownMenuItem(value: '', child: Text('Global defaults')),
          for (final hatchery in bmk.operationalHatcheries)
            DropdownMenuItem(value: hatchery.id, child: Text(hatchery.label)),
        ],
        onChanged: (value) {
          bmk.setOperationalHatchery(
            value == null || value.isEmpty ? null : value,
          );
        },
      ),
    );
  }

  Widget _buildBreakoutTypeSelector(BmkProvider bmk) {
    final types = [
      _BreakoutTypeOption(type: EbType.fresh, label: 'Fresh'),
      _BreakoutTypeOption(type: EbType.candled, label: 'Candled'),
      _BreakoutTypeOption(type: EbType.residue, label: 'Residue'),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = width >= 300 ? 3 : 1;
        final spacing = width < 520 ? AppSizes.spaceXs : AppSizes.spaceSm;
        final itemWidth = (width - spacing * (columns - 1)) / columns;

        return Wrap(
          key: const ValueKey('bmk-breakout-type-selector'),
          spacing: spacing,
          runSpacing: spacing,
          children: types.map((option) {
            final selected = bmk.selectedEbType == option.type;
            return SizedBox(
              width: itemWidth,
              child: _buildSelectablePill(
                label: option.label,
                selected: selected,
                onTap: () => bmk.setEbType(option.type),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  Widget _buildEbParameters(BmkProvider bmk) {
    final eb = bmk.ebRow!;
    final type = bmk.selectedEbType;

    final List<_BmkMetric> metrics;
    if (type == EbType.fresh) {
      metrics = [
        _breakoutMetric('Infertile', eb.infertilePct),
        _breakoutMetric('24 hours', eb.early24hPct),
        _breakoutMetric('48 hours', eb.early48hPct),
        _breakoutMetric('Blood ring', eb.bloodRingPct),
      ];
    } else if (type == EbType.candled) {
      metrics = [
        _breakoutMetric('Infertile', eb.infertilePct),
        _breakoutMetric('24 hours', eb.early24hPct),
        _breakoutMetric('48 hours', eb.early48hPct),
        _breakoutMetric('Blood ring', eb.bloodRingPct),
        _breakoutMetric('Black eye', eb.blackEyePct),
      ];
    } else {
      metrics = [
        _breakoutMetric('Infertile', eb.infertilePct),
        _breakoutMetric('Early dead', eb.earlyDeadPct),
        _breakoutMetric('Mid dead', eb.midDeadPct),
        _breakoutMetric('Late dead', eb.lateDeadPct),
        _breakoutMetric('External pip', eb.externalPipPct),
        _breakoutMetric('Cracked', eb.crackedPct),
        _breakoutMetric('Contaminated', eb.contamPct),
      ];
    }

    return _buildMetricGrid(
      key: const ValueKey('bmk-breakout-metric-grid'),
      metrics: metrics,
    );
  }

  _BmkMetric _breakoutMetric(String label, double value) {
    return _BmkMetric(label: label, value: '${_formatNumber(value)}%');
  }

  void _syncAdminControllers(BmkProvider bmk) {
    _syncBreedControllers(bmk.breedRow);
    _syncEggBreakoutControllers(bmk.ebRow);
    _syncOperationalControllers(bmk.selectedOperationalStandard);
  }

  void _syncBreedControllers(BmkBreedModel? row, {bool force = false}) {
    final key = row == null ? null : '${row.breed}-${row.ageWeek}';
    if (!force && key == _breedEditKey) return;
    _breedEditKey = key;
    _breedHatchabilityController.text = _formatNumber(row?.hatchabilityPct);
    _breedFertilityController.text = _formatNumber(row?.fertilityPct);
    _breedHofController.text = _formatNumber(row?.hofPct);
    _breedProductionController.text = _formatNumber(row?.productionPct);
    _breedEggWeightController.text = _formatNumber(row?.eggWeightG);
    _breedChickWeightController.text = _formatNumber(row?.chickWeightG);
  }

  void _syncEggBreakoutControllers(
    BmkEggBreakoutModel? row, {
    bool force = false,
  }) {
    final key = row == null ? null : '${row.ageWeek}';
    if (!force && key == _ebEditKey) return;
    _ebEditKey = key;
    _ebInfertileController.text = _formatNumber(row?.infertilePct);
    _ebEarly24hController.text = _formatNumber(row?.early24hPct);
    _ebEarly48hController.text = _formatNumber(row?.early48hPct);
    _ebBloodRingController.text = _formatNumber(row?.bloodRingPct);
    _ebBlackEyeController.text = _formatNumber(row?.blackEyePct);
    _ebEarlyDeadController.text = _formatNumber(row?.earlyDeadPct);
    _ebMidDeadController.text = _formatNumber(row?.midDeadPct);
    _ebLateDeadController.text = _formatNumber(row?.lateDeadPct);
    _ebExternalPipController.text = _formatNumber(row?.externalPipPct);
    _ebCrackedController.text = _formatNumber(row?.crackedPct);
    _ebContamController.text = _formatNumber(row?.contamPct);
  }

  void _syncOperationalControllers(
    BmkOperationalStandardModel? row, {
    bool force = false,
  }) {
    final key = row?.id;
    if (!force && key == _opEditKey) return;
    _opEditKey = key;
    _opMinController.text = _formatNumber(row?.minValue);
    _opMaxController.text = _formatNumber(row?.maxValue);
    _opTargetController.text = _formatNumber(row?.targetValue);
    _opNotesController.text = row?.notes ?? '';
  }

  Future<void> _saveBreedBenchmark(
    BuildContext context,
    BmkProvider bmk,
  ) async {
    if (_breedFormKey.currentState?.validate() != true) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingBreed = true);
    try {
      await bmk.saveSelectedBreedBenchmark(
        hatchabilityPct: _parseController(_breedHatchabilityController),
        fertilityPct: _parseController(_breedFertilityController),
        hofPct: _parseController(_breedHofController),
        productionPct: _parseController(_breedProductionController),
        eggWeightG: _parseController(_breedEggWeightController),
        chickWeightG: _parseController(_breedChickWeightController),
      );
      if (!mounted) return;
      messenger.showSnackBar(const SnackBar(content: Text('Breed BMK saved')));
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save breed BMK: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingBreed = false);
    }
  }

  Future<void> _saveEggBreakoutBenchmark(
    BuildContext context,
    BmkProvider bmk,
  ) async {
    if (_eggBreakoutFormKey.currentState?.validate() != true) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingEggBreakout = true);
    try {
      await bmk.saveSelectedEggBreakoutBenchmark(
        infertilePct: _parseController(_ebInfertileController),
        early24hPct: _parseController(_ebEarly24hController),
        early48hPct: _parseController(_ebEarly48hController),
        bloodRingPct: _parseController(_ebBloodRingController),
        blackEyePct: _parseController(_ebBlackEyeController),
        earlyDeadPct: _parseController(_ebEarlyDeadController),
        midDeadPct: _parseController(_ebMidDeadController),
        lateDeadPct: _parseController(_ebLateDeadController),
        externalPipPct: _parseController(_ebExternalPipController),
        crackedPct: _parseController(_ebCrackedController),
        contamPct: _parseController(_ebContamController),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Egg Breakout BMK saved')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save Egg Breakout BMK: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingEggBreakout = false);
    }
  }

  Future<void> _saveOperationalBenchmark(
    BuildContext context,
    BmkProvider bmk,
  ) async {
    if (_operationalFormKey.currentState?.validate() != true) return;
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _savingOperational = true);
    try {
      await bmk.saveSelectedOperationalStandard(
        minValue: _parseOptionalController(_opMinController),
        maxValue: _parseOptionalController(_opMaxController),
        targetValue: _parseOptionalController(_opTargetController),
        notes: _opNotesController.text.trim().isEmpty
            ? null
            : _opNotesController.text.trim(),
      );
      if (!mounted) return;
      messenger.showSnackBar(
        const SnackBar(content: Text('Operational BMK saved')),
      );
    } catch (error) {
      if (!mounted) return;
      messenger.showSnackBar(
        SnackBar(content: Text('Could not save operational BMK: $error')),
      );
    } finally {
      if (mounted) setState(() => _savingOperational = false);
    }
  }

  String? _numberValidator(
    String? value, {
    required bool isPercent,
    bool requiredField = true,
  }) {
    final text = value?.trim() ?? '';
    if (text.isEmpty && !requiredField) return null;
    if (text.isEmpty) return 'Required';
    final number = double.tryParse(text);
    if (number == null) return 'Enter a number';
    if (number < 0) return 'Must be 0 or more';
    if (isPercent && number > 100) return 'Max 100';
    return null;
  }

  double _parseController(TextEditingController controller) {
    return double.parse(controller.text.trim());
  }

  double? _parseOptionalController(TextEditingController controller) {
    final text = controller.text.trim();
    if (text.isEmpty) return null;
    return double.parse(text);
  }

  String _formatNumber(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
  }

  String _formatOperationalValue(BmkOperationalStandardModel row) {
    final min = row.minValue;
    final max = row.maxValue;
    final target = row.targetValue;
    final unit = row.unit;
    if (min != null && max != null) {
      return '${_formatNumber(min)}-${_formatNumber(max)}$unit';
    }
    if (min != null) return '>= ${_formatNumber(min)}$unit';
    if (max != null) return '<= ${_formatNumber(max)}$unit';
    if (target != null) return '${_formatNumber(target)}$unit';
    return '--';
  }

  Widget _buildBreedRow(BmkProvider bmk, List<String> breeds) {
    return Row(
      children: breeds.map((breed) {
        final isSelected = bmk.selectedBreed == breed;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: ChoiceChip(
              label: Center(child: Text(breed)),
              selected: isSelected,
              selectedColor: AppColors.primary,
              labelStyle: TextStyle(
                color: isSelected ? Colors.white : Colors.black87,
                fontWeight: FontWeight.w500,
              ),
              onSelected: (_) => bmk.setBreed(breed),
            ),
          ),
        );
      }).toList(),
    );
  }
}

class _BmkSectorCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _BmkSectorCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    final isCompact = MediaQuery.sizeOf(context).width < 520;
    final padding = isCompact ? AppSizes.spaceSm : AppSizes.spaceLg;
    final iconSize = isCompact ? 32.0 : AppSizes.iconContainerSm;

    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
        boxShadow: AppElevation.level1,
      ),
      child: Padding(
        padding: EdgeInsets.all(padding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  width: iconSize,
                  height: iconSize,
                  decoration: BoxDecoration(
                    color: AppColors.activeBg,
                    borderRadius: BorderRadius.circular(AppSizes.iconRadius),
                  ),
                  child: Icon(
                    icon,
                    color: AppColors.primary,
                    size: isCompact ? 18 : AppSizes.iconSm,
                  ),
                ),
                SizedBox(
                  width: isCompact ? AppSizes.spaceSm : AppSizes.spaceMd,
                ),
                Expanded(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.sectionTitle.copyWith(
                      fontSize: isCompact ? 16 : null,
                    ),
                  ),
                ),
              ],
            ),
            SizedBox(height: isCompact ? AppSizes.spaceSm : AppSizes.spaceLg),
            child,
          ],
        ),
      ),
    );
  }
}

class _BmkMetric {
  final String label;
  final String value;

  const _BmkMetric({required this.label, required this.value});
}

class _BreakoutTypeOption {
  final EbType type;
  final String label;

  const _BreakoutTypeOption({required this.type, required this.label});
}

class _AdminNumberField {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final bool isPercent;
  final bool requiredField;

  const _AdminNumberField({
    required this.label,
    required this.suffix,
    required this.controller,
    this.isPercent = false,
    this.requiredField = true,
  });
}
