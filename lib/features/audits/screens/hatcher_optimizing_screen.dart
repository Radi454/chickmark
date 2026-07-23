import 'dart:async';
import 'dart:convert';

import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/photo_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../../../data/repositories/photo_repository.dart';
import '../../../services/photo/photo_service.dart';
import '../models/est_grid_data.dart';
import '../models/temperature_entry_unit.dart';
import '../models/temperature_readings_payload.dart';
import '../temperature_capture/temperature_capture_config.dart';
import '../temperature_capture/temperature_capture_launcher.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_autosave_status.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/audit_scope_dialogs.dart';
import '../widgets/audit_station_scroll_view.dart';
import '../widgets/est_grid_widget.dart';
import '../widgets/photo_button.dart';
import '../widgets/temperature_unit_selector.dart';
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
    this.initialSectionIndex = 0,
  });
  @override
  State<HatcherOptimizingScreen> createState() =>
      _HatcherOptimizingScreenState();
}

class _HatcherOptimizingScreenState extends State<HatcherOptimizingScreen> {
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
  final TextEditingController _avgController = TextEditingController();
  final TextEditingController _cvController = TextEditingController();
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
  final TextEditingController _co2Controller = TextEditingController();
  bool? _chickPanting;
  String? _meconium;
  String? _cvtHighlightedKey;
  String? _activeAuditId;
  TemperatureEntryUnit _cvtUnit = TemperatureEntryUnit.fahrenheit;

