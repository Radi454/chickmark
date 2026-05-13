import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:hatchaudit/core/theme/gradient_app_bar.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';
import 'package:hatchaudit/core/constants/app_sizes.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
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

  _BmkMode _mode = _BmkMode.reference;
  String? _breedEditKey;
  String? _ebEditKey;
  bool _savingBreed = false;
  bool _savingEggBreakout = false;

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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'BMK'),
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
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (canEditStandards) ...[
                  _buildModeSelector(),
                  const SizedBox(height: 20),
                ],
                if (_mode == _BmkMode.reference) ...[
                  _buildBreedSection(context, bmk),
                  const SizedBox(height: 24),
                  _buildEggBreakoutSection(context, bmk),
                ] else ...[
                  _buildBreedAdminSection(context, bmk),
                  const SizedBox(height: 24),
                  _buildEggBreakoutAdminSection(context, bmk),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildBreedSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Breed Benchmarks',
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
          Row(
            children: [
              const Text(
                'Age: ',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              DropdownButton<int>(
                value: bmk.breedAges.contains(bmk.selectedBreedAge)
                    ? bmk.selectedBreedAge
                    : null,
                items: bmk.breedAges.map((age) {
                  return DropdownMenuItem(value: age, child: Text('${age}w'));
                }).toList(),
                onChanged: (age) {
                  if (age != null) bmk.setBreedAge(age);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
          if (bmk.breedRow == null)
            const Center(
              child: Text('No data', style: TextStyle(color: Colors.grey)),
            )
          else
            GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              childAspectRatio: 1.2,
              children: [
                _buildMetricTile(
                  'Hatchability %',
                  '${bmk.breedRow!.hatchabilityPct}%',
                ),
                _buildMetricTile(
                  'Fertility %',
                  '${bmk.breedRow!.fertilityPct}%',
                ),
                _buildMetricTile('HOF %', '${bmk.breedRow!.hofPct}%'),
                _buildMetricTile(
                  'Production %',
                  '${bmk.breedRow!.productionPct}%',
                ),
                _buildMetricTile(
                  'Egg Weight (g)',
                  '${bmk.breedRow!.eggWeightG}',
                ),
                _buildMetricTile(
                  'Chick Weight (g)',
                  '${bmk.breedRow!.chickWeightG}',
                ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildMetricTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(8),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            style: const TextStyle(fontSize: 11, color: Colors.grey),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildModeSelector() {
    return Align(
      alignment: Alignment.centerLeft,
      child: SegmentedButton<_BmkMode>(
        segments: const [
          ButtonSegment(
            value: _BmkMode.reference,
            icon: Icon(Icons.visibility_outlined),
            label: Text('Reference'),
          ),
          ButtonSegment(
            value: _BmkMode.admin,
            icon: Icon(Icons.admin_panel_settings_outlined),
            label: Text('Admin'),
          ),
        ],
        selected: {_mode},
        onSelectionChanged: (selected) {
          setState(() {
            _mode = selected.first;
          });
        },
        style: ButtonStyle(
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return AppColors.primary;
            }
            return null;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.selected)) {
              return Colors.white;
            }
            return null;
          }),
        ),
      ),
    );
  }

  Widget _buildBreedAdminSection(BuildContext context, BmkProvider bmk) {
    return SectionCard(
      title: 'Breed BMK Admin',
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
                  return _numberValidator(value, isPercent: field.isPercent);
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
    return SectionCard(
      title: 'Egg Breakout BMK',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              FilterChip(
                label: const Text('🥚 Fresh'),
                selected: bmk.selectedEbType == EbType.fresh,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: bmk.selectedEbType == EbType.fresh
                      ? Colors.white
                      : Colors.black87,
                ),
                onSelected: (_) => bmk.setEbType(EbType.fresh),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('🔍 Candled'),
                selected: bmk.selectedEbType == EbType.candled,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: bmk.selectedEbType == EbType.candled
                      ? Colors.white
                      : Colors.black87,
                ),
                onSelected: (_) => bmk.setEbType(EbType.candled),
              ),
              const SizedBox(width: 8),
              FilterChip(
                label: const Text('🐣 Residue'),
                selected: bmk.selectedEbType == EbType.residue,
                selectedColor: AppColors.primary,
                labelStyle: TextStyle(
                  color: bmk.selectedEbType == EbType.residue
                      ? Colors.white
                      : Colors.black87,
                ),
                onSelected: (_) => bmk.setEbType(EbType.residue),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              const Text(
                'Age: ',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              DropdownButton<int>(
                value: bmk.ebAges.contains(bmk.selectedEbAge)
                    ? bmk.selectedEbAge
                    : null,
                items: bmk.ebAges.map((age) {
                  return DropdownMenuItem(value: age, child: Text('${age}w'));
                }).toList(),
                onChanged: (age) {
                  if (age != null) bmk.setEbAge(age);
                },
              ),
            ],
          ),
          const SizedBox(height: 16),
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

  Widget _buildEbParameters(BmkProvider bmk) {
    final eb = bmk.ebRow!;
    final type = bmk.selectedEbType;

    final Map<String, double> params;
    if (type == EbType.fresh) {
      params = {
        'Infertile': eb.infertilePct,
        '24 hours': eb.early24hPct,
        '48 hours': eb.early48hPct,
        'Blood Ring': eb.bloodRingPct,
      };
    } else if (type == EbType.candled) {
      params = {
        'Infertile': eb.infertilePct,
        '24 hours': eb.early24hPct,
        '48 hours': eb.early48hPct,
        'Blood Ring': eb.bloodRingPct,
        'Black Eye': eb.blackEyePct,
      };
    } else {
      params = {
        'Infertile': eb.infertilePct,
        'Early Dead': eb.earlyDeadPct,
        'Mid Dead': eb.midDeadPct,
        'Late Dead': eb.lateDeadPct,
        'External Pip': eb.externalPipPct,
        'Cracked': eb.crackedPct,
        'Contaminated': eb.contamPct,
      };
    }

    final entries = params.entries.toList();

    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        childAspectRatio: 1.5,
        mainAxisSpacing: 8,
        crossAxisSpacing: 8,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        return Container(
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(
                entry.key,
                style: const TextStyle(fontSize: 10, color: Colors.grey),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 2),
              Text(
                '${entry.value}%',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.primary,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _syncAdminControllers(BmkProvider bmk) {
    _syncBreedControllers(bmk.breedRow);
    _syncEggBreakoutControllers(bmk.ebRow);
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

  String? _numberValidator(String? value, {required bool isPercent}) {
    final text = value?.trim() ?? '';
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

  String _formatNumber(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toStringAsFixed(0);
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'0$'), '');
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

class _AdminNumberField {
  final String label;
  final String suffix;
  final TextEditingController controller;
  final bool isPercent;

  const _AdminNumberField({
    required this.label,
    required this.suffix,
    required this.controller,
    this.isPercent = false,
  });
}
