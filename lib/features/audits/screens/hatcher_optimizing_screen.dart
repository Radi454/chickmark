import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../services/ocr/ocr_service.dart';
import '../../../services/photo/photo_service.dart';
import '../models/est_grid_data.dart';
import '../models/est_guided_capture_state.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_autosave_status.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/est_grid_widget.dart';
import '../widgets/est_guided_capture_panel.dart';
import '../widgets/inline_camera_capture.dart';
import '../widgets/photo_button.dart';
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
  static const Duration _cvtAutoScanInterval = Duration(milliseconds: 1200);

  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    5,
    (_) => GlobalKey(),
  );
  final Map<String, TextEditingController> _controllers = {
    for (final key in EstGridData.scanKeys) key: TextEditingController(),
  };
  final Map<String, FocusNode> _focusNodes = {
    for (final key in EstGridData.scanKeys) key: FocusNode(),
  };
  final Map<String, String?> _photos = {
    for (final key in EstGridData.scanKeys) key: null,
  };
  final Map<String, String?> _meconiumPhotos = {};
  final GlobalKey<InlineCameraCaptureState> _cvtCameraKey = GlobalKey();
  final TextEditingController _avgController = TextEditingController();
  final TextEditingController _cvController = TextEditingController();
  final TextEditingController _cvtGuidedValueController =
      TextEditingController();
  final OcrService _ocrService = OcrService();
  final PhotoService _photoService = PhotoService();
  final PhotoRepository _photoRepository = PhotoRepository();
  final TextEditingController _incubationAgeController = TextEditingController(
    text: '18',
  );
  final TextEditingController _incubationHoursController =
      TextEditingController(text: '0');
  late final TextEditingController _hatcherIdController;
  final TextEditingController _setpointController = TextEditingController();
  final TextEditingController _setpointRhController = TextEditingController();
  bool _chickPanting = false;
  String? _meconium;
  EstGuidedCaptureState? _cvtCaptureState;
  String? _cvtHighlightedKey;
  int _cvtSuccessPulse = 0;
  bool _cvtInlineCameraUnavailable = false;
  bool _cvtInlineCameraReady = false;
  bool _isConfirmingCvtCapture = false;
  int _cvtCaptureGeneration = 0;
  Timer? _cvtAutoScanTimer;
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
    _incubationHoursController.text =
        (widget.initialAudit?.hoIncubationHours ?? 0).toString();
    _setpointController.text = widget.initialAudit?.hoSetpointF != null
        ? widget.initialAudit!.hoSetpointF!.toStringAsFixed(1)
        : '';
    _setpointRhController.text = widget.initialAudit?.hoSetpointRh != null
        ? widget.initialAudit!.hoSetpointRh!.toStringAsFixed(1)
        : '';
    _chickPanting = widget.initialAudit?.hoChickPanting ?? false;
    _meconium = widget.initialAudit?.hoMeconium;
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
        hatcheryId: widget.context.hatcheryId,
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
    _incubationHoursController.text = (audit.hoIncubationHours ?? 0).toString();
    _setpointController.text = audit.hoSetpointF != null
        ? audit.hoSetpointF!.toStringAsFixed(1)
        : '';
    _setpointRhController.text = audit.hoSetpointRh != null
        ? audit.hoSetpointRh!.toStringAsFixed(1)
        : '';
    _chickPanting = audit.hoChickPanting ?? false;
    _meconium = audit.hoMeconium;
    for (final controller in _controllers.values) {
      controller.clear();
    }
    for (final key in _photos.keys.toList()) {
      _photos[key] = null;
    }
    _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    _discardUnconfirmedCvtPhoto(_cvtCaptureState);
    _cvtCaptureState = null;
    _cvtGuidedValueController.clear();
    _cvtHighlightedKey = null;
    _isConfirmingCvtCapture = false;
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
      final readings = EstGridData.normalizeReadings(decoded);
      for (final entry in readings.entries) {
        _controllers[entry.key]?.text = entry.value.toStringAsFixed(1);
      }
    } catch (_) {}
  }

  void _loadCvtPhotos(String? photosJson) {
    if (photosJson == null || photosJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(photosJson);
      if (decoded is! Map) return;
      for (var entry in decoded.entries) {
        final key = _canonicalCvtKey(entry.key?.toString());
        if (key != null && entry.value is String) {
          _photos[key] = entry.value as String;
        }
      }
    } catch (_) {}
  }

  String? _canonicalCvtKey(String? rawKey) {
    if (rawKey == null || rawKey.trim().isEmpty) return null;
    final normalized = EstGridData.normalizeReadings({rawKey: 0});
    if (normalized.isEmpty) return null;
    return normalized.keys.first;
  }

  @override
  void dispose() {
    _cvtAutoScanTimer?.cancel();
    _scrollController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _avgController.dispose();
    _cvController.dispose();
    _cvtGuidedValueController.dispose();
    _incubationAgeController.dispose();
    _incubationHoursController.dispose();
    _hatcherIdController.dispose();
    _setpointController.dispose();
    _setpointRhController.dispose();
    super.dispose();
  }

  void _updateCalculations() {
    final readings = _currentCvtReadings();
    final temps = readings.values.toList();
    final photos = _currentCvtPhotoPaths();
    final auditProvider = context.read<AuditProvider>();
    if (temps.isEmpty) {
      setState(() {
        _avgController.text = '';
        _cvController.text = '';
      });
      auditProvider.updateField('hoCvtReadings', null);
      auditProvider.updateField(
        'hoCvtPhotos',
        photos.isEmpty ? null : jsonEncode(photos),
      );
      auditProvider.updateField('hoCvtAvg', null);
      auditProvider.updateField('hoCvtCv', null);
      return;
    }
    final avg = CalculationUtils.average(temps);
    final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;
    setState(() {
      _avgController.text = avg.toStringAsFixed(1);
      _cvController.text = cv.toStringAsFixed(1);
    });
    auditProvider.updateField('hoCvtReadings', jsonEncode(readings));
    auditProvider.updateField(
      'hoCvtPhotos',
      photos.isEmpty ? null : jsonEncode(photos),
    );
    auditProvider.updateField('hoCvtAvg', avg);
    auditProvider.updateField('hoCvtCv', cv);
  }

  Map<String, double> _currentCvtReadings() {
    final readings = <String, double>{};
    for (final key in EstGridData.scanKeys) {
      final value = double.tryParse(_controllers[key]?.text.trim() ?? '');
      if (value != null) readings[key] = double.parse(value.toStringAsFixed(1));
    }
    return readings;
  }

  Map<String, String> _currentCvtPhotoPaths() {
    final photos = <String, String>{};
    for (final entry in _photos.entries) {
      final path = entry.value;
      if (path != null && path.trim().isNotEmpty) {
        photos[entry.key] = path;
      }
    }
    return photos;
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
                title: 'Hatchers',
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
                  _buildHatcherTabs(auditProvider),
                  const SizedBox(height: 16),
                  _buildHatcherSettingsCard(auditProvider),
                  const SizedBox(height: 16),
                  _buildCo2Card(auditProvider, audit),
                  const SizedBox(height: 16),
                  _buildCvtGridSection(auditProvider),
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
                      key: const ValueKey('hatcher-meconium-card'),
                      padding: const EdgeInsets.all(AppSizes.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Meconium Assessment',
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              PhotoButton(
                                key: const ValueKey(
                                  'hatcher-meconium-photo-button',
                                ),
                                photoPath:
                                    _meconiumPhotos[auditProvider
                                        .activeDraft
                                        .id],
                                enabled: !auditProvider.isReadOnly,
                                panelName: 'hatcher_optimizing',
                                panelRowId:
                                    '${audit.sessionId}:hatcher_optimizing:${audit.id}',
                                fieldKey: 'meconium_photo',
                                onPhotoCaptured: (path) {
                                  setState(() {
                                    _meconiumPhotos[audit.id] = path;
                                  });
                                },
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 6,
                            runSpacing: 6,
                            children:
                                [
                                  'Normal',
                                  'Dark greenish',
                                  'Water',
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
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHatcherTabs(AuditProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Hatchers',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('hatcher-add-sample-button'),
              onPressed: provider.isReadOnly
                  ? null
                  : () {
                      provider.addSample();
                      if (!mounted) return;
                      setState(() {
                        _syncActiveSampleForm(provider.activeDraft);
                      });
                    },
              icon: const Icon(Icons.add, size: 18),
              label: const Text('Add hatcher'),
            ),
            IconButton.outlined(
              tooltip: 'Remove selected hatcher',
              onPressed: provider.isReadOnly || provider.sampleCount <= 1
                  ? null
                  : () {
                      provider.removeActiveSample();
                      if (!mounted) return;
                      setState(() {
                        _syncActiveSampleForm(provider.activeDraft);
                      });
                    },
              icon: const Icon(Icons.delete_outline),
            ),
          ],
        ),
        const SizedBox(height: 8),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (var i = 0; i < provider.drafts.length; i++) ...[
                ChoiceChip(
                  label: Text(_hatcherTabLabel(provider.drafts[i], i)),
                  selected: provider.activeSampleIndex == i,
                  onSelected: (_) {
                    provider.switchSample(i);
                    if (!mounted) return;
                    _syncActiveSampleForm(provider.activeDraft);
                  },
                  selectedColor: AppColors.primary.withAlpha(30),
                  checkmarkColor: AppColors.primary,
                  labelStyle: AppTextStyles.body.copyWith(
                    color: provider.activeSampleIndex == i
                        ? AppColors.primary
                        : AppColors.textBody,
                    fontWeight: provider.activeSampleIndex == i
                        ? FontWeight.w800
                        : FontWeight.w600,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                    side: BorderSide(
                      color: provider.activeSampleIndex == i
                          ? AppColors.primary
                          : AppColors.borderDefault,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildHatcherSettingsCard(AuditProvider provider) {
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
              'Hatcher settings',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _hatcherIdController,
              enabled: !provider.isReadOnly,
              decoration: const InputDecoration(
                labelText: 'Hatcher number',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                provider.updateField('hatcherId', value);
                provider.updateField('hoHatcherId', value);
                if (mounted) setState(() {});
              },
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: AuditNumericField(
                    key: const ValueKey('hatcher-setpoint-f-field'),
                    controller: _setpointController,
                    enabled: !provider.isReadOnly,
                    allowDecimal: true,
                    maxDecimalPlaces: 1,
                    decoration: const InputDecoration(
                      labelText: 'Setpoint (°F)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => provider.updateField(
                      'ho_setpointF',
                      double.tryParse(value),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AuditNumericField(
                    key: const ValueKey('hatcher-setpoint-rh-field'),
                    controller: _setpointRhController,
                    enabled: !provider.isReadOnly,
                    allowDecimal: true,
                    maxDecimalPlaces: 1,
                    decoration: const InputDecoration(
                      labelText: 'Setpoint RH (%)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => provider.updateField(
                      'ho_setpointRh',
                      double.tryParse(value),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'Incubation Age: ${_incubationAgeController.text} days',
              style: AppTextStyles.body,
            ),
            Slider(
              value: double.tryParse(_incubationAgeController.text) ?? 18,
              min: 18,
              max: 21,
              divisions: 3,
              onChanged: provider.isReadOnly
                  ? null
                  : (value) {
                      final age = value.toInt();
                      setState(() {
                        _incubationAgeController.text = age.toString();
                      });
                      provider.updateField('hoIncubationAge', age);
                    },
            ),
            const SizedBox(height: 12),
            Text(
              'Incubation Hours: ${_incubationHoursController.text} hours',
              style: AppTextStyles.body,
            ),
            Slider(
              key: const ValueKey('hatcher-incubation-hours-slider'),
              value: double.tryParse(_incubationHoursController.text) ?? 0,
              min: 0,
              max: 23,
              divisions: 23,
              onChanged: provider.isReadOnly
                  ? null
                  : (value) {
                      final hours = value.toInt();
                      setState(() {
                        _incubationHoursController.text = hours.toString();
                      });
                      provider.updateField('hoIncubationHours', hours);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCo2Card(AuditProvider provider, AuditModel audit) {
    return Card(
      key: _sectionKeys[1],
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                enabled: !provider.isReadOnly,
                decoration: const InputDecoration(
                  labelText: 'CO2 Level (ppm)',
                  border: OutlineInputBorder(),
                ),
                onChanged: (value) =>
                    provider.updateField('hoCo2', double.tryParse(value)),
              ),
            ),
            const SizedBox(width: 8),
            PhotoButton(
              key: const ValueKey('hatcher-co2-photo-button'),
              photoPath: audit.hoCo2Photo,
              enabled: !provider.isReadOnly,
              onPhotoCaptured: (path) =>
                  provider.updateField('hoCo2Photo', path),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCvtGridSection(AuditProvider provider) {
    return Card(
      key: _sectionKeys[2],
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
                    'Chick Vent Temperature',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                OutlinedButton.icon(
                  onPressed: provider.isReadOnly
                      ? null
                      : () => _toggleCvtGuidedCapture(provider),
                  icon: Icon(
                    _cvtCaptureState == null ? Icons.photo_camera : Icons.close,
                  ),
                  label: Text(
                    _cvtCaptureState == null
                        ? 'Guided CVT capture'
                        : 'Close capture',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_cvtCaptureState != null) ...[
              _buildInlineCvtCapturePanel(provider),
              const SizedBox(height: 12),
            ],
            EstGridWidget(
              key: const ValueKey('hatcher-cvt-temperature-grid'),
              controllers: _controllers,
              focusNodes: _focusNodes,
              photos: _photos,
              enabled: !provider.isReadOnly,
              highlightedKey: _cvtHighlightedKey,
              showPhotoCapture: false,
              title: null,
              unitSuffix: '°F',
              tempStatusFn: CalculationUtils.cvtStatus,
              tempZoneFn: CalculationUtils.cvtZone,
              onValueChanged: (_, _) {
                _updateCalculations();
                if (mounted) setState(() {});
              },
              onPhotoCaptured: (key, path) {
                unawaited(_handleCvtPhotoCaptured(provider, key, path));
              },
              onMissingPhotoRequested: (key) {
                unawaited(_attachMissingCvtPhoto(provider, key));
              },
              onClearRequested: (key) {
                unawaited(_clearCvtPoint(provider, key));
              },
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _summaryCard(
                    'AVG',
                    _avgController.text.isEmpty
                        ? '--'
                        : '${_avgController.text}°F',
                    Colors.blue,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: _summaryCard(
                    'CV%',
                    _cvController.text.isEmpty
                        ? '--'
                        : '${_cvController.text}%',
                    Colors.blueGrey,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(100)),
      ),
      child: Column(
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 4),
          Text(
            value,
            style: AppTextStyles.heading.copyWith(fontSize: 24, color: color),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineCvtCapturePanel(AuditProvider provider) {
    final state = _cvtCaptureState!;
    return EstGuidedCapturePanel(
      state: state,
      valueController: _cvtGuidedValueController,
      unitSuffix: '°F',
      targetLabelBuilder: _cvtTargetLabel,
      preview: InlineCameraCapture(
        key: _cvtCameraKey,
        capturedImagePath: state.capturedImagePath,
        isScanning: state.capturedImagePath == null,
        successPulse: _cvtSuccessPulse,
        onCameraReadyChanged: _handleCvtInlineCameraReadyChanged,
        onCameraError: _handleCvtInlineCameraError,
      ),
      useCameraAppForCapture: _cvtInlineCameraUnavailable,
      canAutoScan: _cvtInlineCameraReady && !_cvtInlineCameraUnavailable,
      isConfirming: _isConfirmingCvtCapture,
      onCapture: () =>
          unawaited(_captureInlineCvtReading(useNativeCamera: false)),
      onUseNativeCamera: () =>
          unawaited(_captureInlineCvtReading(useNativeCamera: true)),
      onAutoScan: _startCvtAutoScan,
      onStopAutoScan: () => _stopCvtAutoScan(message: 'Auto scan stopped.'),
      onRetake: _retakeInlineCvtCapture,
      onSkip: _skipInlineCvtCapture,
      onFinish: _finishCvtCapture,
      onValueChanged: (value) {
        final current = _cvtCaptureState;
        if (current == null) return;
        setState(() => _cvtCaptureState = current.valueEdited(value));
      },
      onConfirm: () => unawaited(_confirmInlineCvtCapture(provider)),
      onRejectAutoScanReading: _rejectInlineCvtAutoScanReading,
    );
  }

  String _hatcherTabLabel(AuditModel audit, int index) {
    final raw = (audit.hatcherId ?? audit.hoHatcherId ?? '').trim();
    if (raw.isEmpty) return 'H${index + 1}';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'H$digits';
    final withoutPrefix = raw.toLowerCase().startsWith('h')
        ? raw.substring(1).trim()
        : raw;
    return 'H$withoutPrefix';
  }

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

  void _toggleCvtGuidedCapture(AuditProvider provider) {
    if (_cvtCaptureState == null) {
      _nextCvtCaptureGeneration();
      setState(() {
        _cvtCaptureState = EstGuidedCaptureState.initial(
          readings: _currentCvtReadings(),
          photos: _currentCvtPhotoPaths(),
        );
        _cvtGuidedValueController.clear();
        _cvtHighlightedKey = null;
        _cvtInlineCameraUnavailable = false;
        _cvtInlineCameraReady = false;
        _isConfirmingCvtCapture = false;
      });
      return;
    }

    _finishCvtCapture(showMessage: false);
  }

  int _nextCvtCaptureGeneration() => ++_cvtCaptureGeneration;

  bool _isCurrentCvtCaptureGeneration(int generation) {
    return mounted && generation == _cvtCaptureGeneration;
  }

  void _startCvtAutoScan() {
    final current = _cvtCaptureState;
    if (current == null ||
        current.isProcessing ||
        current.isOcrProcessing ||
        !_cvtInlineCameraReady ||
        _cvtInlineCameraUnavailable) {
      return;
    }

    _nextCvtCaptureGeneration();
    final nextState = current.startAutoScan();
    setState(() {
      _cvtCaptureState = nextState;
      if (nextState.isAutoScanning) _cvtGuidedValueController.clear();
    });

    if (nextState.isAutoScanning) _ensureCvtAutoScanTimer();
  }

  void _ensureCvtAutoScanTimer() {
    if (_cvtAutoScanTimer?.isActive ?? false) return;
    _cvtAutoScanTimer = Timer.periodic(_cvtAutoScanInterval, (_) {
      unawaited(_runCvtAutoScanAttempt());
    });
  }

  void _cancelCvtAutoScanTimer() {
    _cvtAutoScanTimer?.cancel();
    _cvtAutoScanTimer = null;
  }

  void _stopCvtAutoScan({String? message}) {
    _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    final current = _cvtCaptureState;
    if (!mounted || current == null) return;
    setState(() => _cvtCaptureState = current.stopAutoScan(message: message));
  }

  Future<void> _runCvtAutoScanAttempt() async {
    if (!mounted) return;
    final current = _cvtCaptureState;
    if (current == null || !current.canStartOcrAttempt) return;
    final generation = _cvtCaptureGeneration;

    setState(() => _cvtCaptureState = current.autoScanAttemptStarted());

    final inlineCamera = _cvtCameraKey.currentState;
    final sourcePath = await inlineCamera?.takePictureForAutoScan();
    if (!_isCurrentCvtCaptureGeneration(generation)) {
      if (sourcePath != null) unawaited(_photoService.deletePhoto(sourcePath));
      return;
    }

    if (sourcePath == null) {
      _cancelCvtAutoScanTimer();
      final state = _cvtCaptureState;
      if (state == null) return;
      setState(() {
        if (inlineCamera?.hasCameraError ?? false) {
          _cvtInlineCameraUnavailable = true;
        }
        _cvtCaptureState = state.stopAutoScan(
          message: 'Auto scan stopped. Use Capture or Camera app.',
        );
      });
      return;
    }

    final reading = await _recognizeThermoScanReadingFahrenheit(sourcePath);
    if (!_isCurrentCvtCaptureGeneration(generation)) {
      unawaited(_photoService.deletePhoto(sourcePath));
      return;
    }

    final state = _cvtCaptureState;
    if (state == null) {
      unawaited(_photoService.deletePhoto(sourcePath));
      return;
    }

    if (reading == null) {
      unawaited(_photoService.deletePhoto(sourcePath));
      setState(() {
        _cvtGuidedValueController.clear();
        _cvtCaptureState = state.autoScanAttemptResolved(
          photoPath: sourcePath,
          ocrValue: null,
        );
      });
      return;
    }

    _cancelCvtAutoScanTimer();
    setState(() {
      _cvtGuidedValueController.text = reading.toStringAsFixed(1);
      _cvtCaptureState = state.autoScanAttemptResolved(
        photoPath: sourcePath,
        ocrValue: reading,
      );
    });
  }

  Future<void> _captureInlineCvtReading({required bool useNativeCamera}) async {
    final current = _cvtCaptureState;
    if (current == null ||
        current.isProcessing ||
        current.isOcrProcessing ||
        _isConfirmingCvtCapture) {
      return;
    }

    final generation = _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    _discardUnconfirmedCvtPhoto(current);
    FocusScope.of(context).unfocus();
    setState(() {
      _cvtCaptureState = current.captureStarted();
      _cvtGuidedValueController.clear();
    });

    String? savedPath;
    final shouldUseNativeCamera =
        useNativeCamera || _cvtInlineCameraUnavailable;
    var usedInlineFallback = false;
    if (shouldUseNativeCamera) {
      savedPath = await _photoService.pickPhoto(fromCamera: true);
    } else {
      final inlineCamera = _cvtCameraKey.currentState;
      final sourcePath = await inlineCamera?.takePicture();
      if (sourcePath != null) {
        savedPath = await _photoService.saveCapturedPhotoPath(sourcePath);
        unawaited(_photoService.deletePhoto(sourcePath));
      } else if (inlineCamera?.hasCameraError ?? false) {
        usedInlineFallback = true;
        savedPath = await _photoService.pickPhoto(fromCamera: true);
      }
    }

    if (!_isCurrentCvtCaptureGeneration(generation)) {
      if (savedPath != null) unawaited(_photoService.deletePhoto(savedPath));
      return;
    }
    if (savedPath == null) {
      final state = _cvtCaptureState;
      if (state == null) return;
      setState(() {
        if (usedInlineFallback) _cvtInlineCameraUnavailable = true;
        _cvtCaptureState = state.captureFailed(
          shouldUseNativeCamera || usedInlineFallback
              ? 'No image captured.'
              : 'Inline camera is still starting. Try again or use Camera app.',
        );
      });
      return;
    }

    final reading = await _recognizeThermoScanReadingFahrenheit(savedPath);
    if (!_isCurrentCvtCaptureGeneration(generation)) {
      unawaited(_photoService.deletePhoto(savedPath));
      return;
    }

    final state = _cvtCaptureState;
    if (state == null) {
      unawaited(_photoService.deletePhoto(savedPath));
      return;
    }
    if (reading == null) {
      unawaited(_photoService.deletePhoto(savedPath));
    }
    setState(() {
      if (usedInlineFallback) _cvtInlineCameraUnavailable = true;
      _cvtGuidedValueController.text = reading == null
          ? ''
          : reading.toStringAsFixed(1);
      _cvtCaptureState = state.captureResolved(
        photoPath: savedPath!,
        ocrValue: reading,
      );
    });
  }

  void _retakeInlineCvtCapture() {
    final state = _cvtCaptureState;
    if (state == null || state.isProcessing || state.isOcrProcessing) return;
    _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    _discardUnconfirmedCvtPhoto(state);
    setState(() {
      _isConfirmingCvtCapture = false;
      _cvtCaptureState = state.retake();
      _cvtGuidedValueController.clear();
    });
  }

  void _skipInlineCvtCapture() {
    final state = _cvtCaptureState;
    if (state == null || state.isProcessing || state.isOcrProcessing) return;
    _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    _discardUnconfirmedCvtPhoto(state);
    if (state.isLastStep) {
      _finishCvtCapture();
      return;
    }
    setState(() {
      _isConfirmingCvtCapture = false;
      _cvtCaptureState = state.skip();
      _cvtGuidedValueController.clear();
    });
  }

  Future<void> _confirmInlineCvtCapture(AuditProvider provider) async {
    final state = _cvtCaptureState;
    if (state == null || !state.canConfirm || _isConfirmingCvtCapture) return;
    final generation = _nextCvtCaptureGeneration();
    final confirmedKey = state.currentKey;
    _cancelCvtAutoScanTimer();
    setState(() => _isConfirmingCvtCapture = true);

    var evidencePath = state.capturedImagePath!;
    if (state.isAutoScanReview) {
      final savedPath = await _photoService.saveCapturedPhotoPath(evidencePath);
      if (!_isCurrentCvtCaptureGeneration(generation)) {
        unawaited(_photoService.deletePhoto(evidencePath));
        if (savedPath != null) unawaited(_photoService.deletePhoto(savedPath));
        return;
      }
      if (savedPath == null) {
        setState(() {
          _isConfirmingCvtCapture = false;
          _cvtCaptureState = state.stopAutoScan(
            message: 'Could not save evidence photo. Try again.',
          );
        });
        return;
      }
      unawaited(_photoService.deletePhoto(evidencePath));
      evidencePath = savedPath;
    }

    if (!_isCurrentCvtCaptureGeneration(generation)) return;
    _saveCvtPoint(confirmedKey, evidencePath, state.ocrValue!);
    unawaited(
      _saveCvtEvidencePhotoRecord(provider, confirmedKey, evidencePath),
    );
    unawaited(_persistActiveAuditRow(provider));

    if (!_isCurrentCvtCaptureGeneration(generation)) return;
    setState(() {
      _cvtCaptureState = state.confirm(photoPath: evidencePath);
      _cvtGuidedValueController.clear();
      _cvtHighlightedKey = confirmedKey;
      _cvtSuccessPulse++;
      _isConfirmingCvtCapture = false;
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!_isCurrentCvtCaptureGeneration(generation)) return;
      if (_cvtHighlightedKey == confirmedKey) {
        setState(() => _cvtHighlightedKey = null);
      }
      if (state.isLastStep &&
          _cvtCaptureState?.lastConfirmedKey == confirmedKey) {
        _finishCvtCapture();
      }
    });
  }

  void _saveCvtPoint(String key, String path, double valueF) {
    setState(() {
      _photos[key] = path;
      _controllers[key]?.text = valueF.toStringAsFixed(1);
    });
    _updateCalculations();
  }

  Future<void> _handleCvtPhotoCaptured(
    AuditProvider provider,
    String key,
    String path,
  ) async {
    final existingValue = double.tryParse(_controllers[key]?.text.trim() ?? '');
    final existingPhoto = _photos[key];
    if (existingValue != null &&
        (existingPhoto == null || existingPhoto.trim().isEmpty)) {
      setState(() {
        _photos[key] = path;
        _cvtHighlightedKey = key;
      });
      _updateCalculations();
      await _saveCvtEvidencePhotoRecord(provider, key, path);
      return;
    }

    final reading = await _recognizeThermoScanReadingFahrenheit(path);
    if (!mounted) return;
    final valueController = TextEditingController(
      text: reading == null ? '' : reading.toStringAsFixed(1),
    );
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(_cvtTargetLabel(key)),
        content: AuditNumericKeyboardScope(
          child: AuditNumericField(
            controller: valueController,
            allowDecimal: true,
            maxDecimalPlaces: 1,
            decoration: const InputDecoration(
              labelText: 'CVT',
              suffixText: '°F',
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Confirm'),
          ),
        ],
      ),
    );
    final parsed = double.tryParse(valueController.text);
    valueController.dispose();
    if (!mounted || confirmed != true || parsed == null) return;
    _saveCvtPoint(key, path, parsed);
    await _saveCvtEvidencePhotoRecord(provider, key, path);
  }

  Future<void> _attachMissingCvtPhoto(
    AuditProvider provider,
    String key,
  ) async {
    if (provider.isReadOnly ||
        double.tryParse(_controllers[key]?.text.trim() ?? '') == null) {
      return;
    }
    final path = await _photoService.pickPhoto(fromCamera: true);
    if (!mounted || path == null || path.trim().isEmpty) return;
    setState(() {
      _photos[key] = path;
      _cvtHighlightedKey = key;
    });
    _updateCalculations();
    await _saveCvtEvidencePhotoRecord(provider, key, path);
  }

  Future<void> _clearCvtPoint(AuditProvider provider, String key) async {
    if (provider.isReadOnly) return;
    final controller = _controllers[key];
    if (controller == null) return;
    final previousValue = controller.text;
    final previousPhoto = _photos[key];
    if (previousValue.trim().isEmpty &&
        (previousPhoto == null || previousPhoto.trim().isEmpty)) {
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this reading and photo?'),
        content: Text(_cvtTargetLabel(key)),
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

    setState(() {
      controller.clear();
      _photos[key] = null;
      _cvtHighlightedKey = null;
      if (_cvtCaptureState != null) {
        _cvtGuidedValueController.clear();
        _isConfirmingCvtCapture = false;
        _cvtCaptureState = EstGuidedCaptureState.initial(
          readings: _currentCvtReadings(),
          photos: _currentCvtPhotoPaths(),
        );
      }
    });
    _updateCalculations();
  }

  void _rejectInlineCvtAutoScanReading() {
    final state = _cvtCaptureState;
    if (state == null || state.capturedImagePath == null) return;

    _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    final shouldResumeAutoScan = state.isAutoScanReview;
    _discardUnconfirmedCvtPhoto(state);
    setState(() {
      _cvtGuidedValueController.clear();
      _isConfirmingCvtCapture = false;
      _cvtCaptureState = shouldResumeAutoScan
          ? state.rejectAutoScanReading()
          : state.retake();
    });
    if (shouldResumeAutoScan) _ensureCvtAutoScanTimer();
  }

  void _discardUnconfirmedCvtPhoto(EstGuidedCaptureState? state) {
    if (state == null || state.isCurrentPointConfirmed) return;
    final path = state.capturedImagePath;
    if (path == null || path.isEmpty) return;
    unawaited(_photoService.deletePhoto(path));
  }

  void _handleCvtInlineCameraReadyChanged(bool isReady) {
    if (!mounted || _cvtInlineCameraReady == isReady) return;
    setState(() {
      _cvtInlineCameraReady = isReady;
      if (isReady) _cvtInlineCameraUnavailable = false;
    });
  }

  void _handleCvtInlineCameraError(String message) {
    final current = _cvtCaptureState;
    if (!mounted || current == null || current.isProcessing) return;
    _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    setState(() {
      _cvtInlineCameraUnavailable = true;
      _cvtInlineCameraReady = false;
      _cvtCaptureState = current.captureFailed(message);
    });
  }

  void _finishCvtCapture({bool showMessage = true}) {
    final count = _currentCvtReadings().length;
    _nextCvtCaptureGeneration();
    _cancelCvtAutoScanTimer();
    _discardUnconfirmedCvtPhoto(_cvtCaptureState);
    setState(() {
      _cvtCaptureState = null;
      _cvtGuidedValueController.clear();
      _cvtHighlightedKey = null;
      _isConfirmingCvtCapture = false;
    });

    if (!showMessage || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('CVT capture saved $count readings.')),
    );
  }

  Future<void> _saveCvtEvidencePhotoRecord(
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
      description: 'hatcher_cvt_$key',
      createdAt: existing?.createdAt ?? DateTime.now(),
      sessionId: sessionId,
      panelName: 'hatcher_optimizing',
      panelRowId: '$sessionId:hatcher_optimizing:${draft.id}',
      fieldKey: 'hatcher_cvt_$key',
      uploadStatus: existing?.uploadStatus ?? 'local',
    );
    await _photoRepository.saveLocalPhoto(photo);
  }

  Future<bool> _persistActiveAuditRow(AuditProvider provider) async {
    try {
      return provider.saveSamplesWithResult(tabIndex: 0);
    } catch (_) {
      return false;
    }
  }

  Future<double?> _recognizeThermoScanReadingFahrenheit(String path) async {
    final readingC = await _ocrService.recognizeThermoScanReadingCelsius(path);
    if (readingC == null) return null;
    return TempConverter.toFahrenheit(readingC);
  }

  String _cvtTargetLabel(String key) {
    final parts = key.split('_');
    if (parts.length != 2) return key;
    return '${EstGridData.label(parts[0])} - ${EstGridData.label(parts[1])}';
  }
}
