import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/audit_workbench_shell.dart';
import '../widgets/photo_button.dart';
import '../widgets/sample_mode_controls.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class SetterOptimizingScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final List<AuditModel> initialAudits;
  final List<StationSampleModel> initialStationSamples;
  final int initialSectionIndex;

  const SetterOptimizingScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialAudits = const [],
    this.initialStationSamples = const [],
    this.initialSectionIndex = -1,
  });
  @override
  State<SetterOptimizingScreen> createState() => _SetterOptimizingScreenState();
}

class _SetterOptimizingScreenState extends State<SetterOptimizingScreen> {
  static const List<String> _gridRows = ['Door', 'Middle', 'Back'];
  static const List<String> _gridColumns = ['Top', 'Middle', 'Bottom'];
  static const String _gridNavigationGroup = 'setter-est-grid';

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
  final TextEditingController _co2Controller = TextEditingController();
  String? _activeAuditId;

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
    _co2Controller.text = widget.initialAudit?.soCo2 != null
        ? widget.initialAudit!.soCo2!.toStringAsFixed(1)
        : '';
    for (var r in _gridRows) {
      for (var c in _gridColumns) {
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
        flockEntryDate: widget.context.flockEntryDate,
        flockAgeWeeks: widget.context.flockAgeWeeks,
        date: widget.context.date,
      ),
      existingAudit: widget.initialAudit,
      existingAudits: widget.initialAudits,
      existingStationSamples: widget.initialStationSamples,
      readOnly: widget.context.sessionId == null ? null : false,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
      sessionId: widget.context.sessionId,
    );
    _activeAuditId = auditProvider.activeDraft.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialSection();
    });
  }

  void _syncActiveSampleForm(AuditModel audit) {
    if (_activeAuditId == audit.id) return;
    _activeAuditId = audit.id;
    _setterIdController.text = audit.setterId ?? audit.soSetterId ?? '';
    _incubationAgeController.text = (audit.soIncubationAge ?? 1).toString();
    _machineType = audit.soMachineType;
    _turningAngleController.text = audit.soTurningAngle != null
        ? audit.soTurningAngle!.toStringAsFixed(1)
        : '';
    _co2Controller.text = audit.soCo2 != null
        ? audit.soCo2!.toStringAsFixed(1)
        : '';
    for (final controller in _controllers.values) {
      controller.clear();
    }
    _photos.clear();
    _avgController.text = audit.soEstAvg != null
        ? audit.soEstAvg!.toStringAsFixed(1)
        : '';
    _cvController.text = audit.soEstCv != null
        ? audit.soEstCv!.toStringAsFixed(1)
        : '';
    _loadEstReadings(audit.soEstReadings);
    _loadEstPhotos(audit.soEstPhotos);
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
    _co2Controller.dispose();
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
    _syncActiveSampleForm(audit);
    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        backgroundColor: const Color(0xFFF4F6F8),
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Setters',
                actions: [
                  if (auditProvider.isReadOnly)
                    IconButton(
                      icon: const Icon(Icons.edit),
                      onPressed: () => auditProvider.setEditMode(true),
                    ),
                ],
              ),
        body: AuditNumericKeyboardScope(
          child: AuditKeyboardDismiss(
            child: SafeArea(
              child: SingleChildScrollView(
                controller: _scrollController,
                child: AuditWorkbenchShell(
                  key: const ValueKey('setter-workbench-shell'),
                  children: [
                    _buildSetterHeader(audit),
                    const SizedBox(height: 16),
                    StationSampleModeControls(
                      provider: auditProvider,
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 16),
                    _buildSetterWorkbench(audit, auditProvider),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetterHeader(AuditModel audit) {
    final setterId = _setterIdController.text.trim();
    final age = _incubationAgeController.text.trim();
    return AuditStationHero(
      heroKey: const ValueKey('setter-station-header'),
      icon: Icons.thermostat,
      eyebrow: 'SETTER WORKBENCH',
      title: 'Setters',
      subtitle: 'Machine setup, airflow checks, and EST profile in one pass.',
      details: [
        AuditHeroDetail(
          label: 'Breed',
          value: audit.soBreed ?? widget.context.breed ?? 'Unknown',
        ),
        AuditHeroDetail(
          label: 'Setter',
          value: setterId.isEmpty ? 'Not set' : setterId,
        ),
        AuditHeroDetail(
          label: 'Age',
          value: age.isEmpty ? '1 days' : '$age days',
        ),
        const AuditHeroDetail(label: 'EST target', value: '100-101°F'),
      ],
    );
  }

  Widget _buildSetterWorkbench(AuditModel audit, AuditProvider auditProvider) {
    return AuditPanelColumns(
      left: [
        KeyedSubtree(
          key: _sectionKeys[0],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('setter-panel-setup'),
            mark: 'ID',
            icon: Icons.badge_outlined,
            title: 'Flock and setter',
            meta: 'Confirm the flock context and active machine.',
            statusLabel: _setterIdController.text.trim().isEmpty
                ? 'Needs ID'
                : 'Ready',
            statusColor: _setterIdController.text.trim().isEmpty
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildSetterSetupPanel(audit, auditProvider),
          ),
        ),
        KeyedSubtree(
          key: _sectionKeys[1],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('setter-panel-machine'),
            mark: 'MC',
            icon: Icons.tune_outlined,
            title: 'Machine setup',
            meta: 'Machine type and turning-angle confirmation.',
            statusLabel: _machineType == null ? 'Select type' : 'Type set',
            statusColor: _machineType == null
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildMachineSetupPanel(auditProvider),
          ),
        ),
        KeyedSubtree(
          key: _sectionKeys[2],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('setter-panel-environment'),
            mark: 'CO2',
            icon: Icons.co2_outlined,
            title: 'Environment check',
            meta: 'Record CO2 and attach supporting evidence.',
            statusLabel: _co2Controller.text.trim().isEmpty
                ? 'CO2 pending'
                : '${_co2Controller.text.trim()} ppm',
            statusColor: _co2Controller.text.trim().isEmpty
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildSetterEnvironmentPanel(audit, auditProvider),
          ),
        ),
      ],
      right: [
        KeyedSubtree(
          key: _sectionKeys[3],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('setter-panel-est'),
            mark: 'EST',
            icon: Icons.grid_on,
            title: 'Egg Shell Temperature',
            meta: 'Nine-point EST profile with photo evidence.',
            statusLabel: _avgController.text.trim().isEmpty
                ? 'Readings pending'
                : 'Avg ${_avgController.text.trim()}°F',
            statusColor: _avgController.text.trim().isEmpty
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildSetterEstPanel(auditProvider),
          ),
        ),
      ],
    );
  }

  Widget _buildSetterSetupPanel(AuditModel audit, AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InputDecorator(
          decoration: InputDecoration(
            labelText: 'Breed from flock',
            isDense: true,
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          child: Text(audit.soBreed ?? widget.context.breed ?? 'Unknown'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _setterIdController,
          enabled: !auditProvider.isReadOnly,
          decoration: InputDecoration(
            labelText: 'Setter ID',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) {
            setState(() {});
            auditProvider.updateField('setterId', v);
            auditProvider.updateField('soSetterId', v);
          },
        ),
        const SizedBox(height: 16),
        _buildAgeSlider(
          label: 'Incubation age',
          min: 1,
          max: 18,
          divisions: 17,
          value: double.tryParse(_incubationAgeController.text) ?? 1,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            final age = v.toInt();
            setState(() => _incubationAgeController.text = age.toString());
            auditProvider.updateField('soIncubationAge', age);
          },
        ),
      ],
    );
  }

  Widget _buildMachineSetupPanel(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Machine type',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Single Stage', 'Multi Stage'].map((type) {
            final selected = _machineType == type;
            return ChoiceChip(
              label: Text(type),
              selected: selected,
              onSelected: auditProvider.isReadOnly
                  ? null
                  : (_) {
                      setState(() => _machineType = type);
                      auditProvider.updateField('so_machineType', type);
                    },
              selectedColor: AppColors.primary.withAlpha(30),
              checkmarkColor: AppColors.primary,
              labelStyle: AppTextStyles.body.copyWith(
                color: selected ? AppColors.primary : Colors.black87,
                fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: selected ? AppColors.primary : Colors.grey[300]!,
                ),
              ),
            );
          }).toList(),
        ),
        const SizedBox(height: 14),
        AuditNumericField(
          controller: _turningAngleController,
          enabled: !auditProvider.isReadOnly,
          allowDecimal: true,
          maxDecimalPlaces: 1,
          decoration: InputDecoration(
            labelText: 'Turning Angle (°)',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) =>
              auditProvider.updateField('so_turningAngle', double.tryParse(v)),
        ),
      ],
    );
  }

  Widget _buildSetterEnvironmentPanel(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AuditNumericField(
          controller: _co2Controller,
          enabled: !auditProvider.isReadOnly,
          allowDecimal: true,
          decoration: InputDecoration(
            labelText: 'CO2 Level',
            suffixText: 'ppm',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) {
            setState(() {});
            auditProvider.updateField('soCo2', double.tryParse(v));
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: PhotoButton(
            photoPath: audit.soCo2Photo,
            enabled: !auditProvider.isReadOnly,
            onPhotoCaptured: (p) => auditProvider.updateField('soCo2Photo', p),
          ),
        ),
      ],
    );
  }

  Widget _buildSetterEstPanel(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Optimum range: 100-101°F',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: AuditMetricCard(
                label: 'AVG',
                value: _avgController.text.isEmpty
                    ? ''
                    : '${_avgController.text}°F',
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: AuditMetricCard(
                label: 'CV%',
                value: _cvController.text.isEmpty
                    ? ''
                    : '${_cvController.text}%',
                color: Colors.blueGrey,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _buildEstGrid(auditProvider),
      ],
    );
  }

  Widget _buildAgeSlider({
    required String label,
    required double min,
    required double max,
    required int divisions,
    required double value,
    required bool enabled,
    required ValueChanged<double> onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            Text(
              '${value.toInt()} days',
              style: AppTextStyles.body.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          onChanged: enabled ? onChanged : null,
        ),
      ],
    );
  }

  void _scrollToInitialSection() {
    if (widget.initialSectionIndex < 0) return;
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
    return Column(
      children: [
        for (var r in _gridRows)
          Row(
            children: [
              SizedBox(width: 60, child: Text(r, style: AppTextStyles.body)),
              for (var c in _gridColumns)
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
          AuditNumericField(
            controller: _controllers[key]!,
            enabled: !provider.isReadOnly,
            allowDecimal: true,
            maxDecimalPlaces: 1,
            navigationGroup: _gridNavigationGroup,
            navigationRow: _gridRows.indexOf(key.split('_').first),
            navigationColumn: _gridColumns.indexOf(key.split('_').last),
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
