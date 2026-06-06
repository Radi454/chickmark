import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../services/ocr/ocr_service.dart';
import '../../../services/photo/photo_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../models/est_grid_data.dart';
import '../ocr_capture/ocr_capture_config.dart';
import '../ocr_capture/ocr_capture_launcher.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_autosave_status.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/est_grid_widget.dart';
import '../widgets/photo_button.dart';
import '../widgets/unsaved_changes_guard.dart';
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

enum _EstScanAction { confirm, retake, skip }

class _SetterOptimizingScreenState extends State<SetterOptimizingScreen> {
  static const TextStyle _prominentFloatingLabelStyle = TextStyle(
    color: AppColors.primary,
    fontSize: 14,
    fontWeight: FontWeight.w700,
    height: 1.2,
  );
  static const List<String> _setterBreeds = [
    'Ross308',
    'Arbo',
    'Avian',
    'Cobb500',
    'Hubbard',
    'IR',
  ];

  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    5,
    (_) => GlobalKey(),
  );

  final Map<String, TextEditingController> _estControllers = {};
  final Map<String, FocusNode> _estFocusNodes = {};
  final Map<String, String?> _estPhotos = {};
  final OcrService _ocrService = OcrService();
  final PhotoService _photoService = PhotoService();
  final PhotoRepository _photoRepository = PhotoRepository();

  final TextEditingController _estAvgController = TextEditingController();
  final TextEditingController _estCvController = TextEditingController();
  final TextEditingController _incubationAgeController = TextEditingController(
    text: '1',
  );
  final TextEditingController _incubationHoursController =
      TextEditingController(text: '0');
  late final TextEditingController _setterIdController;
  final TextEditingController _setpointController = TextEditingController();
  final TextEditingController _setpointRhController = TextEditingController();
  final TextEditingController _batchSizeController = TextEditingController();
  final TextEditingController _batchCountController = TextEditingController();
  final TextEditingController _turningAngleController = TextEditingController();
  final TextEditingController _co2Controller = TextEditingController();

  String _machineType = 'Multi';
  int _activeEstSampleIndex = 0;
  String _activeEstBreed = 'Ross308';
  String? _activeAuditId;

  @override
  void initState() {
    super.initState();
    for (final level in EstGridData.levels) {
      for (final location in EstGridData.locations) {
        final key = EstGridData.key(location, level);
        _estControllers[key] = TextEditingController();
        _estFocusNodes[key] = FocusNode();
      }
    }
    _setterIdController = TextEditingController();

    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    auditProvider.initialize(
      AuditContext(
        auditType: widget.context.auditType,
        customerId: widget.context.customerId,
        flockId: widget.context.flockId,
        hatcheryId: widget.context.hatcheryId,
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
    _initializeFormState(auditProvider.activeDraft);
    _activeAuditId = auditProvider.activeDraft.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialSection();
    });
  }

  void _initializeFormState(AuditModel audit) {
    _setterIdController.text = _setterNumberValue(audit);
    _machineType = _normalizeSetterType(audit.soMachineType);
    _setpointController.text = audit.soSetpointF != null
        ? audit.soSetpointF!.toStringAsFixed(1)
        : '';
    _setpointRhController.text = audit.soSetpointRh != null
        ? audit.soSetpointRh!.toStringAsFixed(1)
        : '';
    _batchSizeController.text = (audit.soBatchSize ?? 19200).toString();
    _batchCountController.text = (audit.soBatchCount ?? 1).toString();
    _turningAngleController.text = audit.soTurningAngle != null
        ? audit.soTurningAngle!.toStringAsFixed(1)
        : '';
    _co2Controller.text = audit.soCo2 != null
        ? audit.soCo2!.toStringAsFixed(1)
        : '';
    final estSamples = _setterEstSamples(audit);
    if (_activeEstSampleIndex >= estSamples.length) {
      _activeEstSampleIndex = estSamples.length - 1;
    }
    if (_activeEstSampleIndex < 0) _activeEstSampleIndex = 0;
    final activeEstSample = estSamples[_activeEstSampleIndex];
    _activeEstBreed = _normalizeBreed(activeEstSample['breed']);
    _incubationAgeController.text =
        ((activeEstSample['incubationAge'] as num?)?.toInt() ??
                audit.soIncubationAge ??
                1)
            .toString();
    _incubationHoursController.text =
        ((activeEstSample['incubationHours'] as num?)?.toInt() ??
                audit.soIncubationHours ??
                0)
            .toString();
    for (final controller in _estControllers.values) {
      controller.clear();
    }
    _estPhotos.clear();
    final sampleAvg = (activeEstSample['estAvg'] as num?)?.toDouble();
    final sampleCv = (activeEstSample['estCv'] as num?)?.toDouble();
    _estAvgController.text = sampleAvg != null
        ? sampleAvg.toStringAsFixed(1)
        : '';
    _estCvController.text = sampleCv != null ? sampleCv.toStringAsFixed(1) : '';
    _loadEstReadings(_encodedStringMap(activeEstSample['estReadings']));
    _loadEstPhotos(_encodedStringMap(activeEstSample['estPhotos']));
  }

  void _syncActiveSampleForm(AuditProvider provider, AuditModel audit) {
    if (_activeAuditId == audit.id) return;
    _activeAuditId = audit.id;
    _activeEstSampleIndex = 0;
    _initializeFormState(audit);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || provider.activeDraft.id != _activeAuditId) return;
      _syncSelectedEstSampleToFlatFields(provider);
    });
  }

  String _normalizeSetterType(String? value) {
    final normalized = value?.trim().toLowerCase();
    if (normalized == 'single' || normalized == 'single stage') {
      return 'Single';
    }
    return 'Multi';
  }

  String _normalizeBreed(Object? value) {
    final text = value?.toString().trim();
    if (text != null && _setterBreeds.contains(text)) return text;
    return 'Ross308';
  }

  String? _encodedStringMap(Object? value) {
    if (value == null) return null;
    if (value is Map && value.isNotEmpty) return jsonEncode(value);
    return null;
  }

  List<Map<String, dynamic>> _setterEstSamples(AuditModel audit) {
    final samples = <Map<String, dynamic>>[];
    final raw = audit.soEstSamplesJson;
    if (raw != null && raw.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(raw);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is Map) {
              samples.add(_normalizeEstSample(Map<String, dynamic>.from(item)));
            }
          }
        }
      } catch (_) {
        // Fall back to the legacy flat EST fields below.
      }
    }
    if (samples.isNotEmpty) return samples;
    return [
      _normalizeEstSample({
        'id': audit.id,
        'breed': audit.soBreed,
        'incubationAge': audit.soIncubationAge ?? 1,
        'incubationHours': audit.soIncubationHours ?? 0,
        'estReadings': _decodeMap(audit.soEstReadings),
        'estPhotos': _decodeMap(audit.soEstPhotos),
        'estAvg': audit.soEstAvg,
        'estCv': audit.soEstCv,
      }),
    ];
  }

  Map<String, dynamic> _normalizeEstSample(Map<String, dynamic> sample) {
    final sampleId = sample['id']?.toString().trim();
    return {
      'id': sampleId != null && sampleId.isNotEmpty
          ? sampleId
          : DateTime.now().microsecondsSinceEpoch.toString(),
      'breed': _normalizeBreed(sample['breed']),
      'incubationAge': _clampInt(sample['incubationAge'], min: 1, max: 18),
      'incubationHours': _clampInt(sample['incubationHours'], min: 0, max: 23),
      'estReadings': _mapFromObject(sample['estReadings']),
      'estPhotos': _mapFromObject(sample['estPhotos']),
      'estAvg': (sample['estAvg'] as num?)?.toDouble(),
      'estCv': (sample['estCv'] as num?)?.toDouble(),
    };
  }

  Map<String, dynamic> _decodeMap(String? raw) {
    if (raw == null || raw.trim().isEmpty) return {};
    try {
      final decoded = jsonDecode(raw);
      return _mapFromObject(decoded);
    } catch (_) {
      return {};
    }
  }

  Map<String, dynamic> _mapFromObject(Object? value) {
    if (value is! Map) return {};
    return {
      for (final entry in value.entries)
        if (entry.key != null) entry.key.toString(): entry.value,
    };
  }

  int _clampInt(Object? value, {required int min, required int max}) {
    final parsed = value is num ? value.toInt() : int.tryParse('$value');
    return (parsed ?? min).clamp(min, max).toInt();
  }

  void _loadEstReadings(String? readingsJson) {
    if (readingsJson == null || readingsJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(readingsJson);
      if (decoded is! Map) return;
      final readings = EstGridData.normalizeReadings(decoded);
      for (final entry in readings.entries) {
        _estControllers[entry.key]?.text = entry.value.toStringAsFixed(1);
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
      for (final entry in decoded.entries) {
        final key = _canonicalEstKey(entry.key?.toString());
        if (key == null || entry.value is! String) continue;
        _estPhotos[key] = entry.value as String;
      }
    } catch (_) {
      // Keep photos empty if stored data is malformed.
    }
  }

  String? _canonicalEstKey(String? rawKey) {
    if (rawKey == null) return null;
    final normalized = EstGridData.normalizeReadings({rawKey: 0});
    return normalized.keys.isEmpty ? null : normalized.keys.first;
  }

  @override
  void dispose() {
    _scrollController.dispose();
    for (final controller in _estControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _estFocusNodes.values) {
      focusNode.dispose();
    }
    _estAvgController.dispose();
    _estCvController.dispose();
    _incubationAgeController.dispose();
    _incubationHoursController.dispose();
    _setterIdController.dispose();
    _setpointController.dispose();
    _setpointRhController.dispose();
    _batchSizeController.dispose();
    _batchCountController.dispose();
    _turningAngleController.dispose();
    _co2Controller.dispose();
    unawaited(_ocrService.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();
    final audit = auditProvider.activeDraft;
    _syncActiveSampleForm(auditProvider, audit);
    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Setters',
                actions: [
                  const AuditAutosaveStatus(onDark: true),
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
                  _buildSetterTabs(auditProvider),
                  const SizedBox(height: 16),
                  _buildIdentityCard(auditProvider, audit),
                  const SizedBox(height: 16),
                  _buildMachineCard(auditProvider, audit),
                  const SizedBox(height: 16),
                  _buildCo2Card(auditProvider, audit),
                  const SizedBox(height: 16),
                  _buildEstSampleCard(auditProvider, audit),
                  const SizedBox(height: 16),
                  Card(
                    key: _sectionKeys[3],
                    elevation: 2,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(AppSizes.cardRadius),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(AppSizes.cardPadding),
                      child: _buildEstGridSection(auditProvider),
                    ),
                  ),
                  const SizedBox(height: AppSizes.fabBottomPadding),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSetterTabs(AuditProvider provider) {
    return _buildSetterSampleControlCard(
      key: const ValueKey('setter-machine-scope-card'),
      title: 'Machine scope',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildSetterMachineScopeChips(provider),
          const SizedBox(height: 12),
          _buildSetterNumberField(provider),
        ],
      ),
    );
  }

  Widget _buildSetterSampleControlCard({
    Key? key,
    required String title,
    required Widget child,
  }) {
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildSetterMachineScopeChips(AuditProvider provider) {
    final chips = [
      for (final entry in provider.drafts.asMap().entries)
        _buildSetterScopeChip(
          label: _setterTabLabel(entry.value, entry.key),
          selected: provider.activeSampleIndex == entry.key,
          enabled: !provider.isReadOnly,
          onSelected: () => _switchSetterSample(provider, entry.key),
        ),
    ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildSetterSampleActionButton(
          tooltip: 'Add machine sample',
          icon: Icons.add,
          onPressed: provider.isReadOnly
              ? null
              : () => _addSetterMachineSample(provider),
        ),
        if (provider.sampleCount > 1) ...[
          const SizedBox(width: 8),
          _buildSetterSampleActionButton(
            tooltip: 'Remove active machine sample',
            icon: Icons.remove,
            onPressed: provider.isReadOnly
                ? null
                : () => _removeActiveSetterSample(provider),
          ),
        ],
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 520) {
          return Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [...chips, actions],
          );
        }

        return Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: chips,
              ),
            ),
            const SizedBox(width: 8),
            actions,
          ],
        );
      },
    );
  }

  Widget _buildSetterScopeChip({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onSelected() : null,
      selectedColor: AppColors.primary.withAlpha(30),
      checkmarkColor: AppColors.primary,
      labelStyle: AppTextStyles.body.copyWith(
        color: selected ? AppColors.primary : AppColors.textBody,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.borderDefault,
        ),
      ),
    );
  }

  Widget _buildSetterSampleActionButton({
    Key? key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    final enabled = onPressed != null;
    final fillColor = enabled
        ? AppColors.primary.withAlpha(18)
        : AppColors.borderDefault.withAlpha(90);
    final iconColor = enabled ? AppColors.primary : AppColors.textDisabled;
    return Tooltip(
      key: key,
      message: tooltip,
      child: Semantics(
        button: true,
        enabled: enabled,
        label: tooltip,
        child: Material(
          color: Colors.transparent,
          child: InkResponse(
            onTap: onPressed,
            radius: 24,
            containedInkWell: false,
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: fillColor,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 20, color: iconColor),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _addSetterMachineSample(AuditProvider provider) {
    provider.addSample();
    if (!mounted) return;
    setState(() {
      _syncActiveSampleForm(provider, provider.activeDraft);
    });
  }

  void _switchSetterSample(AuditProvider provider, int index) {
    provider.switchSample(index);
    if (!mounted) return;
    setState(() {
      _syncActiveSampleForm(provider, provider.activeDraft);
    });
  }

  void _removeActiveSetterSample(AuditProvider provider) {
    provider.removeActiveSample();
    if (!mounted) return;
    setState(() {
      _syncActiveSampleForm(provider, provider.activeDraft);
    });
  }

  Widget _buildSetterNumberField(AuditProvider auditProvider) {
    return TextField(
      key: const ValueKey('setter-machine-scope-number-field'),
      controller: _setterIdController,
      enabled: !auditProvider.isReadOnly,
      decoration: const InputDecoration(
        labelText: 'Setter number',
        border: OutlineInputBorder(),
      ),
      onChanged: (value) {
        auditProvider.updateField('setterId', value);
        auditProvider.updateField('soSetterId', value);
        if (mounted) setState(() {});
      },
    );
  }

  Widget _buildIdentityCard(AuditProvider auditProvider, AuditModel audit) {
    final totalEggs = audit.soTotalEggsSet ?? _currentTotalEggsSet();
    return Card(
      key: _sectionKeys[0],
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
              'Setter type',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['Multi', 'Single'].map((type) {
                final selected = _machineType == type;
                return ChoiceChip(
                  key: ValueKey('setter-type-${type.toLowerCase()}'),
                  label: Text(type),
                  selected: selected,
                  showCheckmark: false,
                  onSelected: auditProvider.isReadOnly
                      ? null
                      : (_) => _updateSetterType(auditProvider, type),
                  selectedColor: AppColors.primary.withAlpha(30),
                  checkmarkColor: AppColors.primary,
                  labelStyle: AppTextStyles.body.copyWith(
                    color: selected ? AppColors.primary : AppColors.textBody,
                    fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: selected
                          ? AppColors.primary
                          : AppColors.borderDefault,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            Column(
              children: [
                AuditNumericField(
                  controller: _setpointController,
                  enabled: !auditProvider.isReadOnly,
                  allowDecimal: true,
                  maxDecimalPlaces: 1,
                  decoration: const InputDecoration(
                    labelText: 'Setpoint (°F)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => auditProvider.updateField(
                    'so_setpointF',
                    double.tryParse(value),
                  ),
                ),
                const SizedBox(height: 8),
                AuditNumericField(
                  key: const ValueKey('setter-setpoint-rh-field'),
                  controller: _setpointRhController,
                  enabled: !auditProvider.isReadOnly,
                  allowDecimal: true,
                  maxDecimalPlaces: 1,
                  decoration: const InputDecoration(
                    labelText: 'Setpoint RH (%)',
                    border: OutlineInputBorder(),
                  ),
                  onChanged: (value) => auditProvider.updateField(
                    'so_setpointRh',
                    double.tryParse(value),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AuditNumericField(
                    controller: _batchSizeController,
                    enabled: !auditProvider.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: 'Batch size',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _updateBatchTotals(auditProvider),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AuditNumericField(
                    key: const ValueKey('setter-batch-count-field'),
                    controller: _batchCountController,
                    enabled: !auditProvider.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: 'Batches (max 6)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (_) => _updateBatchTotals(auditProvider),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'Total set eggs: $totalEggs',
              style: AppTextStyles.body.copyWith(
                color: AppColors.primary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _updateSetterType(AuditProvider provider, String type) {
    final normalized = _normalizeSetterType(type);
    setState(() {
      _machineType = normalized;
      if (normalized == 'Single') _activeEstSampleIndex = 0;
    });
    provider.updateField('so_machineType', normalized);
    if (normalized == 'Single') {
      final samples = [_activeEstSampleFromForm(provider.activeDraft)];
      _writeSetterEstSamples(provider, samples);
    }
  }

  int _currentTotalEggsSet() {
    final batchSize = int.tryParse(_batchSizeController.text) ?? 19200;
    final batchCount = (int.tryParse(_batchCountController.text) ?? 1)
        .clamp(1, 6)
        .toInt();
    return batchSize * batchCount;
  }

  void _updateBatchTotals(AuditProvider provider) {
    final batchSize = int.tryParse(_batchSizeController.text) ?? 19200;
    final batchCount = (int.tryParse(_batchCountController.text) ?? 1)
        .clamp(1, 6)
        .toInt();
    if (_batchCountController.text != batchCount.toString()) {
      _batchCountController.text = batchCount.toString();
    }
    final total = batchSize * batchCount;
    provider.updateField('so_batchSize', batchSize);
    provider.updateField('so_batchCount', batchCount);
    provider.updateField('so_totalEggsSet', total);
    if (mounted) setState(() {});
  }

  void _updateIncubationAge(AuditProvider provider, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      if (mounted) setState(() {});
      return;
    }
    final age = parsed.clamp(1, 18).toInt();
    _replaceControllerTextIfNeeded(_incubationAgeController, age.toString());
    provider.updateField('soIncubationAge', age);
    _syncActiveEstSampleToDraft(provider);
    if (mounted) setState(() {});
  }

  void _updateIncubationHours(AuditProvider provider, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      if (mounted) setState(() {});
      return;
    }
    final hours = parsed.clamp(0, 23).toInt();
    _replaceControllerTextIfNeeded(
      _incubationHoursController,
      hours.toString(),
    );
    provider.updateField('soIncubationHours', hours);
    _syncActiveEstSampleToDraft(provider);
    if (mounted) setState(() {});
  }

  void _replaceControllerTextIfNeeded(
    TextEditingController controller,
    String value,
  ) {
    if (controller.text == value) return;
    controller.value = TextEditingValue(
      text: value,
      selection: TextSelection.collapsed(offset: value.length),
    );
  }

  void _addEstSample(AuditProvider provider) {
    _syncActiveEstSampleToDraft(provider);
    final samples = _setterEstSamples(provider.activeDraft);
    final base = samples[_activeEstSampleIndex.clamp(0, samples.length - 1)];
    samples.add(
      _normalizeEstSample({
        'id': DateTime.now().microsecondsSinceEpoch.toString(),
        'breed': base['breed'],
        'incubationAge': base['incubationAge'],
        'incubationHours': base['incubationHours'],
        'estReadings': <String, double>{},
        'estPhotos': <String, String>{},
        'estAvg': null,
        'estCv': null,
      }),
    );
    _writeSetterEstSamples(provider, samples);
    setState(() {
      _activeEstSampleIndex = samples.length - 1;
      _initializeFormState(provider.activeDraft);
    });
    _syncSelectedEstSampleToFlatFields(provider);
  }

  void _removeActiveEstSample(AuditProvider provider) {
    final samples = _setterEstSamples(provider.activeDraft);
    if (samples.length <= 1) return;
    _syncActiveEstSampleToDraft(provider);
    final refreshedSamples = _setterEstSamples(provider.activeDraft);
    final index = _activeEstSampleIndex
        .clamp(0, refreshedSamples.length - 1)
        .toInt();
    refreshedSamples.removeAt(index);
    _writeSetterEstSamples(provider, refreshedSamples);
    setState(() {
      _activeEstSampleIndex = index
          .clamp(0, refreshedSamples.length - 1)
          .toInt();
      _initializeFormState(provider.activeDraft);
    });
    _syncSelectedEstSampleToFlatFields(provider);
  }

  void _switchEstSample(AuditProvider provider, int index) {
    _syncActiveEstSampleToDraft(provider);
    final samples = _setterEstSamples(provider.activeDraft);
    if (index < 0 || index >= samples.length) return;
    setState(() {
      _activeEstSampleIndex = index;
      _initializeFormState(provider.activeDraft);
    });
    _syncSelectedEstSampleToFlatFields(provider);
  }

  Map<String, dynamic> _activeEstSampleFromForm(AuditModel audit) {
    final samples = _setterEstSamples(audit);
    final index = _activeEstSampleIndex.clamp(0, samples.length - 1).toInt();
    final existing = Map<String, dynamic>.from(samples[index]);
    final avg = double.tryParse(_estAvgController.text);
    final cv = double.tryParse(_estCvController.text);
    return _normalizeEstSample({
      ...existing,
      'breed': _activeEstBreed,
      'incubationAge': int.tryParse(_incubationAgeController.text) ?? 1,
      'incubationHours': int.tryParse(_incubationHoursController.text) ?? 0,
      'estReadings': _currentEstReadings(),
      'estPhotos': _currentEstPhotoPaths(),
      'estAvg': avg,
      'estCv': cv,
    });
  }

  void _syncActiveEstSampleToDraft(AuditProvider provider) {
    final samples = _setterEstSamples(provider.activeDraft);
    final index = _activeEstSampleIndex.clamp(0, samples.length - 1).toInt();
    samples[index] = _activeEstSampleFromForm(provider.activeDraft);
    _writeSetterEstSamples(provider, samples);
  }

  void _syncSelectedEstSampleToFlatFields(AuditProvider provider) {
    final samples = _setterEstSamples(provider.activeDraft);
    final index = _activeEstSampleIndex.clamp(0, samples.length - 1).toInt();
    final sample = _normalizeEstSample(samples[index]);
    final age = _clampInt(sample['incubationAge'], min: 1, max: 18);
    final hours = _clampInt(sample['incubationHours'], min: 0, max: 23);
    final readingsJson = _encodedStringMap(sample['estReadings']);
    final photosJson = _encodedStringMap(sample['estPhotos']);
    final avg = (sample['estAvg'] as num?)?.toDouble();
    final cv = (sample['estCv'] as num?)?.toDouble();
    final breed = _normalizeBreed(sample['breed']);
    final draft = provider.activeDraft;

    if (draft.soBreed != breed) provider.updateField('soBreed', breed);
    if (draft.soIncubationAge != age) {
      provider.updateField('soIncubationAge', age);
    }
    if (draft.soIncubationHours != hours) {
      provider.updateField('soIncubationHours', hours);
    }
    if (draft.soEstReadings != readingsJson) {
      provider.updateField('soEstReadings', readingsJson);
    }
    if (draft.soEstPhotos != photosJson) {
      provider.updateField('soEstPhotos', photosJson);
    }
    if (draft.soEstAvg != avg) provider.updateField('soEstAvg', avg);
    if (draft.soEstCv != cv) provider.updateField('soEstCv', cv);
  }

  void _writeSetterEstSamples(
    AuditProvider provider,
    List<Map<String, dynamic>> samples,
  ) {
    provider.updateField('so_estSamplesJson', jsonEncode(samples));
  }

  String _incubationAgeScopeLabel(
    List<Map<String, dynamic>> samples,
    int index,
  ) {
    if (samples.length == 1) return 'Pool';
    final sample = samples[index];
    final age = _clampInt(sample['incubationAge'], min: 1, max: 18);
    final duplicateCount = samples.where((candidate) {
      return _clampInt(candidate['incubationAge'], min: 1, max: 18) == age;
    }).length;
    if (duplicateCount == 1) return 'Day $age';

    var occurrence = 0;
    for (var i = 0; i <= index; i++) {
      final candidateAge = _clampInt(
        samples[i]['incubationAge'],
        min: 1,
        max: 18,
      );
      if (candidateAge == age) occurrence++;
    }
    return 'Day $age · $occurrence';
  }

  Widget _buildEstSampleCard(AuditProvider auditProvider, AuditModel audit) {
    final samples = _setterEstSamples(audit);
    final canChangeSampleCount = _machineType == 'Multi';
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Incubation age samples',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                if (canChangeSampleCount)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildSetterSampleActionButton(
                        key: const ValueKey('setter-est-sample-add-button'),
                        tooltip: 'Add incubation age sample',
                        icon: Icons.add,
                        onPressed: auditProvider.isReadOnly
                            ? null
                            : () => _addEstSample(auditProvider),
                      ),
                      if (samples.length > 1) ...[
                        const SizedBox(width: 8),
                        _buildSetterSampleActionButton(
                          key: const ValueKey(
                            'setter-est-sample-remove-button',
                          ),
                          tooltip: 'Remove active incubation age sample',
                          icon: Icons.remove,
                          onPressed: auditProvider.isReadOnly
                              ? null
                              : () => _removeActiveEstSample(auditProvider),
                        ),
                      ],
                    ],
                  ),
              ],
            ),
            const SizedBox(height: 8),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  for (var i = 0; i < samples.length; i++) ...[
                    ChoiceChip(
                      label: Text(_incubationAgeScopeLabel(samples, i)),
                      selected: i == _activeEstSampleIndex,
                      showCheckmark: false,
                      selectedColor: AppColors.primary.withAlpha(30),
                      backgroundColor: AppColors.surface,
                      labelStyle: AppTextStyles.body.copyWith(
                        color: i == _activeEstSampleIndex
                            ? AppColors.primary
                            : AppColors.textBody,
                        fontWeight: i == _activeEstSampleIndex
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: i == _activeEstSampleIndex
                              ? AppColors.primary
                              : AppColors.borderDefault,
                        ),
                      ),
                      onSelected: auditProvider.isReadOnly
                          ? null
                          : (_) {
                              if (samples.length > 1) {
                                _switchEstSample(auditProvider, i);
                              }
                            },
                    ),
                    const SizedBox(width: 8),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AuditNumericField(
                    key: const ValueKey('setter-incubation-age-field'),
                    controller: _incubationAgeController,
                    enabled: !auditProvider.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: 'Incubation Age (days)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        _updateIncubationAge(auditProvider, value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AuditNumericField(
                    key: const ValueKey('setter-incubation-hours-field'),
                    controller: _incubationHoursController,
                    enabled: !auditProvider.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: 'Incubation Hours',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        _updateIncubationHours(auditProvider, value),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineCard(AuditProvider auditProvider, AuditModel audit) {
    return Card(
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AuditNumericField(
                    controller: _turningAngleController,
                    enabled: !auditProvider.isReadOnly,
                    allowDecimal: true,
                    maxDecimalPlaces: 1,
                    decoration: _prominentFloatingLabelDecoration(
                      'Turning Angle (°)',
                    ),
                    onChanged: (value) => auditProvider.updateField(
                      'so_turningAngle',
                      double.tryParse(value),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                PhotoButton(
                  key: const ValueKey('setter-turning-angle-photo-button'),
                  photoPath: audit.soMachineScreenPhoto,
                  enabled: !auditProvider.isReadOnly,
                  fieldKey: 'turning_angle',
                  onPhotoCaptured: (path) =>
                      auditProvider.updateField('so_machineScreenPhoto', path),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCo2Card(AuditProvider auditProvider, AuditModel audit) {
    return Card(
      key: _sectionKeys[2],
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: AuditNumericField(
                    controller: _co2Controller,
                    enabled: !auditProvider.isReadOnly,
                    allowDecimal: true,
                    decoration: _prominentFloatingLabelDecoration(
                      'CO2 Level (ppm)',
                    ),
                    onChanged: (value) => auditProvider.updateField(
                      'soCo2',
                      double.tryParse(value),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                PhotoButton(
                  key: const ValueKey('setter-co2-photo-button'),
                  photoPath: audit.soCo2Photo,
                  enabled: !auditProvider.isReadOnly,
                  onPhotoCaptured: (path) =>
                      auditProvider.updateField('soCo2Photo', path),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  InputDecoration _prominentFloatingLabelDecoration(String label) {
    return const InputDecoration(
      border: OutlineInputBorder(),
      floatingLabelBehavior: FloatingLabelBehavior.always,
      floatingLabelStyle: _prominentFloatingLabelStyle,
      labelStyle: _prominentFloatingLabelStyle,
    ).copyWith(labelText: label);
  }

  Widget _buildEstGridSection(AuditProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text(
                'Egg Shell Temperature',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton.icon(
              onPressed: provider.isReadOnly
                  ? null
                  : () => _openEstCapture(provider),
              icon: const Icon(Icons.document_scanner_outlined),
              label: const Text('Scan readings'),
            ),
          ],
        ),
        const SizedBox(height: 12),
        EstGridWidget(
          controllers: _estControllers,
          focusNodes: _estFocusNodes,
          photos: _estPhotos,
          enabled: !provider.isReadOnly,
          showPhotoCapture: false,
          title: null,
          unitSuffix: '°F',
          tempStatusFn: CalculationUtils.setterEstStatus,
          tempZoneFn: CalculationUtils.setterEstZone,
          onValueChanged: (key, value) => _updateEstCalculations(provider),
          onPhotoCaptured: (key, path) {
            unawaited(_handleEstPhotoCaptured(provider, key, path));
          },
          onMissingPhotoRequested: (key) {
            unawaited(_attachMissingEstPhoto(provider, key));
          },
          onClearRequested: (key) {
            unawaited(_clearEstPoint(provider, key));
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _summCard(
                'AVG',
                _estAvgController.text.isEmpty
                    ? '--'
                    : '${_estAvgController.text}°F',
                _estAverageColor(),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _summCard(
                'CV%',
                _estCvController.text.isEmpty
                    ? '--'
                    : '${_estCvController.text}%',
                Colors.blueGrey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _handleEstPhotoCaptured(
    AuditProvider provider,
    String key,
    String path,
  ) async {
    final existingValue = double.tryParse(_estControllers[key]?.text ?? '');
    final existingPhoto = _estPhotos[key];
    if (existingValue != null &&
        (existingPhoto == null || existingPhoto.trim().isEmpty)) {
      await _attachEstPhotoPathToExistingReading(provider, key, path);
      return;
    }

    await _confirmSingleEstReading(provider, key, path);
  }

  Future<void> _attachMissingEstPhoto(
    AuditProvider provider,
    String key,
  ) async {
    if (provider.isReadOnly) return;
    final existingValue = double.tryParse(_estControllers[key]?.text ?? '');
    final existingPhoto = _estPhotos[key];
    if (existingValue == null ||
        (existingPhoto != null && existingPhoto.trim().isNotEmpty)) {
      return;
    }

    final path = await _photoService.pickPhoto(fromCamera: true);
    if (!mounted || path == null || path.trim().isEmpty) return;

    await _attachEstPhotoPathToExistingReading(provider, key, path);
  }

  Future<void> _attachEstPhotoPathToExistingReading(
    AuditProvider provider,
    String key,
    String path,
  ) async {
    final existingValue = double.tryParse(_estControllers[key]?.text ?? '');
    if (existingValue == null || path.trim().isEmpty) return;

    setState(() {
      _estPhotos[key] = path;
    });
    _updateEstPhotos(provider);
    await _saveEstEvidencePhotoRecord(provider, key, path);
    await _persistActiveAuditRow(provider);
  }

  Future<bool> _persistActiveAuditRow(AuditProvider provider) async {
    try {
      return provider.saveSamplesWithResult(tabIndex: 0);
    } catch (_) {
      // Keep the active draft updated; normal tab save can persist if row is new.
      return false;
    }
  }

  Future<void> _clearEstPoint(AuditProvider provider, String key) async {
    if (provider.isReadOnly) return;
    final controller = _estControllers[key];
    if (controller == null) return;
    final previousValue = controller.text;
    final previousPhoto = _estPhotos[key];
    if (previousValue.trim().isEmpty &&
        (previousPhoto == null || previousPhoto.trim().isEmpty)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this reading and photo?'),
        content: Text(_estTargetLabel(key)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            style: FilledButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final previousReadingsJson = provider.activeDraft.soEstReadings;
    final previousPhotosJson = provider.activeDraft.soEstPhotos;
    final previousSamplesJson = provider.activeDraft.soEstSamplesJson;
    final previousAvg = provider.activeDraft.soEstAvg;
    final previousCv = provider.activeDraft.soEstCv;
    final previousAvgText = _estAvgController.text;
    final previousCvText = _estCvController.text;

    setState(() {
      controller.clear();
      _estPhotos[key] = null;
    });
    _updateEstPhotos(provider);
    _updateEstCalculations(provider);

    final persisted = await _persistActiveAuditRow(provider);
    if (!mounted) return;
    if (persisted) {
      return;
    }

    setState(() {
      controller.text = previousValue;
      _estPhotos[key] = previousPhoto;
      _estAvgController.text = previousAvgText;
      _estCvController.text = previousCvText;
    });
    provider.updateField('soEstReadings', previousReadingsJson);
    provider.updateField('soEstPhotos', previousPhotosJson);
    provider.updateField('so_estSamplesJson', previousSamplesJson);
    provider.updateField('soEstAvg', previousAvg);
    provider.updateField('soEstCv', previousCv);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not clear EST point. Try again.')),
    );
  }

  Future<void> _confirmSingleEstReading(
    AuditProvider provider,
    String key,
    String path,
  ) async {
    final reading = await _recognizeThermoScanReadingFahrenheit(path);
    if (!mounted) return;

    final valueController = TextEditingController(
      text: reading == null ? '' : reading.toStringAsFixed(1),
    );
    final action = await showDialog<_EstScanAction>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            final parsedValue = double.tryParse(valueController.text);
            return AuditNumericKeyboardScope(
              child: AlertDialog(
                title: Text(_estTargetLabel(key)),
                content: AuditNumericField(
                  controller: valueController,
                  allowDecimal: true,
                  maxDecimalPlaces: 1,
                  decoration: InputDecoration(
                    labelText: 'Temperature',
                    suffixText: '°F',
                    helperText: reading == null
                        ? 'No reading found. Enter it manually or retake.'
                        : 'Confirm or edit the detected reading.',
                  ),
                  onChanged: (_) => setDialogState(() {}),
                ),
                actions: [
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, _EstScanAction.skip),
                    child: const Text('Skip'),
                  ),
                  TextButton(
                    onPressed: () =>
                        Navigator.pop(dialogContext, _EstScanAction.retake),
                    child: const Text('Retake'),
                  ),
                  FilledButton(
                    onPressed: parsedValue == null
                        ? null
                        : () => Navigator.pop(
                            dialogContext,
                            _EstScanAction.confirm,
                          ),
                    child: const Text('Confirm'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    final parsedValue = double.tryParse(valueController.text);
    valueController.dispose();
    if (!mounted) return;

    if (action == _EstScanAction.confirm && parsedValue != null) {
      _saveEstPoint(provider, key, path, parsedValue);
      return;
    }
    if (action == _EstScanAction.retake) {
      final newPath = await _photoService.pickPhoto(fromCamera: true);
      if (newPath != null && mounted) {
        await _confirmSingleEstReading(provider, key, newPath);
      }
    }
  }

  Future<double?> _recognizeThermoScanReadingFahrenheit(
    String imagePath, {
    ThermoScanCropFrame? cropFrame,
    bool fanOutVariants = true,
  }) async {
    final celsius = await _ocrService.recognizeThermoScanReadingCelsius(
      imagePath,
      cropFrame: cropFrame,
      fanOutVariants: fanOutVariants,
    );
    if (celsius == null) return null;
    return TempConverter.toFahrenheit(celsius);
  }

  /// Launch the reusable full-screen OCR capture flow (EST, °F) for the ACTIVE
  /// sample, pre-populated with the current grid, then merge confirmed readings
  /// via [_saveEstPoint]. Persistence + sync unchanged.
  Future<void> _openEstCapture(AuditProvider provider) async {
    if (provider.isReadOnly) return;
    _syncActiveEstSampleToDraft(provider);
    final result = await OcrCaptureLauncher.push(
      context,
      OcrCaptureConfig(
        title: 'Eggshell Temperature',
        unitSuffix: '°F',
        convertCelsiusToFahrenheit: true,
        initialReadings: _currentEstReadings(),
        initialPhotos: _currentEstPhotoPaths(),
        tempStatusFn: CalculationUtils.setterEstStatus,
        tempZoneFn: CalculationUtils.setterEstZone,
        targetLabelBuilder: _estTargetLabel,
        readOnly: provider.isReadOnly,
      ),
      ocrService: _ocrService,
      photoService: _photoService,
    );
    if (result == null || result.isEmpty || !mounted) return;
    OcrCaptureLauncher.apply(
      result,
      (key, path, value) => _saveEstPoint(provider, key, path, value),
    );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${result.readings.length} EST readings.')),
    );
  }

  void _saveEstPoint(
    AuditProvider provider,
    String key,
    String path,
    double value,
  ) {
    setState(() {
      _estPhotos[key] = path;
      _estControllers[key]?.text = value.toStringAsFixed(1);
    });
    _updateEstPhotos(provider);
    _updateEstCalculations(provider);
    unawaited(_saveEstEvidencePhotoRecord(provider, key, path));
  }

  Future<void> _saveEstEvidencePhotoRecord(
    AuditProvider provider,
    String key,
    String path,
  ) async {
    final draft = provider.activeDraft;
    final sessionId = draft.sessionId;
    if (sessionId == null || sessionId.isEmpty || path.trim().isEmpty) return;
    final existing = await _photoRepository.getByFilePath(path);
    final photo = PhotoModel(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: path,
      description: 'setter_est',
      createdAt: existing?.createdAt ?? DateTime.now(),
      sessionId: sessionId,
      panelName: 'setter_optimizing',
      panelRowId: '$sessionId:setter_optimizing:${draft.id}',
      fieldKey: 'setter_est_$key',
      uploadStatus: existing?.uploadStatus ?? 'local',
    );
    await _photoRepository.saveLocalPhoto(photo);
  }

  String _estTargetLabel(String key) {
    final parts = key.split('_');
    if (parts.length != 2) return key;
    return '${EstGridData.label(parts[0])} - ${EstGridData.label(parts[1])}';
  }

  Map<String, double> _currentEstReadings() {
    final readings = <String, double>{};
    for (final entry in _estControllers.entries) {
      final value = double.tryParse(entry.value.text);
      if (value != null) readings[entry.key] = value;
    }
    return readings;
  }

  Map<String, String> _currentEstPhotoPaths() {
    final photos = <String, String>{};
    for (final entry in _estPhotos.entries) {
      final path = entry.value;
      if (path != null && path.isNotEmpty) {
        photos[entry.key] = path;
      }
    }
    return photos;
  }

  void _updateEstPhotos(AuditProvider provider) {
    final photos = <String, String>{};
    for (final entry in _estPhotos.entries) {
      final path = entry.value;
      if (path != null && path.isNotEmpty) {
        photos[entry.key] = path;
      }
    }
    provider.updateField(
      'soEstPhotos',
      photos.isEmpty ? null : jsonEncode(photos),
    );
    _syncActiveEstSampleToDraft(provider);
  }

  void _updateEstCalculations(AuditProvider provider) {
    final temps = _estControllers.values
        .map((controller) => double.tryParse(controller.text))
        .whereType<double>()
        .toList();
    if (temps.isEmpty) {
      setState(() {
        _estAvgController.text = '';
        _estCvController.text = '';
      });
      provider.updateField('soEstAvg', null);
      provider.updateField('soEstCv', null);
    } else {
      final avg = CalculationUtils.average(temps);
      final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;
      setState(() {
        _estAvgController.text = avg.toStringAsFixed(1);
        _estCvController.text = cv.toStringAsFixed(1);
      });
      provider.updateField('soEstAvg', avg);
      provider.updateField('soEstCv', cv);
    }

    final readings = _currentEstReadings();
    provider.updateField(
      'soEstReadings',
      readings.isEmpty ? null : jsonEncode(readings),
    );
    _syncActiveEstSampleToDraft(provider);
  }

  Color _estAverageColor() {
    final avg = double.tryParse(_estAvgController.text);
    if (avg == null) return Colors.blueGrey;
    return switch (CalculationUtils.setterEstStatus(avg)) {
      TemperatureStatus.optimal => AppColors.statusGood,
      TemperatureStatus.low ||
      TemperatureStatus.high => AppColors.statusWarning,
    };
  }

  Widget _summCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withAlpha(18),
      borderRadius: BorderRadius.circular(10),
      border: Border.all(color: color.withAlpha(90)),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: AppColors.textSecondary,
            fontWeight: FontWeight.w700,
          ),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.w800,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  String _setterTabLabel(AuditModel audit, int index) {
    final raw = (audit.setterId ?? audit.soSetterId ?? '').trim();
    if (raw.isEmpty) return 'S';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'S$digits';
    final withoutPrefix = raw.toLowerCase().startsWith('s')
        ? raw.substring(1).trim()
        : raw;
    return 'S$withoutPrefix';
  }

  String _setterNumberValue(AuditModel audit) {
    final raw = (audit.setterId ?? audit.soSetterId ?? '').trim();
    return raw.isEmpty ? 'S' : raw;
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
}
