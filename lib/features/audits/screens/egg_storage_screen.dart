import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/audit_type_labels.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/database/database_helper.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/audit_repository.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../providers/customers_provider.dart';
import '../../../services/ocr/ocr_service.dart';
import '../../../services/photo/photo_service.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/audit_provider.dart';
import '../utils/egg_storage_bmk_age.dart';
import '../models/est_grid_data.dart';
import '../models/est_guided_capture_state.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/est_grid_widget.dart';
import '../widgets/est_guided_capture_panel.dart';
import '../widgets/inline_camera_capture.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/photo_button.dart';
import '../widgets/weight_grid_widget.dart';
import 'audit_context_screen.dart';

class EggStorageScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final List<AuditModel> initialAudits;
  final List<StationSampleModel> initialStationSamples;
  final int initialSectionIndex;
  final EggStorageStationController? stationController;

  const EggStorageScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialAudits = const [],
    this.initialStationSamples = const [],
    this.initialSectionIndex = 0,
    this.stationController,
  });

  @override
  State<EggStorageScreen> createState() => _EggStorageScreenState();
}

class EggStorageStationController {
  _EggStorageScreenState? _state;

  Future<bool> prepareForStationExit() =>
      _state?._prepareForStationExit() ?? Future.value(true);

  void _attach(_EggStorageScreenState state) {
    _state = state;
  }

  void _detach(_EggStorageScreenState state) {
    if (identical(_state, state)) _state = null;
  }
}

