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

class HatcherOptimizingScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final List<AuditModel> initialAudits;
  final List<StationSampleModel> initialStationSamples;
  final int initialSectionIndex;

  const HatcherOptimizingScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialAudits = const [],
    this.initialStationSamples = const [],
    this.initialSectionIndex = -1,
  });
  @override
  State<HatcherOptimizingScreen> createState() =>
      _HatcherOptimizingScreenState();
}

class _HatcherOptimizingScreenState extends State<HatcherOptimizingScreen> {
  static const List<String> _gridRows = ['Door', 'Middle', 'Back'];
  static const List<String> _gridColumns = ['Top', 'Middle', 'Bottom'];
  static const String _gridNavigationGroup = 'hatcher-cvt-grid';

  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    6,
    (_) => GlobalKey(),
  );
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _photos = {};
  final TextEditingController _avgController = TextEditingController();
  final TextEditingController _cvController = TextEditingController();
  final TextEditingController _incubationAgeController = TextEditingController(
    text: '18',
  );
  final TextEditingController _co2Controller = TextEditingController();
  late final TextEditingController _hatcherIdController;
  bool _chickPanting = false;
  String? _meconium;
  final TextEditingController _transferDayController = TextEditingController();
  String? _activeAuditId;

  @override
  void initState() {
    super.initState();
    _hatcherIdController = TextEditingController(
      text:
          widget.initialAudit?.hatcherId ??
          widget.initialAudit?.hoHatcherId ??
          widget.context.hatcherId ??
          '',
    );
    _incubationAgeController.text = (widget.initialAudit?.hoIncubationAge ?? 18)
        .toString();
    _chickPanting = widget.initialAudit?.hoChickPanting ?? false;
    _meconium = widget.initialAudit?.hoMeconium;
    _transferDayController.text =
        widget.initialAudit?.hoTransferDay?.toString() ?? '';
    _co2Controller.text = widget.initialAudit?.hoCo2?.toString() ?? '';
    for (var r in _gridRows) {
      for (var c in _gridColumns) {
        _controllers['${r}_$c'] = TextEditingController();
      }
    }
    _loadCvtReadings(widget.initialAudit?.hoCvtReadings);
    _loadCvtPhotos(widget.initialAudit?.hoCvtPhotos);
    if (widget.initialAudit?.hoCvtAvg != null) {
      _avgController.text = widget.initialAudit!.hoCvtAvg!.toStringAsFixed(1);
    }
    if (widget.initialAudit?.hoCvtCv != null) {
      _cvController.text = widget.initialAudit!.hoCvtCv!.toStringAsFixed(1);
    }
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
    _hatcherIdController.text = audit.hatcherId ?? audit.hoHatcherId ?? '';
    _incubationAgeController.text = (audit.hoIncubationAge ?? 18).toString();
    _chickPanting = audit.hoChickPanting ?? false;
    _meconium = audit.hoMeconium;
    _transferDayController.text = audit.hoTransferDay?.toString() ?? '';
    _co2Controller.text = audit.hoCo2?.toString() ?? '';
    for (final controller in _controllers.values) {
      controller.clear();
    }
    _photos.clear();
    _avgController.text = audit.hoCvtAvg != null
        ? audit.hoCvtAvg!.toStringAsFixed(1)
        : '';
    _cvController.text = audit.hoCvtCv != null
        ? audit.hoCvtCv!.toStringAsFixed(1)
        : '';
    _loadCvtReadings(audit.hoCvtReadings);
    _loadCvtPhotos(audit.hoCvtPhotos);
  }

  void _loadCvtReadings(String? readingsJson) {
    if (readingsJson == null || readingsJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(readingsJson);
      if (decoded is! Map) return;
      for (var entry in decoded.entries) {
        if (_controllers.containsKey(entry.key)) {
          final val = entry.value;
          if (val is num) {
            _controllers[entry.key]!.text = val.toStringAsFixed(1);
          }
        }
      }
    } catch (_) {}
  }

  void _loadCvtPhotos(String? photosJson) {
    if (photosJson == null || photosJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(photosJson);
      if (decoded is! Map) return;
      for (var entry in decoded.entries) {
        if (entry.value is String) {
          _photos[entry.key] = entry.value as String;
        }
      }
    } catch (_) {}
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
    _co2Controller.dispose();
    _hatcherIdController.dispose();
    _transferDayController.dispose();
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
    auditProvider.updateField('hoCvtReadings', jsonEncode(readings));
    auditProvider.updateField('hoCvtPhotos', jsonEncode(_photos));
    auditProvider.updateField('hoCvtAvg', avg);
    auditProvider.updateField('hoCvtCv', cv);
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
                title: 'Hatchers',
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
                  key: const ValueKey('hatcher-workbench-shell'),
                  children: [
                    _buildHatcherHeader(audit),
                    const SizedBox(height: 16),
                    StationSampleModeControls(
                      provider: auditProvider,
                      padding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 16),
                    _buildHatcherWorkbench(audit, auditProvider),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHatcherHeader(AuditModel audit) {
    final hatcherId = _hatcherIdController.text.trim();
    final age = _incubationAgeController.text.trim();
    return AuditStationHero(
      heroKey: const ValueKey('hatcher-station-header'),
      icon: Icons.device_thermostat,
      eyebrow: 'HATCHER WORKBENCH',
      title: 'Hatchers',
      subtitle: 'Hatcher climate, chick observations, and CVT profile.',
      details: [
        AuditHeroDetail(
          label: 'Breed',
          value: audit.hoBreed ?? widget.context.breed ?? 'Unknown',
        ),
        AuditHeroDetail(
          label: 'Hatcher',
          value: hatcherId.isEmpty ? 'Not set' : hatcherId,
        ),
        AuditHeroDetail(
          label: 'Age',
          value: age.isEmpty ? '18 days' : '$age days',
        ),
        const AuditHeroDetail(label: 'CVT target', value: '103-105°F'),
      ],
    );
  }

  Widget _buildHatcherWorkbench(AuditModel audit, AuditProvider auditProvider) {
    return AuditPanelColumns(
      left: [
        KeyedSubtree(
          key: _sectionKeys[0],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('hatcher-panel-setup'),
            mark: 'ID',
            icon: Icons.badge_outlined,
            title: 'Flock and hatcher',
            meta: 'Confirm the flock context and active hatcher.',
            statusLabel: _hatcherIdController.text.trim().isEmpty
                ? 'Needs ID'
                : 'Ready',
            statusColor: _hatcherIdController.text.trim().isEmpty
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildHatcherSetupPanel(audit, auditProvider),
          ),
        ),
        KeyedSubtree(
          key: _sectionKeys[1],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('hatcher-panel-environment'),
            mark: 'CO2',
            icon: Icons.co2_outlined,
            title: 'Environment check',
            meta: 'Record hatcher CO2 and attach supporting evidence.',
            statusLabel: _co2Controller.text.trim().isEmpty
                ? 'CO2 pending'
                : '${_co2Controller.text.trim()} ppm',
            statusColor: _co2Controller.text.trim().isEmpty
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildHatcherEnvironmentPanel(audit, auditProvider),
          ),
        ),
        KeyedSubtree(
          key: _sectionKeys[5],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('hatcher-panel-transfer'),
            mark: 'TR',
            icon: Icons.event_outlined,
            title: 'Transfer timing',
            meta: 'Record transfer day when available.',
            statusLabel: _transferDayController.text.trim().isEmpty
                ? 'Pending'
                : 'Day ${_transferDayController.text.trim()}',
            statusColor: _transferDayController.text.trim().isEmpty
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildTransferPanel(auditProvider),
          ),
        ),
      ],
      right: [
        KeyedSubtree(
          key: _sectionKeys[2],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('hatcher-panel-cvt'),
            mark: 'CVT',
            icon: Icons.grid_on,
            title: 'Chick Vent Temperature',
            meta: 'Nine-point CVT profile with photo evidence.',
            statusLabel: _avgController.text.trim().isEmpty
                ? 'Readings pending'
                : 'Avg ${_avgController.text.trim()}°F',
            statusColor: _avgController.text.trim().isEmpty
                ? AppColors.statusWarning
                : AppColors.statusGood,
            child: _buildHatcherCvtPanel(auditProvider),
          ),
        ),
        KeyedSubtree(
          key: _sectionKeys[3],
          child: AuditWorkbenchPanel(
            panelKey: const ValueKey('hatcher-panel-observations'),
            mark: 'OBS',
            icon: Icons.visibility_outlined,
            title: 'Chick observations',
            meta: 'Panting and meconium assessment.',
            statusLabel: _chickPanting || _meconium != null
                ? 'Observed'
                : 'Not set',
            statusColor: _chickPanting || _meconium != null
                ? AppColors.statusGood
                : AppColors.statusWarning,
            child: _buildObservationPanel(audit, auditProvider),
          ),
        ),
      ],
    );
  }

  Widget _buildHatcherSetupPanel(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
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
          child: Text(audit.hoBreed ?? widget.context.breed ?? 'Unknown'),
        ),
        const SizedBox(height: 12),
        TextField(
          controller: _hatcherIdController,
          enabled: !auditProvider.isReadOnly,
          decoration: InputDecoration(
            labelText: 'Hatcher ID',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) {
            setState(() {});
            auditProvider.updateField('hatcherId', v);
            auditProvider.updateField('hoHatcherId', v);
          },
        ),
        const SizedBox(height: 16),
        _buildAgeSlider(
          label: 'Incubation age',
          min: 18,
          max: 21,
          divisions: 3,
          value: double.tryParse(_incubationAgeController.text) ?? 18,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            final age = v.toInt();
            setState(() => _incubationAgeController.text = age.toString());
            auditProvider.updateField('hoIncubationAge', age);
          },
        ),
      ],
    );
  }

  Widget _buildHatcherEnvironmentPanel(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TextField(
          controller: _co2Controller,
          enabled: !auditProvider.isReadOnly,
          decoration: InputDecoration(
            labelText: 'CO2 Level',
            suffixText: 'ppm',
            isDense: true,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (v) {
            setState(() {});
            auditProvider.updateField('hoCo2', double.tryParse(v));
          },
        ),
        const SizedBox(height: 10),
        Align(
          alignment: Alignment.centerLeft,
          child: PhotoButton(
            photoPath: audit.hoCo2Photo,
            enabled: !auditProvider.isReadOnly,
            onPhotoCaptured: (p) => auditProvider.updateField('hoCo2Photo', p),
          ),
        ),
      ],
    );
  }

  Widget _buildHatcherCvtPanel(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Optimum range: 103-105°F',
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
        _buildCvtGrid(auditProvider),
      ],
    );
  }

  Widget _buildObservationPanel(AuditModel audit, AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Chick panting',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(
              child: SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(value: false, label: Text('No')),
                  ButtonSegment(value: true, label: Text('Yes')),
                ],
                selected: {_chickPanting},
                onSelectionChanged: auditProvider.isReadOnly
                    ? null
                    : (s) {
                        setState(() => _chickPanting = s.first);
                        auditProvider.updateField(
                          'hoChickPanting',
                          s.first ? 1 : 0,
                        );
                      },
              ),
            ),
            const SizedBox(width: 10),
            PhotoButton(
              photoPath: audit.hoChickPantingPhoto,
              enabled: !auditProvider.isReadOnly,
              onPhotoCaptured: (p) =>
                  auditProvider.updateField('hoChickPantingPhoto', p),
            ),
          ],
        ),
        const SizedBox(height: 16),
        Text(
          'Meconium assessment',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: ['Normal', 'Greenish', 'Watery', 'Excessive'].map((option) {
            final selected = _meconium == option;
            return ChoiceChip(
              label: Text(option),
              selected: selected,
              onSelected: auditProvider.isReadOnly
                  ? null
                  : (_) {
                      setState(() => _meconium = option);
                      auditProvider.updateField('ho_meconium', option);
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
      ],
    );
  }

  Widget _buildTransferPanel(AuditProvider auditProvider) {
    return AuditNumericField(
      controller: _transferDayController,
      enabled: !auditProvider.isReadOnly,
      decoration: InputDecoration(
        labelText: 'Transfer Day',
        suffixText: 'days',
        isDense: true,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: (v) {
        setState(() {});
        auditProvider.updateField('ho_transferDay', int.tryParse(v));
      },
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

  Widget _buildCvtGrid(AuditProvider provider) {
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
    final isGood = value != null && value >= 103 && value <= 105;
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
              provider.updateField('hoCvtPhotos', jsonEncode(_photos));
            },
          ),
        ],
      ),
    );
  }
}
