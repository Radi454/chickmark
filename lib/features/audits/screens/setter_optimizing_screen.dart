import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/models/audit_model.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/photo_button.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class SetterOptimizingScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final int initialSectionIndex;

  const SetterOptimizingScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialSectionIndex = 0,
  });
  @override
  State<SetterOptimizingScreen> createState() => _SetterOptimizingScreenState();
}

class _SetterOptimizingScreenState extends State<SetterOptimizingScreen> {
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    5,
    (_) => GlobalKey(),
  );
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _photos = {};
  final TextEditingController _avgController = TextEditingController();
  final TextEditingController _cvController = TextEditingController();
  final TextEditingController _incubationAgeController = TextEditingController(
    text: '1',
  );
  late final TextEditingController _setterIdController;
  String? _machineType;
  final TextEditingController _turningAngleController = TextEditingController();

  List<TextInputFormatter> get _decimalInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
  ];

  @override
  void initState() {
    super.initState();
    _setterIdController = TextEditingController(
      text:
          widget.initialAudit?.setterId ??
          widget.initialAudit?.soSetterId ??
          widget.context.setterId ??
          '',
    );
    _incubationAgeController.text = (widget.initialAudit?.soIncubationAge ?? 1)
        .toString();
    _machineType = widget.initialAudit?.soMachineType;
    _turningAngleController.text = widget.initialAudit?.soTurningAngle != null
        ? widget.initialAudit!.soTurningAngle!.toStringAsFixed(1)
        : '';
    final rows = ['Door', 'Middle', 'Back'];
    final cols = ['Top', 'Middle', 'Bottom'];
    for (var r in rows) {
      for (var c in cols) {
        _controllers['${r}_$c'] = TextEditingController();
      }
    }
    _loadEstReadings(widget.initialAudit?.soEstReadings);
    if (widget.initialAudit?.soEstAvg != null) {
      _avgController.text = widget.initialAudit!.soEstAvg!.toStringAsFixed(1);
    }
    if (widget.initialAudit?.soEstCv != null) {
      _cvController.text = widget.initialAudit!.soEstCv!.toStringAsFixed(1);
    }
    _loadEstPhotos(widget.initialAudit?.soEstPhotos);
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    auditProvider.initialize(
      AuditContext(
        auditType: widget.context.auditType,
        customerId: widget.context.customerId,
        flockId: widget.context.flockId,
        breed: widget.context.breed,
        setterId: widget.context.setterId,
        hatcherId: widget.context.hatcherId,
        date: widget.context.date,
      ),
      existingAudit: widget.initialAudit,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
      sessionId: widget.context.sessionId,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialSection();
    });
  }

  void _loadEstReadings(String? readingsJson) {
    if (readingsJson == null || readingsJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(readingsJson);
      if (decoded is! Map) return;
      for (var entry in decoded.entries) {
        final key = entry.key;
        if (_controllers.containsKey(key)) {
          final val = entry.value;
          if (val is num) {
            _controllers[key]!.text = val.toStringAsFixed(1);
          }
        }
      }
    } catch (_) {
      // Keep grid blank if stored data is malformed.
    }
  }

  void _loadEstPhotos(String? photosJson) {
    if (photosJson == null || photosJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(photosJson);
      if (decoded is! Map) return;
      for (var entry in decoded.entries) {
        if (entry.value is String) {
          _photos[entry.key] = entry.value as String;
        }
      }
    } catch (_) {
      // Keep photos empty if stored data is malformed.
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    _avgController.dispose();
    _cvController.dispose();
    _incubationAgeController.dispose();
    _setterIdController.dispose();
    _turningAngleController.dispose();
    super.dispose();
  }

  void _updateCalculations() {
    final temps = _controllers.values
        .map((c) => double.tryParse(c.text))
        .where((t) => t != null)
        .map((t) => t!)
        .toList();
    if (temps.isEmpty) {
      setState(() {
        _avgController.text = '';
        _cvController.text = '';
      });
      return;
    }
    final avg = CalculationUtils.average(temps);
    final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;
    setState(() {
      _avgController.text = avg.toStringAsFixed(1);
      _cvController.text = cv.toStringAsFixed(1);
    });
    final readings = _controllers.map((key, value) {
      return MapEntry(key, double.tryParse(value.text));
    });
    final auditProvider = context.read<AuditProvider>();
    auditProvider.updateField('soEstReadings', jsonEncode(readings));
    auditProvider.updateField('soEstPhotos', jsonEncode(_photos));
    auditProvider.updateField('soEstAvg', avg);
    auditProvider.updateField('soEstCv', cv);
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();
    final audit = auditProvider.activeDraft;
    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Setter Optimizing',
                actions: [
                  if (auditProvider.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => auditProvider.setEditMode(true),
                    ),
                ],
              ),
        body: AuditKeyboardDismiss(
          child: SingleChildScrollView(
            controller: _scrollController,
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Card(
                  key: _sectionKeys[0],
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSizes.cardPadding),
                    child: Column(
                      children: [
                        InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Breed from flock',
                            border: OutlineInputBorder(),
                          ),
                          child: Text(
                            audit.soBreed ?? widget.context.breed ?? 'Unknown',
                          ),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _setterIdController,
                          enabled: !auditProvider.isReadOnly,
                          decoration: const InputDecoration(
                            labelText: 'Setter ID',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) {
                            auditProvider.updateField('setterId', v);
                            auditProvider.updateField('soSetterId', v);
                          },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSizes.cardPadding),
                    child: Column(
                      children: [
                        Text(
                          'Incubation Age: ${_incubationAgeController.text} days',
                          style: AppTextStyles.body,
                        ),
                        Slider(
                          value:
                              double.tryParse(_incubationAgeController.text) ??
                              1,
                          min: 1,
                          max: 18,
                          divisions: 17,
                          onChanged: auditProvider.isReadOnly
                              ? null
                              : (v) {
                                  final age = v.toInt();
                                  setState(() {
                                    _incubationAgeController.text = age
                                        .toString();
                                  });
                                  auditProvider.updateField(
                                    'soIncubationAge',
                                    age,
                                  );
                                },
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  key: _sectionKeys[1],
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSizes.cardPadding),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Machine Type',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 6,
                          runSpacing: 6,
                          children: ['Single Stage', 'Multi Stage'].map((type) {
                            final selected = _machineType == type;
                            return ChoiceChip(
                              label: Text(type),
                              selected: selected,
                              onSelected: auditProvider.isReadOnly
                                  ? null
                                  : (_) {
                                      setState(() => _machineType = type);
                                      auditProvider.updateField(
                                        'so_machineType',
                                        type,
                                      );
                                    },
                              selectedColor: AppColors.primary.withAlpha(30),
                              checkmarkColor: AppColors.primary,
                              labelStyle: AppTextStyles.body.copyWith(
                                color: selected
                                    ? AppColors.primary
                                    : Colors.black87,
                                fontWeight: selected
                                    ? FontWeight.w700
                                    : FontWeight.w500,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8),
                                side: BorderSide(
                                  color: selected
                                      ? AppColors.primary
                                      : Colors.grey[300]!,
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                        const SizedBox(height: 12),
                        TextField(
                          controller: _turningAngleController,
                          enabled: !auditProvider.isReadOnly,
                          keyboardType: const TextInputType.numberWithOptions(
                            decimal: true,
                          ),
                          decoration: const InputDecoration(
                            labelText: 'Turning Angle (°)',
                            border: OutlineInputBorder(),
                          ),
                          inputFormatters: _decimalInputFormatters,
                          onChanged: (v) => auditProvider.updateField(
                            'so_turningAngle',
                            double.tryParse(v),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  key: _sectionKeys[2],
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSizes.cardPadding),
                    child: Column(
                      children: [
                        TextField(
                          enabled: !auditProvider.isReadOnly,
                          decoration: const InputDecoration(
                            labelText: 'CO2 Level (ppm)',
                            border: OutlineInputBorder(),
                          ),
                          onChanged: (v) => auditProvider.updateField(
                            'soCo2',
                            double.tryParse(v),
                          ),
                        ),
                        const SizedBox(height: 8),
                        PhotoButton(
                          photoPath: audit.soCo2Photo,
                          enabled: !auditProvider.isReadOnly,
                          onPhotoCaptured: (p) =>
                              auditProvider.updateField('soCo2Photo', p),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: _statCard('AVG', _avgController.text, null),
                    ),
                    const SizedBox(width: 8),
                    Expanded(child: _statCard('CV%', _cvController.text, null)),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  key: _sectionKeys[3],
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(AppSizes.cardPadding),
                    child: Column(
                      children: [
                        Text(
                          'Egg Shell Temperature (EST) - Optimum: 100-101°F',
                          style: AppTextStyles.body,
                        ),
                        _buildEstGrid(auditProvider),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statCard(String label, String value, Color? color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        Text(label, style: AppTextStyles.caption),
        Text(value.isEmpty ? '--' : value, style: AppTextStyles.heading),
      ],
    ),
  );

  void _scrollToInitialSection() {
    final index = widget.initialSectionIndex
        .clamp(0, _sectionKeys.length - 1)
        .toInt();
    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Widget _buildEstGrid(AuditProvider provider) {
    final rows = ['Door', 'Middle', 'Back'];
    final cols = ['Top', 'Middle', 'Bottom'];
    return Column(
      children: [
        for (var r in rows)
          Row(
            children: [
              SizedBox(width: 60, child: Text(r, style: AppTextStyles.body)),
              for (var c in cols)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: _buildGridCell(provider, '${r}_$c'),
                  ),
                ),
            ],
          ),
      ],
    );
  }

  Widget _buildGridCell(AuditProvider provider, String key) {
    final value = double.tryParse(_controllers[key]?.text ?? '');
    final isGood = value != null && value >= 100 && value <= 101;
    final borderColor = value == null
        ? Colors.grey[300]!
        : (isGood ? AppColors.greenTab : Colors.red);

    return Container(
      padding: const EdgeInsets.all(6),
      decoration: BoxDecoration(
        border: Border.all(color: borderColor, width: value == null ? 1 : 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          TextField(
            controller: _controllers[key],
            enabled: !provider.isReadOnly,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onChanged: (_) => _updateCalculations(),
          ),
          const SizedBox(height: 4),
          Icon(
            value == null
                ? Icons.circle_outlined
                : isGood
                ? Icons.check_circle
                : Icons.error,
            color: value == null
                ? Colors.grey
                : isGood
                ? AppColors.greenTab
                : Colors.red,
            size: 18,
          ),
          const SizedBox(height: 4),
          PhotoButton(
            photoPath: _photos[key],
            enabled: !provider.isReadOnly,
            onPhotoCaptured: (path) {
              setState(() => _photos[key] = path);
              provider.updateField('soEstPhotos', jsonEncode(_photos));
            },
          ),
        ],
      ),
    );
  }
}