class _EggStorageScreenState extends State<EggStorageScreen>
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
  final TextEditingController _storageDaysController = TextEditingController();
  final TextEditingController _estAvgController = TextEditingController();
  final TextEditingController _estCvController = TextEditingController();
  final TextEditingController _notesController = TextEditingController();
  final List<_UvTray> _uvTrays = [];
  final List<TextEditingController> _eggWeightControllers = List.generate(
    100,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _eggWeightFocusNodes = List.generate(
    100,
    (_) => FocusNode(),
  );
  String? _traySpacing;
  String? _coolerProximity;
  bool? _condensation;
  double? _bmkEggWeight;
  EstGuidedCaptureState? _estCaptureState;
  String? _estHighlightedKey;
  int _estSuccessPulse = 0;
  bool _estInlineCameraUnavailable = false;
  bool _estInlineCameraReady = false;
  bool _isConfirmingEstCapture = false;
  int _estCaptureGeneration = 0;
  String? _activeAuditId;
  Timer? _estAutoScanTimer;

  @override
  void initState() {
    super.initState();
    widget.stationController?._attach(this);
    WidgetsBinding.instance.addObserver(this);
    for (final level in EstGridData.levels) {
      for (final location in EstGridData.locations) {
        final key = EstGridData.key(location, level);
        _estControllers[key] = TextEditingController();
        _estFocusNodes[key] = FocusNode();
      }
    }
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    final auditContext = AuditContext(
      auditType: widget.context.auditType,
      customerId: widget.context.customerId,
      flockId: widget.context.flockId,
      breed: widget.context.breed,
      setterId: widget.context.setterId,
      hatcherId: widget.context.hatcherId,
      flockEntryDate: widget.context.flockEntryDate,
      flockAgeWeeks: widget.context.flockAgeWeeks,
      date: widget.context.date,
    );
    auditProvider.initialize(
      auditContext,
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
  void didUpdateWidget(covariant EggStorageScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.stationController, widget.stationController)) {
      oldWidget.stationController?._detach(this);
      widget.stationController?._attach(this);
    }
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
    _storageDaysController.clear();
    for (final controller in _estControllers.values) {
      controller.clear();
    }
    _estPhotos.clear();
    _estAvgController.clear();
    _estCvController.clear();
    _notesController.clear();
    for (final controller in _eggWeightControllers) {
      controller.clear();
    }
    _traySpacing = null;
    _coolerProximity = null;
    _condensation = null;
    _bmkEggWeight = null;
    _storageDaysController.text = _formatNumber(audit.esEggStorageDays);
    _loadEstGrid(audit.esEstReadingsJson);
    _loadEstPhotos(audit.esEstPhotosJson);
    _estAvgController.text = audit.esEstAvg != null
        ? audit.esEstAvg!.toStringAsFixed(1)
        : '';
    _estCvController.text = audit.esEstCv != null
        ? audit.esEstCv!.toStringAsFixed(1)
        : '';
    _loadUvTrays(audit.esUvTrays);
    _loadEggWeights(audit.esEggWeights);
    _traySpacing = audit.esTraySpacing;
    _coolerProximity = audit.esCoolerProximity;
    _condensation = audit.esCondensation;
    _bmkEggWeight = audit.esEggBmkWeight;
    _notesController.text = audit.notes ?? '';
  }

  void _syncActiveSampleForm(AuditModel audit) {
    if (_activeAuditId == audit.id) return;
    _activeAuditId = audit.id;
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _estCaptureState = _estCaptureState?.stopAutoScan(
      message: 'Auto scan stopped.',
    );
    _initializeFormState(audit);
  }

  void _loadEstGrid(String? readingsJson) {
    if (readingsJson == null || readingsJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(readingsJson);
      if (decoded is! Map) return;
      final normalized = EstGridData.normalizeReadings(decoded);
      for (final entry in normalized.entries) {
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
        final rawKey = entry.key?.toString();
        final path = entry.value?.toString();
        if (rawKey == null || path == null || path.isEmpty) continue;
        final key = rawKey.startsWith('door_')
            ? rawKey.replaceFirst('door_', 'front_')
            : rawKey;
        if (_estControllers.containsKey(key)) {
          _estPhotos[key] = path;
        }
      }
    } catch (_) {
      // Keep photos blank if stored data is malformed.
    }
  }

  void _loadUvTrays(String? traysJson) {
    for (final tray in _uvTrays) {
      tray.dispose();
    }
    _uvTrays.clear();

    if (traysJson == null || traysJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(traysJson);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map) {
          _uvTrays.add(_UvTray.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    } catch (_) {
      // Keep a blank UV section if stored data is malformed.
    }
  }

  void _loadEggWeights(String? weightsJson) {
    if (weightsJson == null || weightsJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(weightsJson);
      if (decoded is! List) return;
      for (
        var i = 0;
        i < decoded.length && i < _eggWeightControllers.length;
        i++
      ) {
        _eggWeightControllers[i].text = _formatNumber(decoded[i]);
      }
    } catch (_) {
      // Keep weight fields blank if stored data is malformed.
    }
  }

  @override
  void dispose() {
    widget.stationController?._detach(this);
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(_estCaptureState);
    WidgetsBinding.instance.removeObserver(this);
    _scrollController.dispose();
    _estGuidedValueController.dispose();
    _storageDaysController.dispose();
    for (final controller in _estControllers.values) {
      controller.dispose();
    }
    for (final focusNode in _estFocusNodes.values) {
      focusNode.dispose();
    }
    _estAvgController.dispose();
    _estCvController.dispose();
    _notesController.dispose();
    for (final tray in _uvTrays) {
      tray.dispose();
    }
    for (var c in _eggWeightControllers) {
      c.dispose();
    }
    for (var n in _eggWeightFocusNodes) {
      n.dispose();
    }
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
      onBackAttempt: _handleEstBackAttempt,
      child: Scaffold(
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: AuditTypeLabels.eggStationLabel,
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
                  _buildEggStorageHeader(),
                  const SizedBox(height: 16),
                  _buildEggStorageWorkbench(audit, auditProvider),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEggStorageHeader() {
    final hatcheryName = context.select<CustomersProvider, String?>((provider) {
      final hatcheryId = widget.context.hatcheryId?.trim();
      if (hatcheryId == null || hatcheryId.isEmpty) return null;
      return provider.hatcheryById(hatcheryId)?.name;
    });
    final hatcheryId = widget.context.hatcheryId?.trim();
    final hatcheryLabel = hatcheryName?.trim().isNotEmpty == true
        ? hatcheryName!.trim()
        : (hatcheryId?.isNotEmpty == true ? hatcheryId! : 'Main Hatchery');

    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 220),
      padding: const EdgeInsets.all(AppSizes.spaceXxl),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF089FE0), Color(0xFF1C48C9)],
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadowElevated,
            blurRadius: 22,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'AUDIT STATION',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.badge.copyWith(
                  fontSize: 22,
                  letterSpacing: 0,
                  color: Colors.white.withValues(alpha: 0.82),
                ),
              ),
              const SizedBox(height: AppSizes.spaceMd),
              Text(
                'Egg storage room',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: AppTextStyles.heading.copyWith(
                  fontSize: 34,
                  height: 1.05,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceXxl),
          Container(
            padding: const EdgeInsets.all(AppSizes.spaceLg),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.24),
                width: 1.5,
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'HATCHERY',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.badge.copyWith(
                    fontSize: 20,
                    letterSpacing: 0,
                    color: Colors.white.withValues(alpha: 0.82),
                  ),
                ),
                const SizedBox(height: AppSizes.spaceSm),
                Text(
                  hatcheryLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.title.copyWith(
                    fontSize: 24,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEggStorageWorkbench(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
    final leftPanels = <Widget>[
      _buildWorkbenchPanel(
        cardKey: _sectionKeys[0],
        mark: 'EST',
        icon: Icons.thermostat_outlined,
        title: 'Egg Shell Temperature',
        meta: 'Storage class and shell readings',
        statusLabel: _estStatusLabel(),
        statusColor: _estStatusColor(),
        child: _buildEstGridSection(auditProvider),
      ),
      _buildWorkbenchPanel(
        cardKey: _sectionKeys[2],
        mark: 'UD',
        icon: Icons.flip_to_back,
        title: 'Upside Down Score',
        meta: 'Count incorrectly oriented eggs per tray',
        statusLabel: 'Avg ${_upsideDownAveragePct().toStringAsFixed(1)}%',
        statusColor: _getAffectedColor(_upsideDownAveragePct()),
        child: _buildUpsideDownSection(auditProvider),
      ),
      _buildWorkbenchPanel(
        cardKey: _sectionKeys[4],
        mark: 'CHK',
        icon: Icons.checklist,
        title: 'Storage Checklist',
        meta: 'Handling observations before set',
        statusLabel: '${_completedChecklistCount(audit)} of 4 set',
        statusColor: _completedChecklistCount(audit) >= 3
            ? AppColors.statusGood
            : AppColors.statusWarning,
        child: _buildStorageChecklistSection(audit, auditProvider),
      ),
    ];
    final rightPanels = <Widget>[
      _buildEggQualityPanel(auditProvider),
      _buildWorkbenchPanel(
        cardKey: _sectionKeys[1],
        mark: 'UV',
        icon: Icons.grid_on,
        title: 'Egg Shell Quality',
        meta: 'UV torch inspection by tray',
        statusLabel:
            'Avg affected ${_uvAffectedAveragePct().toStringAsFixed(1)}%',
        statusColor: _getAffectedColor(_uvAffectedAveragePct()),
        child: _buildUvTraySection(auditProvider),
      ),
      _buildWorkbenchPanel(
        mark: 'NT',
        icon: Icons.notes_outlined,
        title: 'Notes',
        meta: 'Optional station comments',
        child: _buildNotesSection(auditProvider),
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 900) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 96, child: _buildPanelColumn(leftPanels)),
              const SizedBox(width: 16),
              Expanded(flex: 104, child: _buildPanelColumn(rightPanels)),
            ],
          );
        }
        return _buildPanelColumn([...leftPanels, ...rightPanels]);
      },
    );
  }

  Widget _buildPanelColumn(List<Widget> panels) {
    return Column(
      children: [
        for (var i = 0; i < panels.length; i++) ...[
          if (i > 0) const SizedBox(height: 16),
          panels[i],
        ],
      ],
    );
  }

  Widget _buildWorkbenchPanel({
    required String mark,
    required IconData icon,
    required String title,
    required String meta,
    required Widget child,
    Key? cardKey,
    String? statusLabel,
    Color? statusColor,
    bool showHeader = true,
  }) {
    return Container(
      key: cardKey,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.borderDefault),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withAlpha(12),
            blurRadius: 18,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showHeader) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.infoBg,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: AppColors.primary.withAlpha(45),
                        ),
                      ),
                      child: Text(
                        mark,
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.primary,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(icon, size: 18, color: AppColors.primary),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  title,
                                  style: AppTextStyles.title.copyWith(
                                    fontWeight: FontWeight.w800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(meta, style: AppTextStyles.caption),
                        ],
                      ),
                    ),
                    if (statusLabel != null && statusColor != null) ...[
                      const SizedBox(width: 8),
                      _buildStatusPill(statusLabel, statusColor),
                    ],
                  ],
                ),
              ),
              const Divider(height: 1),
            ],
            Padding(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: child,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusPill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withAlpha(28),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: color.withAlpha(90)),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _buildShellTargetCard(_ShellStorageTarget target) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.primary.withAlpha(60)),
      ),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          _targetPill('Storage class', target.label, AppColors.primary),
          _targetPill('Shell target', target.rangeLabel, AppColors.primary),
        ],
      ),
    );
  }

  Widget _targetPill(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withAlpha(80)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 2),
          Text(
            value,
            style: AppTextStyles.body.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEstGridSection(AuditProvider auditProvider) {
    final storageDays = int.tryParse(_storageDaysController.text);
    final target = _shellStorageTarget(storageDays);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AuditNumericField(
          controller: _storageDaysController,
          enabled: !auditProvider.isReadOnly,
          decoration: InputDecoration(
            labelText: 'Storage Days',
            suffixText: 'days',
            isDense: true,
            filled: true,
            fillColor: Colors.grey[50],
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
          ),
          onChanged: (value) {
            final days = int.tryParse(value);
            auditProvider.updateField('esEggStorageDays', days);
            unawaited(_syncEggStorageBmk(auditProvider, days));
            _updateEstCalculations(auditProvider);
            setState(() {});
          },
        ),
        const SizedBox(height: 12),
        _buildShellTargetCard(target),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text(
                'Readings',
                style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
              ),
            ),
            OutlinedButton.icon(
              onPressed: auditProvider.isReadOnly
                  ? null
                  : () => _toggleEstGuidedCapture(auditProvider),
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
          _buildInlineEstCapturePanel(auditProvider),
          const SizedBox(height: 12),
        ],
        EstGridWidget(
          controllers: _estControllers,
          focusNodes: _estFocusNodes,
          photos: _estPhotos,
          enabled: !auditProvider.isReadOnly,
          highlightedKey: _estHighlightedKey,
          showPhotoCapture: false,
          title: null,
          unitSuffix: '°C',
          tempStatusFn: target.status,
          tempZoneFn: target.zone,
          onValueChanged: (key, value) => _updateEstCalculations(auditProvider),
          onPhotoCaptured: (key, path) {
            unawaited(_handleEstPhotoCaptured(auditProvider, key, path));
          },
          onMissingPhotoRequested: (key) {
            unawaited(_attachMissingEstPhoto(auditProvider, key));
          },
          onClearRequested: (key) {
            unawaited(_clearEstPoint(auditProvider, key));
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
                    : '${_estAvgController.text}°C',
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

  Widget _buildUvTraySection(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._uvTrays.asMap().entries.map(
          (entry) => _buildUvTrayCard(entry.key, entry.value, auditProvider),
        ),
        if (_uvTrays.length < 10 && !auditProvider.isReadOnly)
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _uvTrays.add(_UvTray());
              _updateUvTrays(auditProvider);
            }),
            icon: const Icon(Icons.add),
            label: const Text('Add UV Tray'),
          ),
      ],
    );
  }

  Widget _buildUpsideDownSection(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ..._uvTrays.asMap().entries.map(
          (entry) =>
              _buildUpsideDownTrayCard(entry.key, entry.value, auditProvider),
        ),
        if (_uvTrays.length < 10 && !auditProvider.isReadOnly)
          ElevatedButton.icon(
            onPressed: () => setState(() {
              _uvTrays.add(_UvTray());
              _updateUvTrays(auditProvider);
            }),
            icon: const Icon(Icons.add),
            label: const Text('Add Tray'),
          ),
      ],
    );
  }

  Widget _buildEggQualityPanel(AuditProvider auditProvider) {
    final stats = _eggWeightStats();
    final qualityStatus = _qualityStatus(stats);

    return _buildWorkbenchPanel(
      cardKey: _sectionKeys[3],
      mark: 'EQ',
      icon: Icons.monitor_weight_outlined,
      title: 'Egg Quality Assessment',
      meta: '',
      statusLabel: qualityStatus.label,
      statusColor: qualityStatus.color,
      showHeader: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildEggQualityContext(qualityStatus, auditProvider),
          const SizedBox(height: 12),
          _buildEggSampleControls(auditProvider),
          const SizedBox(height: 12),
          _buildEggUniformitySection(auditProvider),
        ],
      ),
    );
  }

  Widget _buildEggQualityContext(
    _PanelStatus status,
    AuditProvider auditProvider,
  ) {
    final storageDays = int.tryParse(_storageDaysController.text);
    final activeDraft = auditProvider.activeDraft;
    final bmkAge =
        activeDraft.esEggBmkAge ?? _calculateEggStorageBmkAge(storageDays);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Egg Quality Assessment',
                      style: AppTextStyles.title.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              _buildStatusPill(status.label, Colors.white),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildQualityContextTile('Flock', widget.context.flockId),
              _buildQualityContextTile('Breed', widget.context.breed ?? '--'),
              _buildQualityContextTile(
                'BMK Age',
                bmkAge == null ? '--' : '$bmkAge wks',
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQualityContextTile(String label, String value) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 110, maxWidth: 170),
      child: Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.white.withAlpha(35),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.white.withAlpha(45)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label.toUpperCase(),
              style: AppTextStyles.caption.copyWith(
                color: Colors.white.withAlpha(190),
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              value,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: Colors.white,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEggSampleControls(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSampleControlCard(
          title: 'Egg Sample Mode',
          note: 'Choose one sample or compare houses',
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _buildModeChip(
                label: 'Single Sample',
                selected: !auditProvider.isCompareMode,
                enabled: !auditProvider.isReadOnly,
                onSelected: () => _setEggSampleMode(auditProvider, false),
              ),
              _buildModeChip(
                label: 'Multi House Samples',
                selected: auditProvider.isCompareMode,
                enabled: !auditProvider.isReadOnly,
                onSelected: () => _setEggSampleMode(auditProvider, true),
              ),
            ],
          ),
        ),
        if (auditProvider.isCompareMode) ...[
          const SizedBox(height: 10),
          _buildSampleControlCard(
            title: 'House Samples',
            note: 'Same flock, compare egg quality by house',
            child: _buildHouseSampleChips(auditProvider),
          ),
        ],
      ],
    );
  }

  Widget _buildSampleControlCard({
    required String title,
    required String note,
    required Widget child,
  }) {
    return Container(
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  note,
                  textAlign: TextAlign.end,
                  style: AppTextStyles.caption,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          child,
        ],
      ),
    );
  }

  Widget _buildModeChip({
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
        fontWeight: FontWeight.w700,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.borderDefault,
        ),
      ),
    );
  }

  Widget _buildHouseSampleChips(AuditProvider auditProvider) {
    final chips = [
      for (final entry in auditProvider.stationSamples.asMap().entries)
        ChoiceChip(
          label: Text(entry.value.houseNo ?? entry.value.sampleLabel),
          selected: entry.key == auditProvider.activeSampleIndex,
          onSelected: auditProvider.isReadOnly
              ? null
              : (_) => _switchEggHouseSample(auditProvider, entry.key),
          selectedColor: AppColors.primary.withAlpha(30),
          checkmarkColor: AppColors.primary,
          labelStyle: AppTextStyles.body.copyWith(
            color: entry.key == auditProvider.activeSampleIndex
                ? AppColors.primary
                : AppColors.textBody,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: entry.key == auditProvider.activeSampleIndex
                  ? AppColors.primary
                  : AppColors.borderDefault,
            ),
          ),
        ),
    ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHouseSampleActionButton(
          tooltip: 'Add house sample',
          icon: Icons.add,
          onPressed: auditProvider.isReadOnly
              ? null
              : () => _addEggHouseSample(auditProvider),
        ),
        if (auditProvider.sampleCount > 1) ...[
          const SizedBox(width: 8),
          _buildHouseSampleActionButton(
            tooltip: 'Remove active house sample',
            icon: Icons.remove,
            onPressed: auditProvider.isReadOnly
                ? null
                : () => _removeActiveEggHouseSample(auditProvider),
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

  Widget _buildHouseSampleActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }

  void _setEggSampleMode(AuditProvider provider, bool compare) {
    provider.setStationSampleMode(
      compare
          ? StationSampleModel.sampleModeComparison
          : StationSampleModel.sampleModePooled,
    );
    _syncActiveSampleForm(provider.activeDraft);
    if (mounted) setState(() {});
  }

  void _addEggHouseSample(AuditProvider provider) {
    provider.addSample();
    _syncActiveSampleForm(provider.activeDraft);
    if (mounted) setState(() {});
  }

  void _switchEggHouseSample(AuditProvider provider, int index) {
    provider.switchSample(index);
    _syncActiveSampleForm(provider.activeDraft);
    if (mounted) setState(() {});
  }

  void _removeActiveEggHouseSample(AuditProvider provider) {
    provider.removeActiveSample();
    _syncActiveSampleForm(provider.activeDraft);
    if (mounted) setState(() {});
  }

  Widget _buildEggUniformitySection(AuditProvider auditProvider) {
    final stats = _eggWeightStats();
    final enteredCount = stats?.sampleSize ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUniformitySummary(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openEggWeightSheet(auditProvider),
            icon: const Icon(Icons.grid_on),
            label: Text(
              auditProvider.isReadOnly
                  ? 'View Weights ($enteredCount/100)'
                  : 'Enter Weights ($enteredCount/100)',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStorageChecklistSection(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
    const turningOptions = <int, String>{
      0: 'No Turning',
      1: '1 time',
      2: '2 times',
      3: '3 times',
      4: '4 times',
      5: '5 times',
    };
    const spacings = ['Adequate', 'Tight', 'Loose'];
    const proximities = ['Near', 'Far', 'Adjacent', 'Separate'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChoiceRow(
          label: 'Egg Turning',
          options: turningOptions.values.toList(),
          selected: turningOptions[audit.esTurningTimes],
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            final turningTimes = turningOptions.entries
                .firstWhere((entry) => entry.value == v)
                .key;
            auditProvider.updateField('esTurningTimes', turningTimes);
          },
        ),
        const SizedBox(height: 12),
        _buildChoiceRow(
          label: 'Tray Spacing',
          options: spacings,
          selected: _traySpacing,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            setState(() => _traySpacing = v);
            auditProvider.updateField('es_traySpacing', v);
          },
        ),
        const SizedBox(height: 12),
        _buildChoiceRow(
          label: 'Cooler Proximity',
          options: proximities,
          selected: _coolerProximity,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            setState(() => _coolerProximity = v);
            auditProvider.updateField('es_coolerProximity', v);
          },
        ),
        const SizedBox(height: 12),
        _buildChoiceRow(
          label: 'Condensation Present',
          options: const ['No', 'Yes'],
          selected: (_condensation ?? false) ? 'Yes' : 'No',
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            final hasCondensation = v == 'Yes';
            setState(() => _condensation = hasCondensation);
            auditProvider.updateField(
              'es_condensation',
              hasCondensation ? 1 : 0,
            );
          },
        ),
      ],
    );
  }

  Widget _buildNotesSection(AuditProvider auditProvider) {
    return TextField(
      controller: _notesController,
      enabled: !auditProvider.isReadOnly,
      minLines: 4,
      maxLines: 7,
      decoration: InputDecoration(
        labelText: 'Assessment Notes',
        alignLabelWithHint: true,
        filled: true,
        fillColor: AppColors.surfaceVariant,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
      ),
      onChanged: (value) => auditProvider.updateField('notes', value),
    );
  }

  Widget _buildChoiceRow({
    required String label,
    required List<String> options,
    required String? selected,
    required bool enabled,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opt) {
            final isSelected = selected == opt;
            return ChoiceChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: enabled ? (_) => onChanged(opt) : null,
              selectedColor: AppColors.primary.withAlpha(30),
              checkmarkColor: AppColors.primary,
              labelStyle: AppTextStyles.body.copyWith(
                color: isSelected ? AppColors.primary : Colors.black87,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : Colors.grey[300]!,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  String _estStatusLabel() {
    final avg = double.tryParse(_estAvgController.text);
    if (avg == null) return 'Pending';
    final storageDays = int.tryParse(_storageDaysController.text);
    final target = _shellStorageTarget(storageDays);
    return target.status(avg) == TemperatureStatus.optimal
        ? 'On target'
        : target.zone(avg);
  }

  Color _estStatusColor() {
    final avg = double.tryParse(_estAvgController.text);
    if (avg == null) return AppColors.statusWarning;
    final storageDays = int.tryParse(_storageDaysController.text);
    final target = _shellStorageTarget(storageDays);
    return target.status(avg) == TemperatureStatus.optimal
        ? AppColors.statusGood
        : AppColors.statusError;
  }

  double _upsideDownAveragePct() {
    return _averageTrayPct((tray) => tray.upsideDownPct);
  }

  double _uvAffectedAveragePct() {
    return _averageTrayPct((tray) => tray.affectedPct);
  }

  double _averageTrayPct(double Function(_UvTray tray) selector) {
    if (_uvTrays.isEmpty) return 0.0;
    final values = _uvTrays.map(selector).toList();
    return values.reduce((sum, value) => sum + value) / values.length;
  }

  int _completedChecklistCount(AuditModel audit) {
    return [
      audit.esTurningTimes != null,
      _traySpacing != null,
      _coolerProximity != null,
      _condensation != null,
    ].where((isComplete) => isComplete).length;
  }

  _PanelStatus _qualityStatus(_EggWeightStats? stats) {
    if (stats == null) {
      return const _PanelStatus('Pending', AppColors.statusWarning);
    }
    if (stats.cv <= AppThresholds.cvAlertPct &&
        stats.uniformity > AppThresholds.uniformityGood) {
      return const _PanelStatus('Healthy spread', AppColors.statusGood);
    }
    if (stats.uniformity < AppThresholds.uniformityPoor) {
      return const _PanelStatus('Review spread', AppColors.statusError);
    }
    return const _PanelStatus('Watch spread', AppColors.statusWarning);
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

  Widget _buildUvTrayCard(int index, _UvTray tray, AuditProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tray ${index + 1}',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!provider.isReadOnly)
                IconButton(
                  tooltip: 'Delete tray',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => setState(() {
                    final removed = _uvTrays.removeAt(index);
                    removed.dispose();
                    _updateUvTrays(provider);
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: AuditNumericField(
              controller: tray.totalEggsController,
              enabled: !provider.isReadOnly,
              decoration: const InputDecoration(
                labelText: 'Total Eggs',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                tray.totalEggs = int.tryParse(value);
                _updateUvTrays(provider);
              }),
            ),
          ),
          const SizedBox(height: 12),
          _buildConditionCounter(
            label: 'Cuticle Damage',
            value: tray.cuticleDamage,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() {
              tray.cuticleDamage++;
              _updateUvTrays(provider);
            }),
            onDecrement: () => setState(() {
              if (tray.cuticleDamage > 0) tray.cuticleDamage--;
              _updateUvTrays(provider);
            }),
          ),
          const SizedBox(height: 6),
          _buildConditionCounter(
            label: 'Washed',
            value: tray.washed,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() {
              tray.washed++;
              _updateUvTrays(provider);
            }),
            onDecrement: () => setState(() {
              if (tray.washed > 0) tray.washed--;
              _updateUvTrays(provider);
            }),
          ),
          const SizedBox(height: 6),
          _buildConditionCounter(
            label: 'Dirty',
            value: tray.dirty,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() {
              tray.dirty++;
              _updateUvTrays(provider);
            }),
            onDecrement: () => setState(() {
              if (tray.dirty > 0) tray.dirty--;
              _updateUvTrays(provider);
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Affected: ${tray.affectedCount} eggs (${tray.affectedPct.toStringAsFixed(1)}%)',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getAffectedColor(tray.affectedPct),
                  ),
                ),
              ),
              PhotoButton(
                photoPath: tray.photoPath,
                enabled: !provider.isReadOnly,
                cameraFirst: true,
                onPhotoCaptured: (path) => setState(() {
                  tray.photoPath = path;
                  _updateUvTrays(provider);
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionCounter({
    required String label,
    required int value,
    required bool enabled,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: enabled ? onDecrement : null,
            icon: const Icon(Icons.remove, size: 16),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$value',
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w700,
            color: value > 0 ? AppColors.primary : AppTextStyles.caption.color,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: enabled ? onIncrement : null,
            icon: const Icon(Icons.add, size: 16),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.infoBg,
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUpsideDownTrayCard(
    int index,
    _UvTray tray,
    AuditProvider provider,
  ) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Tray ${index + 1}',
            style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w700),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: AuditNumericField(
              controller: tray.totalEggsController,
              enabled: !provider.isReadOnly,
              decoration: const InputDecoration(
                labelText: 'Total Eggs',
                border: OutlineInputBorder(),
              ),
              onChanged: (value) => setState(() {
                tray.totalEggs = int.tryParse(value);
                _updateUvTrays(provider);
              }),
            ),
          ),
          const SizedBox(height: 12),
          _buildConditionCounter(
            label: 'Upside Down',
            value: tray.upsideDown,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() {
              tray.upsideDown++;
              _updateUvTrays(provider);
            }),
            onDecrement: () => setState(() {
              if (tray.upsideDown > 0) tray.upsideDown--;
              _updateUvTrays(provider);
            }),
          ),
          const SizedBox(height: 10),
          Text(
            'Upside Down: ${tray.upsideDown} eggs (${tray.upsideDownPct.toStringAsFixed(1)}%)',
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.bold,
              color: _getAffectedColor(tray.upsideDownPct),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUniformitySummary() {
    final stats = _eggWeightStats();
    final storageDays = int.tryParse(_storageDaysController.text);
    final activeDraft = context.watch<AuditProvider>().activeDraft;
    final bmkAge =
        activeDraft.esEggBmkAge ?? _calculateEggStorageBmkAge(storageDays);
    final bmkWeight = _bmkEggWeight ?? activeDraft.esEggBmkWeight;

    final cards = [
      _SummaryMetric(
        'Avg Weight',
        stats == null ? '--' : '${stats.avg.toStringAsFixed(1)}g',
        AppColors.primary,
      ),
      _SummaryMetric(
        'BMK Age',
        bmkAge == null ? '--' : '$bmkAge wks',
        Colors.blueGrey,
      ),
      _SummaryMetric(
        'Sample Size',
        '${stats?.sampleSize ?? 0}/100',
        Colors.blueGrey,
      ),
      _SummaryMetric(
        'Min',
        stats == null ? '--' : '${stats.minRange.toStringAsFixed(1)}g',
        Colors.blueGrey,
      ),
      _SummaryMetric(
        'Max',
        stats == null ? '--' : '${stats.maxRange.toStringAsFixed(1)}g',
        Colors.blueGrey,
      ),
      _SummaryMetric(
        'Uniformity',
        stats == null ? '--' : '${stats.uniformity.toStringAsFixed(1)}%',
        stats == null ? Colors.blueGrey : _uniformityColor(stats.uniformity),
      ),
      _SummaryMetric(
        'C.V',
        stats == null ? '--' : '${stats.cv.toStringAsFixed(1)}%',
        stats == null
            ? Colors.blueGrey
            : stats.cv <= AppThresholds.cvAlertPct
            ? AppColors.greenTab
            : Colors.red,
      ),
      _SummaryMetric(
        'BMK Egg Weight',
        bmkWeight == null ? '--' : '${bmkWeight.toStringAsFixed(1)}g',
        Colors.blueGrey,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 560 ? 4 : 2;
        final spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (card) => SizedBox(
                  width: itemWidth,
                  child: _summCard(card.label, card.value, card.color),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<void> _openEggWeightSheet(AuditProvider provider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return AuditKeyboardDismiss(
              child: Padding(
                padding: EdgeInsets.only(
                  bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                ),
                child: DraggableScrollableSheet(
                  expand: false,
                  initialChildSize: 0.9,
                  minChildSize: 0.55,
                  maxChildSize: 0.95,
                  builder: (context, scrollController) {
                    return Column(
                      children: [
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                          child: Row(
                            children: [
                              Expanded(
                                child: Text(
                                  _eggWeightSheetTitle(provider),
                                  style: AppTextStyles.heading.copyWith(
                                    fontSize: 18,
                                  ),
                                ),
                              ),
                              IconButton(
                                tooltip: 'Close',
                                icon: const Icon(Icons.close),
                                onPressed: () => Navigator.pop(sheetContext),
                              ),
                            ],
                          ),
                        ),
                        Expanded(
                          child: SingleChildScrollView(
                            controller: scrollController,
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                            child: Column(
                              children: [
                                WeightGridWidget(
                                  controllers: _eggWeightControllers,
                                  focusNodes: _eggWeightFocusNodes,
                                  enabled: !provider.isReadOnly,
                                  mode: WeightsMode.egg,
                                  onChanged: () {
                                    if (!mounted || !sheetContext.mounted) {
                                      return;
                                    }
                                    _updateEggWeights(provider);
                                    setSheetState(() {});
                                  },
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _eggWeightSheetTitle(AuditProvider provider) {
    if (!provider.isCompareMode) return 'Egg Weight Sheet';
    final sample = provider.activeStationSample;
    final label = sample.houseNo ?? sample.sampleLabel;
    return '$label Egg Weight Sheet';
  }

  Widget _summCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  Color _uniformityColor(double uniformity) {
    if (uniformity < AppThresholds.uniformityPoor) return Colors.red;
    if (uniformity <= AppThresholds.uniformityGood) return Colors.orange;
    return AppColors.greenTab;
  }

  Color _getAffectedColor(double pct) => pct <= 5
      ? AppColors.greenTab
      : pct <= 10
      ? Colors.orange
      : Colors.red;

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

  void _handleEstBackAttempt() {
    final current = _estCaptureState;
    if (current == null) return;
    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    if (current.capturedImagePath == null) {
      if (!mounted) return;
      setState(() {
        _estCaptureState = current.stopAutoScan(message: 'Auto scan stopped.');
      });
      return;
    }

    _discardUnconfirmedEstPhoto(current);
    if (!mounted) return;
    setState(() {
      _isConfirmingEstCapture = false;
      _estGuidedValueController.clear();
      _estCaptureState = current.retake();
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

    final reading = await _ocrService.recognizeThermoScanReadingCelsius(
      sourcePath,
    );
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

    final reading = await _ocrService.recognizeThermoScanReadingCelsius(
      savedPath,
    );
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
      SnackBar(content: Text('EST capture saved $count readings.')),
    );
  }

  Future<bool> _prepareForStationExit() async {
    final current = _estCaptureState;
    if (current == null) return true;

    _nextEstCaptureGeneration();
    _cancelEstAutoScanTimer();
    _discardUnconfirmedEstPhoto(current);

    final inlineCamera = _estCameraKey.currentState;
    final shouldWaitForCamera =
        inlineCamera?.isCameraReady == true ||
        inlineCamera?.isPreviewActive == true;
    if (shouldWaitForCamera) {
      await inlineCamera!.closeCameraForStationExit().timeout(
        const Duration(milliseconds: 1500),
        onTimeout: () {},
      );
    } else {
      unawaited(inlineCamera?.closeCameraForStationExit());
    }

    if (!mounted) return true;
    setState(() {
      _estCaptureState = null;
      _estGuidedValueController.clear();
      _estHighlightedKey = null;
      _isConfirmingEstCapture = false;
      _estInlineCameraReady = false;
    });
    return true;
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

    final previousReadingsJson = provider.activeDraft.esEstReadingsJson;
    final previousPhotosJson = provider.activeDraft.esEstPhotosJson;
    final previousAvg = provider.activeDraft.esEstAvg;
    final previousCv = provider.activeDraft.esEstCv;
    final previousShellTemp = provider.activeDraft.esShellTemp;
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
    provider.updateField('es_estReadingsJson', previousReadingsJson);
    provider.updateField('es_estPhotosJson', previousPhotosJson);
    provider.updateField('es_estAvg', previousAvg);
    provider.updateField('es_estCv', previousCv);
    provider.updateField('esShellTemp', previousShellTemp);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Could not clear EST point. Try again.')),
    );
  }

  Future<void> _confirmSingleEstReading(
    AuditProvider provider,
    String key,
    String path,
  ) async {
    final reading = await _ocrService.recognizeThermoScanReadingCelsius(path);
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
                    suffixText: '°C',
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
      description: 'shell_temp',
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
    provider.updateField('es_estPhotosJson', jsonEncode(photos));
  }

  void _updateEstCalculations(AuditProvider provider) {
    final temps = _estControllers.values
        .map((c) => double.tryParse(c.text))
        .where((t) => t != null)
        .map((t) => t!)
        .toList();
    if (temps.isEmpty) {
      setState(() {
        _estAvgController.text = '';
        _estCvController.text = '';
      });
      provider.updateField('es_estAvg', null);
      provider.updateField('es_estCv', null);
      provider.updateField('esShellTemp', null);
    } else {
      final avg = CalculationUtils.average(temps);
      final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;
      setState(() {
        _estAvgController.text = avg.toStringAsFixed(1);
        _estCvController.text = cv.toStringAsFixed(1);
      });
      provider.updateField('es_estAvg', avg);
      provider.updateField('es_estCv', cv);
      provider.updateField('esShellTemp', avg);
    }
    final readings = <String, double>{};
    for (final entry in _estControllers.entries) {
      final value = double.tryParse(entry.value.text);
      if (value != null) readings[entry.key] = value;
    }
    provider.updateField(
      'es_estReadingsJson',
      readings.isEmpty ? null : jsonEncode(readings),
    );
  }

  void _updateUvTrays(AuditProvider provider) {
    provider.updateField(
      'esUvTrays',
      jsonEncode(_uvTrays.map((tray) => tray.toMap()).toList()),
    );
  }

  void _updateEggWeights(AuditProvider provider) {
    final allWeights = _eggWeightControllers
        .map((controller) => double.tryParse(controller.text))
        .toList();
    final weights = allWeights.whereType<double>().where((w) => w > 0).toList();

    provider.updateField('esEggWeights', jsonEncode(allWeights));
    provider.updateField('esEggSampleSize', weights.length);

    if (weights.isEmpty) {
      provider.updateField('esEggAvgWeight', null);
      provider.updateField('esEggUniformityPct', null);
      provider.updateField('esEggCvPct', null);
      if (mounted) setState(() {});
      return;
    }

    final avg = CalculationUtils.average(weights);
    final minRange = avg * 0.9;
    final maxRange = avg * 1.1;
    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      minRange,
      maxRange,
    );
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;

    provider.updateField('esEggAvgWeight', avg);
    provider.updateField('esEggUniformityPct', uniformity);
    provider.updateField('esEggCvPct', cv);
    if (mounted) setState(() {});
  }

  _ShellStorageTarget _shellStorageTarget(int? storageDays) {
    final days = storageDays ?? 0;
    if (days <= 4) {
      return const _ShellStorageTarget(
        label: 'Short storage',
        minC: 19,
        maxC: 21,
      );
    }
    if (days <= 7) {
      return const _ShellStorageTarget(
        label: 'Medium storage',
        minC: 18,
        maxC: 20,
      );
    }
    return const _ShellStorageTarget(label: 'Long storage', minC: 16, maxC: 18);
  }

  int? _calculateEggStorageBmkAge(int? storageDays) {
    final entryDate = widget.context.flockEntryDate;

    final auditDate = DateTime.tryParse(widget.context.date) ?? DateTime.now();
    return EggStorageBmkAge.calculateWeeks(
      flockEntryDate: entryDate,
      flockAgeWeeks: widget.context.flockAgeWeeks,
      auditDate: auditDate,
      storageDays: storageDays,
    );
  }

  Future<void> _syncEggStorageBmk(
    AuditProvider provider,
    int? storageDays,
  ) async {
    final bmkAge = _calculateEggStorageBmkAge(storageDays);
    provider.updateField('esEggBmkAge', bmkAge);

    final eggWeight = bmkAge == null
        ? null
        : await _lookupBmkEggWeight(widget.context.breed, bmkAge);
    if (!mounted) return;
    setState(() => _bmkEggWeight = eggWeight);
    provider.updateField('esEggBmkWeight', eggWeight);
  }

  Future<double?> _lookupBmkEggWeight(String? breed, int ageWeek) async {
    final normalizedBreed = _normalizeBreed(breed);
    if (normalizedBreed == null) return null;

    final db = await DatabaseHelper().db;
    final rows = await db.rawQuery(
      '''
      SELECT eggWeightG
      FROM bmk_breeds
      WHERE lower(replace(breed, ' ', '')) = ?
      ORDER BY ABS(ageWeek - ?) ASC
      LIMIT 1
      ''',
      [normalizedBreed, ageWeek],
    );
    if (rows.isEmpty) return null;
    return (rows.first['eggWeightG'] as num?)?.toDouble();
  }

  String? _normalizeBreed(String? breed) {
    final value = breed?.trim().toLowerCase().replaceAll(' ', '');
    return value == null || value.isEmpty ? null : value;
  }

  _EggWeightStats? _eggWeightStats() {
    final weights = _eggWeightControllers
        .map((controller) => double.tryParse(controller.text))
        .whereType<double>()
        .where((weight) => weight > 0)
        .toList();
    if (weights.isEmpty) return null;

    final avg = CalculationUtils.average(weights);
    final minRange = avg * 0.9;
    final maxRange = avg * 1.1;
    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      minRange,
      maxRange,
    );
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;

    return _EggWeightStats(
      sampleSize: weights.length,
      avg: avg,
      minRange: minRange,
      maxRange: maxRange,
      uniformity: uniformity,
      cv: cv,
    );
  }

  String _formatNumber(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    if (parsed == parsed.roundToDouble()) return parsed.toStringAsFixed(0);
    return parsed.toString();
  }
}

class _UvTray {
  int? totalEggs;
  int cuticleDamage = 0;
  int washed = 0;
  int dirty = 0;
  int upsideDown = 0;
  String? photoPath;
  late final TextEditingController totalEggsController;

  int get affectedCount => cuticleDamage + washed + dirty;

  _UvTray({
    this.totalEggs = 150,
    this.cuticleDamage = 0,
    this.washed = 0,
    this.dirty = 0,
    this.upsideDown = 0,
    this.photoPath,
  }) {
    totalEggsController = TextEditingController(
      text: totalEggs?.toString() ?? '',
    );
  }

  factory _UvTray.fromMap(Map<String, dynamic> map) {
    return _UvTray(
      totalEggs: _parseInt(map['totalEggs']),
      cuticleDamage: _parseInt(map['cuticleDamage']) ?? 0,
      washed: _parseInt(map['washed']) ?? 0,
      dirty: _parseInt(map['dirty']) ?? 0,
      upsideDown: _parseInt(map['upsideDown']) ?? 0,
      photoPath: map['photoPath'] as String?,
    );
  }

  double get affectedPct => totalEggs == null || totalEggs == 0
      ? 0.0
      : affectedCount / totalEggs! * 100;

  double get upsideDownPct =>
      totalEggs == null || totalEggs == 0 ? 0.0 : upsideDown / totalEggs! * 100;

  Map<String, dynamic> toMap() => {
    'totalEggs': totalEggs,
    'cuticleDamage': cuticleDamage,
    'washed': washed,
    'dirty': dirty,
    'upsideDown': upsideDown,
    'photoPath': photoPath,
  };

  void dispose() {
    totalEggsController.dispose();
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _ShellStorageTarget {
  final String label;
  final double minC;
  final double maxC;

  const _ShellStorageTarget({
    required this.label,
    required this.minC,
    required this.maxC,
  });

  String get rangeLabel => '${_formatTemp(minC)}-${_formatTemp(maxC)}°C';

  TemperatureStatus status(double tempC) {
    if (tempC < minC) return TemperatureStatus.low;
    if (tempC > maxC) return TemperatureStatus.high;
    return TemperatureStatus.optimal;
  }

  String zone(double tempC) {
    if (tempC < minC) return 'Low';
    if (tempC > maxC) return 'High';
    return 'Optimal';
  }

  static String _formatTemp(double temp) {
    return temp.toStringAsFixed(1);
  }
}

class _EggWeightStats {
  final int sampleSize;
  final double avg;
  final double minRange;
  final double maxRange;
  final double uniformity;
  final double cv;

  const _EggWeightStats({
    required this.sampleSize,
    required this.avg,
    required this.minRange,
    required this.maxRange,
    required this.uniformity,
    required this.cv,
  });
}

class _SummaryMetric {
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric(this.label, this.value, this.color);
}

class _PanelStatus {
  final String label;
  final Color color;

  const _PanelStatus(this.label, this.color);
}

enum _EstScanAction { confirm, retake, skip }
