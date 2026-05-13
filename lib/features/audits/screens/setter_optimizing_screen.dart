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
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../services/ocr/ocr_service.dart';
import '../../../services/photo/photo_service.dart';
import '../../auth/providers/auth_provider.dart';
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

class _SetterOptimizingScreenState extends State<SetterOptimizingScreen>
    with WidgetsBindingObserver {
  static const Duration _estAutoScanInterval = Duration(milliseconds: 1000);

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
  final AuditRepository _auditRepository = AuditRepository();
  final PhotoRepository _photoRepository = PhotoRepository();
  final GlobalKey<InlineCameraCaptureState> _estCameraKey = GlobalKey();

  final TextEditingController _estGuidedValueController =
      TextEditingController();
  final TextEditingController _estAvgController = TextEditingController();
  final TextEditingController _estCvController = TextEditingController();
  final TextEditingController _incubationAgeController = TextEditingController(
    text: '1',
  );
  final TextEditingController _incubationHoursController =
      TextEditingController(text: '0');
  late final TextEditingController _setterIdController;
  final TextEditingController _turningAngleController = TextEditingController();
  final TextEditingController _co2Controller = TextEditingController();

  String? _machineType;
  String? _activeAuditId;
  EstGuidedCaptureState? _estCaptureState;
  String? _estHighlightedKey;
  int _estSuccessPulse = 0;
  bool _estInlineCameraUnavailable = false;
  bool _estInlineCameraReady = false;
  bool _isConfirmingEstCapture = false;
  int _estCaptureGeneration = 0;
  Timer? _estAutoScanTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didUpdateWidget(covariant SetterOptimizingScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_isDifferentAuditContext(oldWidget.context, widget.context)) {
      _nextEstCaptureGeneration();
      _stopEstAutoScan(message: 'Auto scan stopped.');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached) {
      _nextEstCaptureGeneration();
      _stopEstAutoScan(message: 'Auto scan stopped.');
    }
  }

  void _initializeFormState(AuditModel audit) {
    _setterIdController.text = audit.setterId ?? audit.soSetterId ?? '';
    _incubationAgeController.text = (audit.soIncubationAge ?? 1).toString();
    _incubationHoursController.text = (audit.soIncubationHours ?? 0).toString();
    _machineType = audit.soMachineType;
    _turningAngleController.text = audit.soTurningAngle != null
        ? audit.soTurningAngle!.toStringAsFixed(1)
        : '';
    _co2Controller.text = audit.soCo2 != null
        ? audit.soCo2!.toStringAsFixed(1)
        : '';
    for (final controller in _estControllers.values) {
      controller.clear();
    }
    _estPhotos.clear();
    _estAvgController.text = audit.soEstAvg != null
        ? audit.soEstAvg!.toStringAsFixed(1)
        : '';
    _estCvController.text = audit.soEstCv != null
        ? audit.soEstCv!.toStringAsFixed(1)
        : '';
    _loadEstReadings(audit.soEstReadings);
    _loadEstPhotos(audit.soEstPhotos);
  }

  void _syncActiveSampleForm(AuditModel audit) {
    if (_activeAuditId == audit.id) return;
    _activeAuditId = audit.id;
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(_estCaptureState);
    _estCaptureState = null;
    _estGuidedValueController.clear();
    _estHighlightedKey = null;
    _isConfirmingEstCapture = false;
    _initializeFormState(audit);
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
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(_estCaptureState);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    for (final controller in _estControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _estFocusNodes.values) {
      focusNode.dispose();
    }
    _estGuidedValueController.dispose();
    _estAvgController.dispose();
    _estCvController.dispose();
    _incubationAgeController.dispose();
    _incubationHoursController.dispose();
    _setterIdController.dispose();
    _turningAngleController.dispose();
    _co2Controller.dispose();
    super.dispose();
  }

  int _nextEstCaptureGeneration() => ++_estCaptureGeneration;

  bool _isCurrentEstCaptureGeneration(int generation) =>
      mounted && generation == _estCaptureGeneration;

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
                  _buildIncubationCard(auditProvider),
                  const SizedBox(height: 16),
                  _buildMachineCard(auditProvider),
                  const SizedBox(height: 16),
                  _buildCo2Card(auditProvider, audit),
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Setters',
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            OutlinedButton.icon(
              key: const ValueKey('setter-add-sample-button'),
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
              label: const Text('Add setter'),
            ),
            IconButton.outlined(
              tooltip: 'Remove selected setter',
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
                  label: Text(_setterTabLabel(provider.drafts[i], i)),
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

  Widget _buildIdentityCard(AuditProvider auditProvider, AuditModel audit) {
    return Card(
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
              child: Text(audit.soBreed ?? widget.context.breed ?? 'Unknown'),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _setterIdController,
              enabled: !auditProvider.isReadOnly,
              decoration: const InputDecoration(
                labelText: 'Setter ID',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) {
                auditProvider.updateField('setterId', value);
                auditProvider.updateField('soSetterId', value);
                if (mounted) setState(() {});
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildIncubationCard(AuditProvider auditProvider) {
    return Card(
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
              value: double.tryParse(_incubationAgeController.text) ?? 1,
              min: 1,
              max: 18,
              divisions: 17,
              onChanged: auditProvider.isReadOnly
                  ? null
                  : (value) {
                      final age = value.toInt();
                      setState(() {
                        _incubationAgeController.text = age.toString();
                      });
                      auditProvider.updateField('soIncubationAge', age);
                    },
            ),
            const SizedBox(height: 12),
            Text(
              'Incubation Hours: ${_incubationHoursController.text} hours',
              style: AppTextStyles.body,
            ),
            Slider(
              key: const ValueKey('setter-incubation-hours-slider'),
              value: double.tryParse(_incubationHoursController.text) ?? 0,
              min: 0,
              max: 23,
              divisions: 23,
              onChanged: auditProvider.isReadOnly
                  ? null
                  : (value) {
                      final hours = value.toInt();
                      setState(() {
                        _incubationHoursController.text = hours.toString();
                      });
                      auditProvider.updateField('soIncubationHours', hours);
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMachineCard(AuditProvider auditProvider) {
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
            Text(
              'Machine Type',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
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
                      color: selected
                          ? AppColors.primary
                          : AppColors.borderDefault,
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            AuditNumericField(
              controller: _turningAngleController,
              enabled: !auditProvider.isReadOnly,
              allowDecimal: true,
              maxDecimalPlaces: 1,
              decoration: const InputDecoration(
                labelText: 'Turning Angle (°)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => auditProvider.updateField(
                'so_turningAngle',
                double.tryParse(value),
              ),
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
            AuditNumericField(
              controller: _co2Controller,
              enabled: !auditProvider.isReadOnly,
              allowDecimal: true,
              decoration: const InputDecoration(
                labelText: 'CO2 Level (ppm)',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => auditProvider.updateField(
                'soCo2',
                double.tryParse(value),
              ),
            ),
            const SizedBox(height: 8),
            PhotoButton(
              photoPath: audit.soCo2Photo,
              enabled: !auditProvider.isReadOnly,
              onPhotoCaptured: (path) =>
                  auditProvider.updateField('soCo2Photo', path),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEstGridSection(AuditProvider provider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSetterEstTargetCard(),
        const SizedBox(height: 12),
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
                  : () => _toggleEstGuidedCapture(provider),
              icon: Icon(
                _estCaptureState == null ? Icons.photo_camera : Icons.close,
              ),
              label: Text(
                _estCaptureState == null ? 'Guided capture' : 'Close capture',
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (_estCaptureState != null) ...[
          _buildInlineEstCapturePanel(provider),
          const SizedBox(height: 12),
        ],
        EstGridWidget(
          controllers: _estControllers,
          focusNodes: _estFocusNodes,
          photos: _estPhotos,
          enabled: !provider.isReadOnly,
          highlightedKey: _estHighlightedKey,
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
                Colors.blue,
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

  Widget _buildSetterEstTargetCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withAlpha(80)),
      ),
      child: Wrap(
        spacing: 10,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Icon(Icons.thermostat_outlined, color: AppColors.primary, size: 20),
          Text(
            'Allowed 99.5-102°F',
            style: AppTextStyles.body.copyWith(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(
            'Optimum 100-101°F',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInlineEstCapturePanel(AuditProvider provider) {
    final state = _estCaptureState!;

    return EstGuidedCapturePanel(
      state: state,
      valueController: _estGuidedValueController,
      preview: InlineCameraCapture(
        key: _estCameraKey,
        capturedImagePath: state.capturedImagePath,
        isScanning: state.capturedImagePath == null,
        successPulse: _estSuccessPulse,
        onCameraReadyChanged: _handleInlineCameraReadyChanged,
        onCameraError: _handleInlineCameraError,
      ),
      unitSuffix: '°F',
      targetLabelBuilder: _estTargetLabel,
      useCameraAppForCapture: _estInlineCameraUnavailable,
      canAutoScan: _estInlineCameraReady && !_estInlineCameraUnavailable,
      isConfirming: _isConfirmingEstCapture,
      onCapture: () =>
          unawaited(_captureInlineEstReading(useNativeCamera: false)),
      onUseNativeCamera: () =>
          unawaited(_captureInlineEstReading(useNativeCamera: true)),
      onAutoScan: _startEstAutoScan,
      onStopAutoScan: () => _stopEstAutoScan(message: 'Auto scan stopped.'),
      onRetake: _retakeInlineEstCapture,
      onSkip: _skipInlineEstCapture,
      onFinish: _finishInlineEstCapture,
      onValueChanged: (value) {
        final current = _estCaptureState;
        if (current == null) return;
        setState(() => _estCaptureState = current.valueEdited(value));
      },
      onConfirm: () => unawaited(_confirmInlineEstCapture(provider)),
      onRejectAutoScanReading: _rejectInlineAutoScanReading,
    );
  }

  void _toggleEstGuidedCapture(AuditProvider provider) {
    if (_estCaptureState == null) {
      _nextEstCaptureGeneration();
      setState(() {
        _estCaptureState = EstGuidedCaptureState.initial(
          readings: _currentEstReadings(),
          photos: _currentEstPhotoPaths(),
        );
        _estGuidedValueController.clear();
        _estHighlightedKey = null;
        _estInlineCameraUnavailable = false;
        _estInlineCameraReady = false;
        _isConfirmingEstCapture = false;
      });
      return;
    }

    _finishInlineEstCapture(showMessage: false);
  }

  void _startEstAutoScan() {
    final current = _estCaptureState;
    if (current == null ||
        current.isProcessing ||
        current.isOcrProcessing ||
        !_estInlineCameraReady ||
        _estInlineCameraUnavailable) {
      return;
    }

    _nextEstCaptureGeneration();
    final nextState = current.startAutoScan();
    setState(() {
      _estCaptureState = nextState;
      if (nextState.isAutoScanning) _estGuidedValueController.clear();
    });

    if (nextState.isAutoScanning) {
      _ensureEstAutoScanTimer();
    }
  }

  void _ensureEstAutoScanTimer() {
    if (_estAutoScanTimer?.isActive ?? false) return;
    _estAutoScanTimer = Timer.periodic(_estAutoScanInterval, (_) {
      unawaited(_runEstAutoScanAttempt());
    });
  }

  void _cancelEstAutoScanTimer() {
    _estAutoScanTimer?.cancel();
    _estAutoScanTimer = null;
  }

  void _stopEstAutoScan({String? message}) {
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    final current = _estCaptureState;
    if (!mounted || current == null) return;
    setState(() {
      _estCaptureState = current.stopAutoScan(message: message);
    });
  }

  Future<void> _runEstAutoScanAttempt() async {
    if (!mounted) return;
    final current = _estCaptureState;
    if (current == null || !current.canStartOcrAttempt) return;
    final generation = _estCaptureGeneration;

    setState(() {
      _estCaptureState = current.autoScanAttemptStarted();
    });

    final inlineCamera = _estCameraKey.currentState;
    final sourcePath = await inlineCamera?.takePictureForAutoScan();
    if (!_isCurrentEstCaptureGeneration(generation)) {
      if (sourcePath != null) unawaited(_photoService.deletePhoto(sourcePath));
      return;
    }

    if (sourcePath == null) {
      _cancelEstAutoScanTimer();
      final state = _estCaptureState;
      if (state == null) return;
      setState(() {
        if (inlineCamera?.hasCameraError ?? false) {
          _estInlineCameraUnavailable = true;
        }
        _estCaptureState = state.stopAutoScan(
          message: 'Auto scan stopped. Use Capture or Camera app.',
        );
      });
      return;
    }

    final reading = await _recognizeThermoScanReadingFahrenheit(sourcePath);
    if (!_isCurrentEstCaptureGeneration(generation)) {
      unawaited(_photoService.deletePhoto(sourcePath));
      return;
    }

    final state = _estCaptureState;
    if (state == null) {
      unawaited(_photoService.deletePhoto(sourcePath));
      return;
    }

    if (reading == null) {
      unawaited(_photoService.deletePhoto(sourcePath));
      setState(() {
        _estGuidedValueController.clear();
        _estCaptureState = state.autoScanAttemptResolved(
          photoPath: sourcePath,
          ocrValue: null,
        );
      });
      return;
    }

    _cancelEstAutoScanTimer();
    setState(() {
      _estGuidedValueController.text = reading.toStringAsFixed(1);
      _estCaptureState = state.autoScanAttemptResolved(
        photoPath: sourcePath,
        ocrValue: reading,
      );
    });
  }

  void _rejectInlineAutoScanReading() {
    final state = _estCaptureState;
    if (state == null || state.capturedImagePath == null) return;

    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    final shouldResumeAutoScan = state.isAutoScanReview;
    _discardUnconfirmedEstPhoto(state);
    setState(() {
      _estGuidedValueController.clear();
      _isConfirmingEstCapture = false;
      _estCaptureState = shouldResumeAutoScan
          ? state.rejectAutoScanReading()
          : state.retake();
    });
    if (shouldResumeAutoScan) _ensureEstAutoScanTimer();
  }

  void _discardUnconfirmedEstPhoto(EstGuidedCaptureState? state) {
    if (state == null || state.isCurrentPointConfirmed) return;
    final path = state.capturedImagePath;
    if (path == null || path.isEmpty) return;
    unawaited(_photoService.deletePhoto(path));
  }

  void _handleInlineCameraReadyChanged(bool isReady) {
    if (!mounted || _estInlineCameraReady == isReady) return;
    setState(() {
      _estInlineCameraReady = isReady;
      if (isReady) _estInlineCameraUnavailable = false;
    });
  }

  void _handleInlineCameraError(String message) {
    final current = _estCaptureState;
    if (!mounted || current == null || current.isProcessing) return;
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    setState(() {
      _estInlineCameraUnavailable = true;
      _estInlineCameraReady = false;
      _estCaptureState = current.captureFailed(message);
    });
  }

  Future<void> _captureInlineEstReading({required bool useNativeCamera}) async {
    final current = _estCaptureState;
    if (current == null ||
        current.isProcessing ||
        current.isOcrProcessing ||
        _isConfirmingEstCapture) {
      return;
    }

    final generation = _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(current);
    FocusScope.of(context).unfocus();
    setState(() {
      _estCaptureState = current.captureStarted();
      _estGuidedValueController.clear();
    });

    String? savedPath;
    final shouldUseNativeCamera =
        useNativeCamera || _estInlineCameraUnavailable;
    var usedInlineFallback = false;
    if (shouldUseNativeCamera) {
      savedPath = await _photoService.pickPhoto(fromCamera: true);
    } else {
      final inlineCamera = _estCameraKey.currentState;
      final sourcePath = await inlineCamera?.takePicture();
      if (sourcePath != null) {
        savedPath = await _photoService.saveCapturedPhotoPath(sourcePath);
        unawaited(_photoService.deletePhoto(sourcePath));
      } else if (inlineCamera?.hasCameraError ?? false) {
        usedInlineFallback = true;
        savedPath = await _photoService.pickPhoto(fromCamera: true);
      }
    }

    if (!_isCurrentEstCaptureGeneration(generation)) {
      if (savedPath != null) unawaited(_photoService.deletePhoto(savedPath));
      return;
    }
    if (savedPath == null) {
      final state = _estCaptureState;
      if (state == null) return;
      setState(() {
        if (usedInlineFallback) _estInlineCameraUnavailable = true;
        _estCaptureState = state.captureFailed(
          shouldUseNativeCamera || usedInlineFallback
              ? 'No image captured.'
              : 'Inline camera is still starting. Try again or use Camera app.',
        );
      });
      return;
    }

    final reading = await _recognizeThermoScanReadingFahrenheit(savedPath);
    if (!_isCurrentEstCaptureGeneration(generation)) {
      unawaited(_photoService.deletePhoto(savedPath));
      return;
    }

    final state = _estCaptureState;
    if (state == null) {
      unawaited(_photoService.deletePhoto(savedPath));
      return;
    }
    if (reading == null) {
      unawaited(_photoService.deletePhoto(savedPath));
    }
    setState(() {
      if (usedInlineFallback) _estInlineCameraUnavailable = true;
      _estGuidedValueController.text = reading == null
          ? ''
          : reading.toStringAsFixed(1);
      _estCaptureState = state.captureResolved(
        photoPath: savedPath!,
        ocrValue: reading,
      );
    });
  }

  void _retakeInlineEstCapture() {
    final state = _estCaptureState;
    if (state == null || state.isProcessing || state.isOcrProcessing) return;
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(state);
    setState(() {
      _isConfirmingEstCapture = false;
      _estCaptureState = state.retake();
      _estGuidedValueController.clear();
    });
  }

  void _skipInlineEstCapture() {
    final state = _estCaptureState;
    if (state == null || state.isProcessing || state.isOcrProcessing) return;
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(state);
    if (state.isLastStep) {
      _finishInlineEstCapture();
      return;
    }
    setState(() {
      _isConfirmingEstCapture = false;
      _estCaptureState = state.skip();
      _estGuidedValueController.clear();
    });
  }

  Future<void> _confirmInlineEstCapture(AuditProvider provider) async {
    final state = _estCaptureState;
    if (state == null || !state.canConfirm || _isConfirmingEstCapture) return;
    if (state.isCurrentPointConfirmed) {
      setState(() {
        _estCaptureState = state.captureFailed(
          'This EST point is already saved. Retake to replace it.',
        );
      });
      return;
    }

    final generation = _nextEstCaptureGeneration();
    final confirmedKey = state.currentKey;
    _cancelEstAutoScanTimer();
    setState(() => _isConfirmingEstCapture = true);

    var evidencePath = state.capturedImagePath!;
    if (state.isAutoScanReview) {
      final savedPath = await _photoService.saveCapturedPhotoPath(evidencePath);
      if (!_isCurrentEstCaptureGeneration(generation)) {
        unawaited(_photoService.deletePhoto(evidencePath));
        if (savedPath != null) unawaited(_photoService.deletePhoto(savedPath));
        return;
      }
      if (savedPath == null) {
        setState(() {
          _isConfirmingEstCapture = false;
          _estCaptureState = state.stopAutoScan(
            message: 'Could not save evidence photo. Try again.',
          );
        });
        return;
      }
      unawaited(_photoService.deletePhoto(evidencePath));
      evidencePath = savedPath;
    }

    if (!_isCurrentEstCaptureGeneration(generation)) return;
    _saveEstPoint(provider, confirmedKey, evidencePath, state.ocrValue!);

    if (!_isCurrentEstCaptureGeneration(generation)) return;
    setState(() {
      _estCaptureState = state.confirm(photoPath: evidencePath);
      _estGuidedValueController.clear();
      _estHighlightedKey = confirmedKey;
      _estSuccessPulse++;
      _isConfirmingEstCapture = false;
    });

    Future.delayed(const Duration(milliseconds: 700), () {
      if (!_isCurrentEstCaptureGeneration(generation)) return;
      if (_estHighlightedKey == confirmedKey) {
        setState(() => _estHighlightedKey = null);
      }
      if (state.isLastStep &&
          _estCaptureState?.lastConfirmedKey == confirmedKey) {
        _finishInlineEstCapture();
      }
    });
  }

  void _finishInlineEstCapture({bool showMessage = true}) {
    final count = _structuredEstReadings().length;
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(_estCaptureState);
    setState(() {
      _estCaptureState = null;
      _estGuidedValueController.clear();
      _estHighlightedKey = null;
      _isConfirmingEstCapture = false;
    });

    if (!showMessage || !mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Setter EST capture saved $count readings.')),
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
      _estHighlightedKey = key;
    });
    _updateEstPhotos(provider);
    await _saveEstEvidencePhotoRecord(provider.activeDraft.id, key, path);
    await _persistActiveAuditRow(provider);
  }

  Future<bool> _persistActiveAuditRow(AuditProvider provider) async {
    try {
      await _auditRepository.updateAudit(provider.activeDraft);
      return true;
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
    final previousAvg = provider.activeDraft.soEstAvg;
    final previousCv = provider.activeDraft.soEstCv;
    final previousAvgText = _estAvgController.text;
    final previousCvText = _estCvController.text;

    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(_estCaptureState);

    setState(() {
      controller.clear();
      _estPhotos[key] = null;
      _estHighlightedKey = null;
      if (_estCaptureState != null) {
        _estGuidedValueController.clear();
        _isConfirmingEstCapture = false;
        _estCaptureState = EstGuidedCaptureState.initial(
          readings: _currentEstReadings(),
          photos: _currentEstPhotoPaths(),
        );
      }
    });
    _updateEstPhotos(provider);
    _updateEstCalculations(provider);

    final persisted = await _persistActiveAuditRow(provider);
    if (!mounted) return;
    if (persisted) {
      setState(() => _estSuccessPulse++);
      return;
    }

    setState(() {
      controller.text = previousValue;
      _estPhotos[key] = previousPhoto;
      _estAvgController.text = previousAvgText;
      _estCvController.text = previousCvText;
      if (_estCaptureState != null) {
        _estCaptureState = EstGuidedCaptureState.initial(
          readings: _currentEstReadings(),
          photos: _currentEstPhotoPaths(),
        );
      }
    });
    provider.updateField('soEstReadings', previousReadingsJson);
    provider.updateField('soEstPhotos', previousPhotosJson);
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

  Future<double?> _recognizeThermoScanReadingFahrenheit(String imagePath) async {
    final celsius = await _ocrService.recognizeThermoScanReadingCelsius(
      imagePath,
    );
    if (celsius == null) return null;
    return TempConverter.toFahrenheit(celsius);
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
    unawaited(_saveEstEvidencePhotoRecord(provider.activeDraft.id, key, path));
  }

  Future<void> _saveEstEvidencePhotoRecord(
    String auditId,
    String key,
    String path,
  ) async {
    if (auditId.isEmpty || path.trim().isEmpty) return;
    final existing = await _photoRepository.getByFilePath(path);
    final photo = PhotoModel(
      id: existing?.id ?? DateTime.now().microsecondsSinceEpoch.toString(),
      filePath: path,
      description: 'setter_est',
      createdAt: existing?.createdAt ?? DateTime.now(),
      auditId: auditId,
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

  List<Map<String, Object>> _structuredEstReadings() {
    return EstGridData.toStructuredReadings(_currentEstReadings());
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
    if (raw.isEmpty) return 'S${index + 1}';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'S$digits';
    final withoutPrefix = raw.toLowerCase().startsWith('s')
        ? raw.substring(1).trim()
        : raw;
    return 'S$withoutPrefix';
  }

  bool _isDifferentAuditContext(
    AuditContextData previous,
    AuditContextData next,
  ) {
    return previous.auditType != next.auditType ||
        previous.customerId != next.customerId ||
        previous.flockId != next.flockId ||
        previous.sessionId != next.sessionId ||
        previous.setterId != next.setterId ||
        previous.hatcherId != next.hatcherId ||
        previous.date != next.date;
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