  @override
  void initState() {
    super.initState();
    _hatcherIdController = TextEditingController(
      text: _hatcherNumberValue(
        widget.initialAudit?.hatcherId ??
            widget.initialAudit?.hoHatcherId ??
            widget.context.hatcherId,
      ),
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
    _co2Controller.text = _formatNumber(widget.initialAudit?.hoCo2);
    _chickPanting = widget.initialAudit?.hoChickPanting;
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
      existingAudits: widget.initialAudits,
      existingStationSamples: widget.initialStationSamples,
      readOnly: widget.context.sessionId == null ? null : false,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
      sessionId: widget.context.sessionId,
    );
    _syncActiveSampleForm(auditProvider.activeDraft);
    _activeAuditId = auditProvider.activeDraft.id;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialSection();
    });
  }

  void _syncActiveSampleForm(AuditModel audit) {
    if (_activeAuditId == audit.id) return;
    _activeAuditId = audit.id;
    _hatcherIdController.text = _hatcherNumberValue(
      audit.hatcherId ?? audit.hoHatcherId,
    );
    _incubationAgeController.text = (audit.hoIncubationAge ?? 18).toString();
    _incubationHoursController.text = (audit.hoIncubationHours ?? 0).toString();
    _setpointController.text = audit.hoSetpointF != null
        ? audit.hoSetpointF!.toStringAsFixed(1)
        : '';
    _setpointRhController.text = audit.hoSetpointRh != null
        ? audit.hoSetpointRh!.toStringAsFixed(1)
        : '';
    _co2Controller.text = _formatNumber(audit.hoCo2);
    _chickPanting = audit.hoChickPanting;
    _meconium = audit.hoMeconium;
    for (final controller in _controllers.values) {
      controller.clear();
    }
    for (final key in _photos.keys.toList()) {
      _photos[key] = null;
    }
    _cvtHighlightedKey = null;
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
    final payload = TemperatureReadingsPayload.decode(
      readingsJson,
      legacyUnit: TemperatureEntryUnit.fahrenheit,
    );
    _cvtUnit = payload.unit;
    for (final entry in payload.readings.entries) {
      _controllers[entry.key]?.text = entry.value.toStringAsFixed(1);
    }
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
    _scrollController.dispose();
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    for (final node in _focusNodes.values) {
      node.dispose();
    }
    _avgController.dispose();
    _cvController.dispose();
    _incubationAgeController.dispose();
    _incubationHoursController.dispose();
    _hatcherIdController.dispose();
    _setpointController.dispose();
    _setpointRhController.dispose();
    _co2Controller.dispose();
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
    auditProvider.updateField(
      'hoCvtReadings',
      TemperatureReadingsPayload(
        unit: _cvtUnit,
        readings: readings,
      ).toJsonString(),
    );
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
      if (value != null) {
        readings[key] = double.parse(value.toStringAsFixed(1));
      }
    }
    return readings;
  }

  Map<String, double> _currentCvtDisplayReadings() {
    final readings = <String, double>{};
    for (final key in EstGridData.scanKeys) {
      final value = double.tryParse(_controllers[key]?.text.trim() ?? '');
      if (value != null) readings[key] = value;
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
            child: AuditStationScrollView(
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
                      key: const ValueKey('hatcher-chick-panting-card'),
                      padding: const EdgeInsets.all(AppSizes.cardPadding),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Chick Panting',
                                  style: AppTextStyles.body.copyWith(
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                              PhotoButton(
                                key: const ValueKey(
                                  'hatcher-chick-panting-photo-button',
                                ),
                                photoPath: audit.hoChickPantingPhoto,
                                enabled: !auditProvider.isReadOnly,
                                fieldKey: 'chick_panting_photo',
                                onPhotoCaptured: (p) => auditProvider
                                    .updateField('hoChickPantingPhoto', p),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              _buildPantingChoice(
                                provider: auditProvider,
                                value: false,
                                label: 'No',
                              ),
                              _buildPantingChoice(
                                provider: auditProvider,
                                value: true,
                                label: 'Yes',
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
    return _buildHatcherSampleControlCard(
      key: const ValueKey('hatcher-machine-scope-card'),
      title: 'Machine scope',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHatcherMachineScopeChips(provider),
          const SizedBox(height: 12),
          _buildHatcherNumberField(provider),
        ],
      ),
    );
  }

  Widget _buildHatcherSampleControlCard({
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

  Widget _buildHatcherMachineScopeChips(AuditProvider provider) {
    final chips = [
      for (final entry in provider.drafts.asMap().entries)
        _buildHatcherScopeChip(
          label: _hatcherTabLabel(entry.value, entry.key),
          selected: provider.activeSampleIndex == entry.key,
          enabled: !provider.isReadOnly,
          onSelected: () => _switchHatcherSample(provider, entry.key),
        ),
    ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHatcherSampleActionButton(
          tooltip: context.tr('Add machine sample'),
          icon: Icons.add,
          onPressed: provider.isReadOnly
              ? null
              : () => _addHatcherMachineSample(provider),
        ),
        if (provider.sampleCount > 1) ...[
          const SizedBox(width: 8),
          _buildHatcherSampleActionButton(
            tooltip: context.tr('Remove active machine sample'),
            icon: Icons.remove,
            onPressed: provider.isReadOnly
                ? null
                : () => _removeActiveHatcherSample(provider),
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

  Widget _buildHatcherScopeChip({
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

  Widget _buildHatcherSampleActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      tooltip: context.tr(tooltip),
      onPressed: onPressed,
      icon: Icon(icon),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }

  Future<void> _addHatcherMachineSample(AuditProvider provider) async {
    final values = await showAuditScopeIdentityDialog(
      context,
      scopeLabel: 'Machine',
      fields: const [AuditScopeIdentityField(key: 'hatcher', label: 'Hatcher')],
      validator: (values) => _hasDuplicateHatcher(provider, values['hatcher']!)
          ? 'A Machine scope with this identity already exists.'
          : null,
    );
    if (values == null || !mounted) return;
    final hatcher = values['hatcher']!;
    provider.addSample();
    provider.updateField('hatcherId', hatcher);
    provider.updateField('hoHatcherId', hatcher);
    setState(() {
      _syncActiveSampleForm(provider.activeDraft);
    });
  }

  bool _hasDuplicateHatcher(AuditProvider provider, String hatcher) {
    final normalized = normalizeAuditScopeIdentity(hatcher, prefix: 'H');
    return provider.drafts.any(
      (draft) =>
          normalizeAuditScopeIdentity(
            draft.hatcherId ?? draft.hoHatcherId ?? '',
            prefix: 'H',
          ) ==
          normalized,
    );
  }

  void _switchHatcherSample(AuditProvider provider, int index) {
    provider.switchSample(index);
    if (!mounted) return;
    setState(() {
      _syncActiveSampleForm(provider.activeDraft);
    });
  }

  Future<void> _removeActiveHatcherSample(AuditProvider provider) async {
    final confirmed = await confirmAuditScopeRemoval(
      context,
      hasEnteredResults: provider.stationScopeHasEnteredResults(
        provider.activeSampleIndex,
      ),
    );
    if (!confirmed || !mounted) return;
    provider.removeActiveSample();
    setState(() {
      _syncActiveSampleForm(provider.activeDraft);
    });
  }

  Widget _buildHatcherNumberField(AuditProvider provider) {
    return TextField(
      key: const ValueKey('hatcher-machine-scope-number-field'),
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
    );
  }

  Widget _buildPantingChoice({
    required AuditProvider provider,
    required bool value,
    required String label,
  }) {
    final selected = _chickPanting == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: provider.isReadOnly
          ? null
          : (_) {
              setState(() => _chickPanting = value);
              provider.updateField('hoChickPanting', value ? 1 : 0);
            },
      selectedColor: AppColors.primary.withAlpha(30),
      checkmarkColor: AppColors.primary,
      labelStyle: AppTextStyles.body.copyWith(
        color: selected ? AppColors.primary : AppColors.textBody,
        fontWeight: selected ? FontWeight.w800 : FontWeight.w600,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.borderDefault,
        ),
      ),
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
            Row(
              children: [
                Expanded(
                  child: AuditNumericField(
                    key: const ValueKey('hatcher-incubation-age-field'),
                    controller: _incubationAgeController,
                    enabled: !provider.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: 'Incubation Age (days)',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) => _updateIncubationAge(provider, value),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: AuditNumericField(
                    key: const ValueKey('hatcher-incubation-hours-field'),
                    controller: _incubationHoursController,
                    enabled: !provider.isReadOnly,
                    decoration: const InputDecoration(
                      labelText: 'Incubation Hours',
                      border: OutlineInputBorder(),
                    ),
                    onChanged: (value) =>
                        _updateIncubationHours(provider, value),
                  ),
                ),
              ],
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
                key: const ValueKey('hatcher-co2-field'),
                controller: _co2Controller,
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
              fieldKey: 'co2_photo',
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
                TemperatureUnitSelector(
                  value: _cvtUnit,
                  keyPrefix: 'hatcher-cvt',
                  enabled: !provider.isReadOnly,
                  onChanged: _setCvtUnit,
                ),
                const SizedBox(width: 8),
                OutlinedButton.icon(
                  onPressed: provider.isReadOnly
                      ? null
                      : () => _openCvtCapture(provider),
                  icon: const Icon(Icons.document_scanner_outlined),
                  label: const Text('Capture readings'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            EstGridWidget(
              key: const ValueKey('hatcher-cvt-temperature-grid'),
              controllers: _controllers,
              focusNodes: _focusNodes,
              photos: _photos,
              enabled: false,
              highlightedKey: _cvtHighlightedKey,
              showPhotoCapture: false,
              displayOnly: true,
              title: null,
              unitSuffix: _cvtUnit.suffix,
              tempStatusFn: (value) => CalculationUtils.cvtStatus(
                _cvtUnit.toCanonical(
                  value,
                  canonicalUnit: TemperatureEntryUnit.fahrenheit,
                ),
              ),
              tempZoneFn: (value) => CalculationUtils.cvtZone(
                _cvtUnit.toCanonical(
                  value,
                  canonicalUnit: TemperatureEntryUnit.fahrenheit,
                ),
              ),
              onValueChanged: (_, _) {
                _updateCalculations();
                if (mounted) setState(() {});
              },
              onPhotoCaptured: (_, _) {},
              onCellSelected: provider.isReadOnly
                  ? null
                  : (key) => _openCvtCapture(provider, initialKey: key),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: _summaryCard(
                    'AVG',
                    _avgController.text.isEmpty
                        ? '--'
                        : '${_displayCvtAverage()}${_cvtUnit.suffix}',
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

  String _hatcherTabLabel(AuditModel audit, int index) {
    final raw = (audit.hatcherId ?? audit.hoHatcherId ?? '').trim();
    if (raw.isEmpty) return 'H';
    final digits = RegExp(r'\d+').allMatches(raw).map((m) => m.group(0)).join();
    if (digits.isNotEmpty) return 'H$digits';
    final withoutPrefix = raw.toLowerCase().startsWith('h')
        ? raw.substring(1).trim()
        : raw;
    return 'H$withoutPrefix';
  }

  String _hatcherNumberValue(String? value) {
    final raw = (value ?? '').trim();
    return raw.isEmpty ? 'H' : raw;
  }

  String _formatNumber(double? value) {
    if (value == null) return '';
    if (value == value.roundToDouble()) return value.toInt().toString();
    return value.toString();
  }

  void _updateIncubationAge(AuditProvider provider, String value) {
    final parsed = int.tryParse(value);
    if (parsed == null) {
      if (mounted) setState(() {});
      return;
    }
    final age = parsed.clamp(18, 21).toInt();
    _replaceControllerTextIfNeeded(_incubationAgeController, age.toString());
    provider.updateField('hoIncubationAge', age);
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
    provider.updateField('hoIncubationHours', hours);
    if (mounted) setState(() {});
  }

  void _replaceControllerTextIfNeeded(
    TextEditingController controller,
    String value,
  ) {
    if (controller.text == value) return;
    controller
      ..text = value
      ..selection = TextSelection.collapsed(offset: value.length);
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

  /// Launch the reusable full-screen capture flow, pre-populated
  /// with the current grid, then merge confirmed readings via [_saveCvtPoint]
  /// (+ evidence photo records). Persistence + sync unchanged.
  Future<void> _openCvtCapture(
    AuditProvider provider, {
    String? initialKey,
  }) async {
    if (provider.isReadOnly) return;
    final result = await TemperatureCaptureLauncher.push(
      context,
      TemperatureCaptureConfig(
        title: 'Chick Vent Temperature',
        unitSuffix: _cvtUnit.suffix,
        initialKey: initialKey,
        initialReadings: _currentCvtDisplayReadings(),
        initialPhotos: _currentCvtPhotoPaths(),
        tempStatusFn: (value) => CalculationUtils.cvtStatus(
          _cvtUnit.toCanonical(
            value,
            canonicalUnit: TemperatureEntryUnit.fahrenheit,
          ),
        ),
        tempZoneFn: (value) => CalculationUtils.cvtZone(
          _cvtUnit.toCanonical(
            value,
            canonicalUnit: TemperatureEntryUnit.fahrenheit,
          ),
        ),
        targetLabelBuilder: _cvtTargetLabel,
        readOnly: provider.isReadOnly,
      ),
      photoService: _photoService,
    );
    if (result == null || result.isEmpty || !mounted) return;
    TemperatureCaptureLauncher.apply(result, (key, path, value) {
      _saveCvtPoint(key, path, value);
      if (path.isNotEmpty) {
        unawaited(_saveCvtEvidencePhotoRecord(provider, key, path));
      }
    });
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Saved ${result.readings.length} CVT readings.')),
    );
  }

  void _saveCvtPoint(String key, String path, double valueF) {
    setState(() {
      _photos[key] = path;
      _controllers[key]?.text = valueF.toStringAsFixed(1);
    });
    _updateCalculations();
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

  void _setCvtUnit(TemperatureEntryUnit unit) {
    if (_cvtUnit == unit) return;
    final previousUnit = _cvtUnit;
    setState(() {
      for (final controller in _controllers.values) {
        final value = double.tryParse(controller.text);
        if (value != null) {
          controller.text = previousUnit
              .convert(value, unit)
              .toStringAsFixed(1);
        }
      }
      _cvtUnit = unit;
    });
    _updateCalculations();
  }

  String _displayCvtAverage() {
    final average = double.tryParse(_avgController.text);
    if (average == null) return '--';
    return average.toStringAsFixed(1);
  }

  String _cvtTargetLabel(String key) {
    final parts = key.split('_');
    if (parts.length != 2) return key;
    return '${EstGridData.label(parts[0])} - ${EstGridData.label(parts[1])}';
  }
}
