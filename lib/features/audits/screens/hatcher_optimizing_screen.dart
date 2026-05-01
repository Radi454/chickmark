import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/models/audit_model.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/photo_button.dart';
import '../widgets/sample_mode_controls.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class HatcherOptimizingScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final int initialSectionIndex;

  const HatcherOptimizingScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialSectionIndex = 0,
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
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Hatcher Optimizing',
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
            child: SingleChildScrollView(
              controller: _scrollController,
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  StationSampleModeControls(
                    provider: auditProvider,
                    padding: EdgeInsets.zero,
                  ),
                  const SizedBox(height: 16),
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
                              audit.hoBreed ??
                                  widget.context.breed ??
                                  'Unknown',
                            ),
                          ),
                          const SizedBox(height: 12),
                          TextField(
                            controller: _hatcherIdController,
                            enabled: !auditProvider.isReadOnly,
                            decoration: const InputDecoration(
                              labelText: 'Hatcher ID',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) {
                              auditProvider.updateField('hatcherId', v);
                              auditProvider.updateField('hoHatcherId', v);
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
                                double.tryParse(
                                  _incubationAgeController.text,
                                ) ??
                                18,
                            min: 18,
                            max: 21,
                            divisions: 3,
                            onChanged: auditProvider.isReadOnly
                                ? null
                                : (v) {
                                    final age = v.toInt();
                                    setState(() {
                                      _incubationAgeController.text = age
                                          .toString();
                                    });
                                    auditProvider.updateField(
                                      'hoIncubationAge',
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
                        children: [
                          TextField(
                            enabled: !auditProvider.isReadOnly,
                            decoration: const InputDecoration(
                              labelText: 'CO2 Level (ppm)',
                              border: OutlineInputBorder(),
                            ),
                            onChanged: (v) => auditProvider.updateField(
                              'hoCo2',
                              double.tryParse(v),
                            ),
                          ),
                          const SizedBox(height: 8),
                          PhotoButton(
                            photoPath: audit.hoCo2Photo,
                            enabled: !auditProvider.isReadOnly,
                            onPhotoCaptured: (p) =>
                                auditProvider.updateField('hoCo2Photo', p),
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
                      Expanded(
                        child: _statCard('CV%', _cvController.text, null),
                      ),
                    ],
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
                          Text(
                            'Chick Vent Temperature (CVT) - Optimum: 103-105°F',
                            style: AppTextStyles.body,
                          ),
                          _buildCvtGrid(auditProvider),
                        ],
                      ),
                    ),
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
                          Text('Chick Panting', style: AppTextStyles.body),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: SegmentedButton<bool>(
                                  segments: const [
                                    ButtonSegment(
                                      value: false,
                                      label: Text('No'),
                                    ),
                                    ButtonSegment(
                                      value: true,
                                      label: Text('Yes'),
                                    ),
                                  ],
                                  selected: {_chickPanting},
                                  onSelectionChanged: auditProvider.isReadOnly
                                      ? null
                                      : (s) {
                                          setState(
                                            () => _chickPanting = s.first,
                                          );
                                          auditProvider.updateField(
                                            'hoChickPanting',
                                            s.first ? 1 : 0,
                                          );
                                        },
                                ),
                              ),
                              const SizedBox(width: 8),
                              PhotoButton(
                                photoPath: audit.hoChickPantingPhoto,
                                enabled: !auditProvider.isReadOnly,
                                onPhotoCaptured: (p) => auditProvider
                                    .updateField('hoChickPantingPhoto', p),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    key: _sectionKeys[4],
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
                            'Meconium Assessment',
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                [
                                  'Normal',
                                  'Greenish',
                                  'Watery',
                                  'Excessive',
                                ].map((option) {
                                  final selected = _meconium == option;
                                  return ChoiceChip(
                                    label: Text(option),
                                    selected: selected,
                                    onSelected: auditProvider.isReadOnly
                                        ? null
                                        : (_) {
                                            setState(() => _meconium = option);
                                            auditProvider.updateField(
                                              'ho_meconium',
                                              option,
                                            );
                                          },
                                    selectedColor: AppColors.primary.withAlpha(
                                      30,
                                    ),
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
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Card(
                    key: _sectionKeys[5],
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
                            'Transfer Day',
                            style: AppTextStyles.body.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          const SizedBox(height: 12),
                          AuditNumericField(
                            controller: _transferDayController,
                            enabled: !auditProvider.isReadOnly,
                            decoration: const InputDecoration(
                              labelText: 'Transfer Day (day of incubation)',
                              border: OutlineInputBorder(),
                              suffixText: 'days',
                            ),
                            onChanged: (v) => auditProvider.updateField(
                              'ho_transferDay',
                              int.tryParse(v),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
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
