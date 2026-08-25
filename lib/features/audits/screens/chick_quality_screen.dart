import 'dart:async';
import 'dart:convert';

import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/database/database_helper.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_autosave_status.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/audit_scope_dialogs.dart';
import '../widgets/audit_station_scroll_view.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/weight_entry_sheet_scroll_view.dart';
import '../widgets/weight_grid_widget.dart';
import '../widgets/tabs/cvt_tab.dart';
import '../widgets/tabs/culled_chicks_analysis_tab.dart';
import '../widgets/tabs/pasgar_tab.dart';
import '../widgets/tabs/pm_necropsy_tab.dart';
import '../widgets/tabs/yfbm_tab.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

typedef ChickBmkWeightLookup =
    Future<double?> Function(String? breed, int ageWeek);

class ChickQualityScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final List<AuditModel> initialAudits;
  final List<StationSampleModel> initialStationSamples;
  final int initialTabIndex;
  final ChickBmkWeightLookup? bmkChickWeightLookup;

  const ChickQualityScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialAudits = const [],
    this.initialStationSamples = const [],
    this.initialTabIndex = 0,
    this.bmkChickWeightLookup,
  });

  @override
  State<ChickQualityScreen> createState() => _ChickQualityScreenState();
}

class _ChickQualityScreenState extends State<ChickQualityScreen> {
  static const double _wideWorkbenchBreakpoint = 980;
  static const Duration _weightUpdateDebounceDuration = Duration(
    milliseconds: 350,
  );

  final List<TextEditingController> _weightControllers = List.generate(
    100,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _weightFocusNodes = List.generate(
    100,
    (_) => FocusNode(),
  );
  String? _loadedWeightsAuditId;
  Timer? _weightUpdateDebounce;
  bool _hasPendingWeightUpdate = false;
  double? _bmkChickWeight;
  int _bmkLookupGeneration = 0;

  @override
  void initState() {
    super.initState();

    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    final auditContext = AuditContext(
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
    _bmkChickWeight = auditProvider.activeDraft.chickBmkWeight;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _syncCurrentChickWeightBmk(auditProvider);
    });
  }

  @override
  void dispose() {
    _weightUpdateDebounce?.cancel();
    for (final controller in _weightControllers) {
      controller.dispose();
    }
    for (final node in _weightFocusNodes) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();
    final audit = auditProvider.activeDraft;
    _syncWeightControllers(auditProvider, audit);

    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Chicks',
                toolbarHeight: 76,
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
            child: Column(
              children: [
                Expanded(
                  child: AuditStationScrollView(
                    scrollKey: const ValueKey('chick-quality-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HeaderCard(contextData: widget.context),
                            if (auditProvider
                                    .registryValidationWarnings
                                    .isNotEmpty ||
                                auditProvider
                                    .persistedChickQualityFlags
                                    .isNotEmpty) ...[
                              const SizedBox(height: 12),
                              const _ChickQualityAdvisoryBanner(),
                            ],
                            const SizedBox(height: 16),
                            _buildWorkbench(context, auditProvider, audit),
                          ],
                        ),
                      ),
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

  Widget _buildWorkbench(
    BuildContext context,
    AuditProvider provider,
    AuditModel audit,
  ) {
    final activeQualitySampleMeta = provider.isCompareMode
        ? '${provider.activeStationSample.sampleLabel} setter/hatcher sample'
        : '';
    final leftColumn = Column(
      children: [
        _StationPanel(
          key: const ValueKey('chick-quality-machine-sampling'),
          title: 'Chick Quality',
          meta: 'Setter/hatcher sample scope',
          status: provider.isCompareMode ? 'Compare' : 'Single',
          showHeader: false,
          child: _MachineSampleControls(provider: provider),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-pasgar'),
          title: 'Pasgar Score',
          meta: activeQualitySampleMeta,
          collapsible: true,
          child: PasgarTab(
            key: ValueKey('pasgar-${audit.id}'),
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-yfbm'),
          title: 'YFBM',
          meta: activeQualitySampleMeta,
          collapsible: true,
          child: YfbmTab(
            key: ValueKey('yfbm-${audit.id}'),
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-cvt'),
          title: 'Chick Vent Temperature',
          meta: activeQualitySampleMeta,
          collapsible: true,
          child: CvtTab(
            key: ValueKey('cvt-${audit.id}'),
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-pm'),
          title: 'PM Necropsy',
          meta: activeQualitySampleMeta,
          collapsible: true,
          child: PmNecropsyTab(
            key: ValueKey('pm-${audit.id}'),
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-culled-analysis'),
          title: 'Culled Chicks Analysis',
          meta: activeQualitySampleMeta,
          collapsible: true,
          child: CulledChicksAnalysisTab(
            key: ValueKey('culled-${audit.id}'),
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
      ],
    );

    final rightColumn = Column(
      children: [
        _StationPanel(
          key: const ValueKey('chick-quality-panel-weights'),
          showHeader: false,
          child: _ChickWeightsPanel(
            contextData: widget.context,
            provider: provider,
            audit: audit,
            bmkChickWeight: _bmkChickWeight,
            weightControllers: _weightControllers,
            weightFocusNodes: _weightFocusNodes,
            onWeightsChanged: _updateWeightCalculations,
            onOpenWeightSheet: () => _openWeightSheet(provider),
          ),
        ),
      ],
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth >= _wideWorkbenchBreakpoint;
        if (!isWide) {
          return Column(
            key: const ValueKey('chick-quality-workbench'),
            children: [leftColumn, const SizedBox(height: 16), rightColumn],
          );
        }

        return Row(
          key: const ValueKey('chick-quality-workbench'),
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(flex: 96, child: leftColumn),
            const SizedBox(width: 16),
            Expanded(flex: 104, child: rightColumn),
          ],
        );
      },
    );
  }

  Future<void> _openWeightSheet(AuditProvider provider) async {
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
          builder: (sheetContext, _) {
            return AuditKeyboardDismiss(
              enabled: false,
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
                    return Container(
                      key: const ValueKey('chick-quality-weight-sheet'),
                      clipBehavior: Clip.antiAlias,
                      decoration: const BoxDecoration(
                        color: AppColors.surface,
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(18),
                        ),
                      ),
                      child: Column(
                        children: [
                          Padding(
                            padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    _chickWeightSheetTitle(provider),
                                    style: AppTextStyles.heading.copyWith(
                                      fontSize: 18,
                                    ),
                                  ),
                                ),
                                IconButton(
                                  tooltip: context.tr('Close'),
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close),
                                ),
                              ],
                            ),
                          ),
                          Expanded(
                            child: WeightEntrySheetScrollView(
                              controller: scrollController,
                              child: KeyedSubtree(
                                key: const ValueKey('weight-grid-widget'),
                                child: WeightGridWidget(
                                  controllers: _weightControllers,
                                  focusNodes: _weightFocusNodes,
                                  enabled: !provider.isReadOnly,
                                  mode: WeightsMode.egg,
                                  onChanged: () {
                                    if (!mounted || !sheetContext.mounted) {
                                      return;
                                    }
                                    _scheduleWeightCalculationUpdate();
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
    if (mounted) {
      _flushPendingWeightUpdate();
    }
  }

  String _chickWeightSheetTitle(AuditProvider provider) {
    if (!provider.isChickWeightCompareMode) return 'Chick Weight Sheet';
    final sample = provider.activeChickWeightSample;
    final label = sample.houseNo ?? sample.sampleLabel;
    return '$label Chick Weight Sheet';
  }

  void _syncWeightControllers(AuditProvider provider, AuditModel audit) {
    final weightSampleId = provider.chickWeightSamples.isEmpty
        ? audit.id
        : provider.activeChickWeightSample.id;
    if (_loadedWeightsAuditId == weightSampleId) return;
    for (final controller in _weightControllers) {
      controller.text = '';
    }

    final sampleWeights = provider.chickWeightSamples.isEmpty
        ? null
        : _weightsFromSample(provider.activeChickWeightSample);
    if (sampleWeights != null) {
      for (
        var i = 0;
        i < sampleWeights.length && i < _weightControllers.length;
        i++
      ) {
        final value = sampleWeights[i];
        _weightControllers[i].text = value == null ? '' : value.toString();
      }
    } else if (!provider.isChickWeightCompareMode &&
        audit.chickWeights != null &&
        audit.chickWeights!.isNotEmpty) {
      try {
        final decoded = jsonDecode(audit.chickWeights!);
        if (decoded is List) {
          for (
            var i = 0;
            i < decoded.length && i < _weightControllers.length;
            i++
          ) {
            final value = decoded[i];
            _weightControllers[i].text = value == null ? '' : value.toString();
          }
        }
      } catch (_) {
        // Keep an empty editable grid when legacy JSON is malformed.
      }
    }
    _loadedWeightsAuditId = weightSampleId;
  }

  void _scheduleWeightCalculationUpdate() {
    _hasPendingWeightUpdate = true;
    _weightUpdateDebounce?.cancel();
    _weightUpdateDebounce = Timer(_weightUpdateDebounceDuration, () {
      if (!mounted) return;
      _flushPendingWeightUpdate();
    });
  }

  void _flushPendingWeightUpdate() {
    if (!_hasPendingWeightUpdate) return;
    _weightUpdateDebounce?.cancel();
    _weightUpdateDebounce = null;
    _hasPendingWeightUpdate = false;
    _updateWeightCalculations();
  }

  void _updateWeightCalculations() {
    final provider = context.read<AuditProvider>();
    final weights = _weightControllers
        .map((controller) => double.tryParse(controller.text))
        .where((weight) => weight != null && weight > 0)
        .map((weight) => weight!)
        .toList();

    if (weights.isEmpty) {
      provider.updateChickWeightSampleResult(weightsJson: jsonEncode(weights));
      return;
    }

    final avg = CalculationUtils.average(weights);
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;
    final minRange = avg * 0.9;
    final maxRange = avg * 1.1;
    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      minRange,
      maxRange,
    );

    provider.updateChickWeightSampleResult(
      weightsJson: jsonEncode(weights),
      avgWeight: avg,
      uniformityPct: uniformity,
      cvPct: cv,
    );
  }

  List<dynamic>? _weightsFromSample(StationSampleModel sample) {
    final summaryJson = sample.resultSummaryJson;
    if (summaryJson == null || summaryJson.isEmpty) return null;
    try {
      final decoded = jsonDecode(summaryJson);
      if (decoded is Map && decoded['chickWeights'] is List) {
        return decoded['chickWeights'] as List<dynamic>;
      }
    } catch (_) {
      return null;
    }
    return null;
  }

  void _syncCurrentChickWeightBmk(AuditProvider provider) {
    unawaited(_syncChickWeightBmk(provider));
  }

  Future<void> _syncChickWeightBmk(AuditProvider provider) async {
    final generation = ++_bmkLookupGeneration;
    final bmkAge = _chickBmkAgeForContext();
    final draft = provider.activeDraft;
    if (draft.chickBmkAge != bmkAge) {
      provider.updateField('chickBmkAge', bmkAge);
    }

    if (bmkAge == null) {
      if (mounted) setState(() => _bmkChickWeight = null);
      if (provider.activeDraft.chickBmkWeight != null) {
        provider.updateField('chickBmkWeight', null);
      }
      return;
    }

    final chickWeight = await _lookupBmkChickWeight(
      _firstText(widget.context.breed, draft.soBreed, draft.hoBreed),
      bmkAge,
    );
    if (!mounted || generation != _bmkLookupGeneration) return;
    setState(() => _bmkChickWeight = chickWeight);
    if (provider.activeDraft.chickBmkWeight != chickWeight) {
      provider.updateField('chickBmkWeight', chickWeight);
    }
  }

  int? _chickBmkAgeForContext() {
    final age = widget.context.flockAgeWeeks;
    return age == null || age <= 0 ? null : age;
  }

  Future<double?> _lookupBmkChickWeight(String? breed, int ageWeek) async {
    final injectedLookup = widget.bmkChickWeightLookup;
    if (injectedLookup != null) {
      return injectedLookup(breed, ageWeek);
    }

    final normalizedBreed = _normalizeBreed(breed);
    if (normalizedBreed == null) return null;

    try {
      final db = await DatabaseHelper().db;
      final rows = await db.rawQuery(
        '''
        SELECT chickWeightG
        FROM bmk_breeds
        WHERE lower(replace(breed, ' ', '')) = ?
        ORDER BY ABS(ageWeek - ?) ASC
        LIMIT 1
        ''',
        [normalizedBreed, ageWeek],
      );
      if (rows.isEmpty) return null;
      return (rows.first['chickWeightG'] as num?)?.toDouble();
    } catch (_) {
      return null;
    }
  }

  String? _normalizeBreed(String? breed) {
    final value = breed?.trim().toLowerCase().replaceAll(' ', '');
    return value == null || value.isEmpty ? null : value;
  }

  String? _firstText(String? first, String? second, String? third) {
    for (final value in [first, second, third]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

class _ChickQualityAdvisoryBanner extends StatelessWidget {
  const _ChickQualityAdvisoryBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chick-quality-advisory-banner'),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: AppColors.statusWarning.withValues(alpha: 0.45),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.info_outline,
            color: AppColors.statusWarning,
            size: 20,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              context.tr(
                'Review data quality. Registry checks need attention; save is still allowed.',
              ),
              style: const TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}

class _HeaderCard extends StatelessWidget {
  final AuditContextData contextData;

  const _HeaderCard({required this.contextData});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chick-quality-header-card'),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
        boxShadow: const [
          BoxShadow(
            color: Color(0x14111827),
            blurRadius: 28,
            offset: Offset(0, 16),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Audit station',
            style: AppTextStyles.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.78),
              fontWeight: FontWeight.w900,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Chick quality',
            style: AppTextStyles.heading.copyWith(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          _HeaderContextTile(
            label: 'Hatchery',
            value: contextData.hatcheryId?.isNotEmpty == true
                ? contextData.hatcheryId!
                : 'Main Hatchery',
          ),
        ],
      ),
    );
  }
}

class _HeaderContextTile extends StatelessWidget {
  final String label;
  final String value;

  const _HeaderContextTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: AppTextStyles.caption.copyWith(
              color: Colors.white.withValues(alpha: 0.72),
              fontWeight: FontWeight.w800,
              letterSpacing: 0,
            ),
          ),
          const SizedBox(height: 5),
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
    );
  }
}

class _StationPanel extends StatelessWidget {
  final String title;
  final String meta;
  final String status;
  final Widget child;
  final bool showHeader;
  final bool collapsible;

  const _StationPanel({
    super.key,
    this.title = '',
    this.meta = '',
    this.status = '',
    required this.child,
    this.showHeader = true,
    this.collapsible = false,
  });

  @override
  Widget build(BuildContext context) {
    final panelPadding = MediaQuery.sizeOf(context).width < 560 ? 14.0 : 16.0;
    final decoration = BoxDecoration(
      color: AppColors.surface,
      borderRadius: BorderRadius.circular(12),
      border: Border.all(color: AppColors.borderDefault),
      boxShadow: const [
        BoxShadow(
          color: Color(0x0F111827),
          blurRadius: 24,
          offset: Offset(0, 10),
        ),
      ],
    );

    if (showHeader && collapsible) {
      return Container(
        width: double.infinity,
        decoration: decoration,
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: Theme(
            data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
            child: ExpansionTile(
              tilePadding: EdgeInsets.all(panelPadding),
              childrenPadding: EdgeInsets.fromLTRB(
                panelPadding,
                0,
                panelPadding,
                panelPadding,
              ),
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: AppTextStyles.title.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (meta.trim().isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(meta, style: AppTextStyles.caption),
                  ],
                ],
              ),
              trailing: const Icon(Icons.expand_more),
              children: [child],
            ),
          ),
        ),
      );
    }

    return Container(
      width: double.infinity,
      decoration: decoration,
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            Padding(
              padding: EdgeInsets.all(panelPadding),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style: AppTextStyles.title.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        if (meta.trim().isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(meta, style: AppTextStyles.caption),
                        ],
                      ],
                    ),
                  ),
                  _StatusPill(label: status),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(padding: EdgeInsets.all(panelPadding), child: child),
        ],
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;

  const _StatusPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.statusGoodBg,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.statusGood,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;

  const _GradientIcon(this.icon, {this.size = 18});

  @override
  Widget build(BuildContext context) {
    return ShaderMask(
      blendMode: BlendMode.srcIn,
      shaderCallback: AppColors.brandGradient.createShader,
      child: Icon(icon, size: size, color: Colors.white),
    );
  }
}

class _ChickWeightsPanel extends StatelessWidget {
  final AuditContextData contextData;
  final AuditProvider provider;
  final AuditModel audit;
  final double? bmkChickWeight;
  final List<TextEditingController> weightControllers;
  final List<FocusNode> weightFocusNodes;
  final VoidCallback onWeightsChanged;
  final VoidCallback onOpenWeightSheet;

  const _ChickWeightsPanel({
    required this.contextData,
    required this.provider,
    required this.audit,
    required this.bmkChickWeight,
    required this.weightControllers,
    required this.weightFocusNodes,
    required this.onWeightsChanged,
    required this.onOpenWeightSheet,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _WeightStats.fromControllers(weightControllers);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FlockCard(contextData: contextData, audit: audit, stats: stats),
        const SizedBox(height: 12),
        _HouseWeightSampleControls(provider: provider),
        const SizedBox(height: 12),
        _MetricGrid(audit: audit, stats: stats, bmkChickWeight: bmkChickWeight),
        const SizedBox(height: 14),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: OutlinedButton.icon(
            onPressed: onOpenWeightSheet,
            icon: const Icon(Icons.scale_outlined, size: 18),
            label: const Text('Enter Weights'),
          ),
        ),
      ],
    );
  }
}

class _FlockCard extends StatelessWidget {
  final AuditContextData contextData;
  final AuditModel audit;
  final _WeightStats stats;

  const _FlockCard({
    required this.contextData,
    required this.audit,
    required this.stats,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Chick Weights & Uniformity',
            style: AppTextStyles.heading.copyWith(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 14),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 420;
              final tiles = [
                _FlockInfo(label: 'Flock', value: contextData.flockId),
                _FlockInfo(
                  label: 'Breed',
                  value:
                      _firstText(
                        contextData.breed,
                        audit.soBreed,
                        audit.hoBreed,
                      ) ??
                      '--',
                ),
                _FlockInfo(label: 'BMK Age', value: _bmkAgeLabel),
              ];
              if (!isWide) {
                return _FlockContextStrip(
                  vertical: true,
                  children: [for (final tile in tiles) tile],
                );
              }
              return _FlockContextStrip(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    Expanded(child: tiles[i]),
                    if (i < tiles.length - 1) const _FlockContextDivider(),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  String get _bmkAgeLabel {
    final contextAge = contextData.flockAgeWeeks;
    final bmkAge = contextAge != null && contextAge > 0
        ? contextAge
        : audit.chickBmkAge;
    return bmkAge == null ? '--' : '$bmkAge wks';
  }

  String? _firstText(String? first, String? second, String? third) {
    for (final value in [first, second, third]) {
      final trimmed = value?.trim();
      if (trimmed != null && trimmed.isNotEmpty) return trimmed;
    }
    return null;
  }
}

class _FlockContextStrip extends StatelessWidget {
  final List<Widget> children;
  final bool vertical;

  const _FlockContextStrip({required this.children, this.vertical = false});

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('chick-weight-context-strip'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
      ),
      child: vertical
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  children[i],
                  if (i < children.length - 1) const SizedBox(height: 10),
                ],
              ],
            )
          : Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: children,
            ),
    );
  }
}

class _FlockContextDivider extends StatelessWidget {
  const _FlockContextDivider();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 1,
      height: 40,
      margin: const EdgeInsets.symmetric(horizontal: 10),
      color: Colors.white.withValues(alpha: 0.16),
    );
  }
}

class _FlockInfo extends StatelessWidget {
  final String label;
  final String value;

  const _FlockInfo({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(
            color: Colors.white.withValues(alpha: 0.72),
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
    );
  }
}

class _HouseWeightSampleControls extends StatefulWidget {
  final AuditProvider provider;

  const _HouseWeightSampleControls({required this.provider});

  @override
  State<_HouseWeightSampleControls> createState() =>
      _HouseWeightSampleControlsState();
}

class _HouseWeightSampleControlsState
    extends State<_HouseWeightSampleControls> {
  final Map<String, TextEditingController> _identityControllers = {};
  final Map<String, FocusNode> _identityFocusNodes = {};

  AuditProvider get provider => widget.provider;

  @override
  void dispose() {
    for (final controller in _identityControllers.values) {
      controller.dispose();
    }
    for (final node in _identityFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _pruneIdentityFields(provider.chickWeightSamples);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSampleControlCard(
          title: 'House scope',
          child: _buildHouseSampleChips(),
        ),
      ],
    );
  }

  Widget _buildSampleControlCard({
    String? title,
    String? note,
    required Widget child,
  }) {
    final hasHeader = title != null || note != null;
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
          if (hasHeader) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (note != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      note,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildScopeInputFields(List<Widget> fields) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (fields.length == 1) return fields.single;
        return Row(
          children: [
            for (var i = 0; i < fields.length; i++) ...[
              Expanded(child: fields[i]),
              if (i < fields.length - 1) const SizedBox(width: 10),
            ],
          ],
        );
      },
    );
  }

  Widget _buildHouseSampleChips() {
    final active = provider.isChickWeightCompareMode;
    final chips = active
        ? [
            for (final entry in provider.chickWeightSamples.asMap().entries)
              _buildHouseSampleChip(
                label: entry.value.sampleLabel,
                selected: entry.key == provider.activeChickWeightSampleIndex,
                enabled: !provider.isReadOnly,
                onSelected: () => provider.switchChickWeightSample(entry.key),
              ),
          ]
        : [
            _buildHouseSampleChip(
              label: 'Pool',
              selected: true,
              enabled: false,
              onSelected: null,
            ),
          ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildHouseSampleActionButton(
          tooltip: context.tr('Add house sample'),
          icon: Icons.add,
          onPressed: provider.isReadOnly
              ? null
              : () => _addChickWeightHouseSample(),
        ),
        if (active) ...[
          const SizedBox(width: 8),
          _buildHouseSampleActionButton(
            tooltip: context.tr('Remove active house sample'),
            icon: Icons.remove,
            onPressed: provider.isReadOnly
                ? null
                : () => _removeActiveChickWeightHouseSample(),
          ),
        ],
      ],
    );

    final chipRow = LayoutBuilder(
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
    if (!active) return chipRow;
    final sample = provider.activeChickWeightSample;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chipRow,
        const SizedBox(height: 10),
        _buildScopeInputFields([
          TextFormField(
            key: ValueKey('chick-weight-house-${sample.id}'),
            controller: _identityController(sample),
            focusNode: _identityFocusNode(sample),
            enabled: !provider.isReadOnly,
            textInputAction: TextInputAction.done,
            decoration: _scopeInputDecoration('House'),
            onChanged: (value) {
              provider.updateChickWeightSampleMetadata({
                'houseNo': value.trim(),
              });
            },
          ),
        ]),
      ],
    );
  }

  Future<void> _addChickWeightHouseSample() async {
    final values = await showAuditScopeIdentityDialog(
      context,
      scopeLabel: 'House',
      fields: const [AuditScopeIdentityField(key: 'house', label: 'House')],
      validator: (values) => _hasDuplicateChickWeightHouse(values['house']!)
          ? 'A House scope with this identity already exists.'
          : null,
    );
    if (values == null || !mounted) return;
    final house = values['house']!;
    provider.addChickWeightSample();
    provider.updateChickWeightSampleMetadata({
      'houseNo': house,
      'houseLabel': 'House $house',
    });
  }

  bool _hasDuplicateChickWeightHouse(String house) {
    if (!provider.isChickWeightCompareMode) return false;
    final normalized = normalizeAuditScopeIdentity(house, prefix: 'H');
    return provider.chickWeightSamples.any(
      (sample) =>
          normalizeAuditScopeIdentity(
            sample.houseNo ?? sample.sampleLabel,
            prefix: 'H',
          ) ==
          normalized,
    );
  }

  Future<void> _removeActiveChickWeightHouseSample() async {
    final discardsResults =
        provider.chickWeightSamples.length > 1 &&
        provider.chickWeightScopeHasEnteredResults(
          provider.activeChickWeightSampleIndex,
        );
    final confirmed = await confirmAuditScopeRemoval(
      context,
      hasEnteredResults: discardsResults,
    );
    if (!confirmed || !mounted) return;
    provider.removeActiveChickWeightSample();
  }

  TextEditingController _identityController(StationSampleModel sample) {
    final nextText = _fieldValue(sample);
    final controller = _identityControllers.putIfAbsent(
      sample.id,
      () => TextEditingController(text: nextText),
    );
    final focusNode = _identityFocusNodes[sample.id];

    if (focusNode?.hasFocus != true && controller.text != nextText) {
      controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }

    return controller;
  }

  FocusNode _identityFocusNode(StationSampleModel sample) {
    return _identityFocusNodes.putIfAbsent(sample.id, FocusNode.new);
  }

  void _pruneIdentityFields(List<StationSampleModel> samples) {
    final validKeys = samples.map((sample) => sample.id).toSet();
    for (final key in _identityControllers.keys.toList()) {
      if (validKeys.contains(key)) continue;
      _identityControllers.remove(key)?.dispose();
      _identityFocusNodes.remove(key)?.dispose();
    }
    for (final key in _identityFocusNodes.keys.toList()) {
      if (validKeys.contains(key)) continue;
      _identityFocusNodes.remove(key)?.dispose();
    }
  }

  String _fieldValue(StationSampleModel sample) {
    final value = sample.houseNo?.trim();
    if (value == null || value.isEmpty) return '';
    if (_isGeneratedHouseScopeValue(sample, value)) return '';
    return sample.houseNo ?? '';
  }

  bool _isGeneratedHouseScopeValue(StationSampleModel sample, String value) {
    if (value == 'H') return true;
    if (!RegExp(r'^H\d+$').hasMatch(value)) return false;
    return sample.sampleLabel == value && sample.houseNo == value;
  }

  Widget _buildHouseSampleChip({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback? onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled && onSelected != null ? (_) => onSelected() : null,
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

  Widget _buildHouseSampleActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      tooltip: context.tr(tooltip),
      onPressed: onPressed,
      icon: _GradientIcon(icon, size: 24),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }

  InputDecoration _scopeInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }
}

class _MachineSampleControls extends StatefulWidget {
  final AuditProvider provider;

  const _MachineSampleControls({required this.provider});

  @override
  State<_MachineSampleControls> createState() => _MachineSampleControlsState();
}

class _MachineSampleControlsState extends State<_MachineSampleControls> {
  final Map<String, TextEditingController> _identityControllers = {};
  final Map<String, FocusNode> _identityFocusNodes = {};

  AuditProvider get provider => widget.provider;

  @override
  void dispose() {
    for (final controller in _identityControllers.values) {
      controller.dispose();
    }
    for (final node in _identityFocusNodes.values) {
      node.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _pruneIdentityFields(provider.stationSamples);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSampleControlCard(
          title: 'Machine scope',
          child: _buildMachineSampleChips(),
        ),
      ],
    );
  }

  Widget _buildSampleControlCard({
    String? title,
    String? note,
    required Widget child,
  }) {
    final hasHeader = title != null || note != null;
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
          if (hasHeader) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (title != null)
                  Expanded(
                    child: Text(
                      title,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  )
                else
                  const Spacer(),
                if (note != null) ...[
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      note,
                      textAlign: TextAlign.end,
                      style: AppTextStyles.caption,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 10),
          ],
          child,
        ],
      ),
    );
  }

  Widget _buildMachineSampleChips() {
    final active = provider.isChickQualityMachineScopeActive;
    final chips = active
        ? [
            for (final entry in provider.stationSamples.asMap().entries)
              _buildMachineSampleChip(
                label: entry.value.sampleLabel,
                selected: entry.key == provider.activeSampleIndex,
                enabled: !provider.isReadOnly,
                onSelected: () => provider.switchSample(entry.key),
              ),
          ]
        : [
            _buildMachineSampleChip(
              label: 'Pool',
              selected: true,
              enabled: false,
              onSelected: null,
            ),
          ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMachineSampleActionButton(
          tooltip: context.tr('Add machine sample'),
          icon: Icons.add,
          onPressed: provider.isReadOnly ? null : _addMachineSample,
        ),
        if (active) ...[
          const SizedBox(width: 8),
          _buildMachineSampleActionButton(
            tooltip: context.tr('Remove active machine sample'),
            icon: Icons.remove,
            onPressed: provider.isReadOnly ? null : _removeActiveMachineSample,
          ),
        ],
      ],
    );

    final chipRow = LayoutBuilder(
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
    if (!active) return chipRow;
    final sample = provider.activeStationSample;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        chipRow,
        const SizedBox(height: 10),
        _buildScopeInputFields([
          TextFormField(
            key: ValueKey('chick-machine-setter-${sample.id}'),
            controller: _identityController(sample, 'setter'),
            focusNode: _identityFocusNode(sample, 'setter'),
            enabled: !provider.isReadOnly,
            textInputAction: TextInputAction.next,
            decoration: _scopeInputDecoration('Setter'),
            onChanged: (value) {
              final accepted = provider.updateSampleMetadata({
                'setterNo': value.trim(),
              });
              if (!accepted) _restoreIdentityController(sample, 'setter');
            },
          ),
          TextFormField(
            key: ValueKey('chick-machine-hatcher-${sample.id}'),
            controller: _identityController(sample, 'hatcher'),
            focusNode: _identityFocusNode(sample, 'hatcher'),
            enabled: !provider.isReadOnly,
            textInputAction: TextInputAction.done,
            decoration: _scopeInputDecoration('Hatcher'),
            onChanged: (value) {
              final accepted = provider.updateSampleMetadata({
                'hatcherNo': value.trim(),
              });
              if (!accepted) _restoreIdentityController(sample, 'hatcher');
            },
          ),
        ]),
      ],
    );
  }

  Future<void> _addMachineSample() async {
    final values = await showAuditScopeIdentityDialog(
      context,
      scopeLabel: 'Machine',
      fields: const [
        AuditScopeIdentityField(key: 'setter', label: 'Setter'),
        AuditScopeIdentityField(key: 'hatcher', label: 'Hatcher'),
      ],
      validator: (values) =>
          _hasDuplicateMachine(
            setter: values['setter']!,
            hatcher: values['hatcher']!,
          )
          ? 'A Machine scope with this identity already exists.'
          : null,
    );
    if (values == null || !mounted) return;
    provider.addChickQualityMachineScopeSample();
    provider.updateSampleMetadata({
      'setterNo': values['setter'],
      'hatcherNo': values['hatcher'],
    });
  }

  bool _hasDuplicateMachine({required String setter, required String hatcher}) {
    if (!provider.isChickQualityMachineScopeActive) return false;
    final normalizedSetter = normalizeAuditScopeIdentity(setter, prefix: 'S');
    final normalizedHatcher = normalizeAuditScopeIdentity(hatcher, prefix: 'H');
    return provider.stationSamples.any(
      (sample) =>
          normalizeAuditScopeIdentity(sample.setterNo ?? '', prefix: 'S') ==
              normalizedSetter &&
          normalizeAuditScopeIdentity(sample.hatcherNo ?? '', prefix: 'H') ==
              normalizedHatcher,
    );
  }

  Future<void> _removeActiveMachineSample() async {
    final discardsResults =
        provider.stationSamples.length > 1 &&
        provider.stationScopeHasEnteredResults(provider.activeSampleIndex);
    final confirmed = await confirmAuditScopeRemoval(
      context,
      hasEnteredResults: discardsResults,
    );
    if (!confirmed || !mounted) return;
    provider.removeActiveChickQualityMachineScopeSample();
  }

  TextEditingController _identityController(
    StationSampleModel sample,
    String field,
  ) {
    final key = _identityKey(sample, field);
    final nextText = _fieldValue(sample, field);
    final controller = _identityControllers.putIfAbsent(
      key,
      () => TextEditingController(text: nextText),
    );
    final focusNode = _identityFocusNodes[key];

    if (focusNode?.hasFocus != true && controller.text != nextText) {
      controller.value = TextEditingValue(
        text: nextText,
        selection: TextSelection.collapsed(offset: nextText.length),
      );
    }

    return controller;
  }

  FocusNode _identityFocusNode(StationSampleModel sample, String field) {
    final key = _identityKey(sample, field);
    return _identityFocusNodes.putIfAbsent(key, FocusNode.new);
  }

  void _restoreIdentityController(StationSampleModel sample, String field) {
    final text = _fieldValue(sample, field);
    final controller = _identityControllers[_identityKey(sample, field)];
    if (controller == null || controller.text == text) return;
    controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  void _pruneIdentityFields(List<StationSampleModel> samples) {
    final validKeys = <String>{
      for (final sample in samples)
        for (final field in const ['setter', 'hatcher'])
          _identityKey(sample, field),
    };

    for (final key in _identityControllers.keys.toList()) {
      if (validKeys.contains(key)) continue;
      _identityControllers.remove(key)?.dispose();
      _identityFocusNodes.remove(key)?.dispose();
    }
    for (final key in _identityFocusNodes.keys.toList()) {
      if (validKeys.contains(key)) continue;
      _identityFocusNodes.remove(key)?.dispose();
    }
  }

  String _identityKey(StationSampleModel sample, String field) {
    return '${sample.id}:$field';
  }

  String _fieldValue(StationSampleModel sample, String field) {
    final value = switch (field) {
      'setter' => sample.setterNo,
      'hatcher' => sample.hatcherNo,
      _ => null,
    };
    final trimmed = value?.trim();
    if (trimmed == null || trimmed.isEmpty) return '';

    final prefix = field == 'setter' ? 'S' : 'H';
    if (_isGeneratedMachineScopeValue(sample, trimmed, prefix)) return '';
    return value ?? '';
  }

  bool _isGeneratedMachineScopeValue(
    StationSampleModel sample,
    String value,
    String prefix,
  ) {
    if (value == prefix) return true;
    if (!RegExp('^$prefix\\d+\$').hasMatch(value)) return false;
    return value == '$prefix${_scopeSerial(sample)}';
  }

  int _scopeSerial(StationSampleModel sample) {
    var serial = 0;
    for (final candidate in provider.stationSamples) {
      if (candidate.sampleKind != sample.sampleKind) continue;
      serial++;
      if (candidate.id == sample.id) return serial;
    }
    return sample.sampleIndex;
  }

  Widget _buildMachineSampleChip({
    required String label,
    required bool selected,
    required bool enabled,
    required VoidCallback? onSelected,
  }) {
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled && onSelected != null ? (_) => onSelected() : null,
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

  Widget _buildMachineSampleActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      tooltip: context.tr(tooltip),
      onPressed: onPressed,
      icon: _GradientIcon(icon, size: 24),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _buildScopeInputFields(List<Widget> fields) {
    return Row(
      children: [
        for (var i = 0; i < fields.length; i++) ...[
          Expanded(child: fields[i]),
          if (i < fields.length - 1) const SizedBox(width: 10),
        ],
      ],
    );
  }

  InputDecoration _scopeInputDecoration(String label) {
    return InputDecoration(
      labelText: label,
      isDense: true,
      filled: true,
      fillColor: Colors.white,
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.borderDefault),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: const BorderSide(color: AppColors.primary, width: 1.4),
      ),
    );
  }
}

class _MetricGrid extends StatelessWidget {
  final AuditModel audit;
  final _WeightStats stats;
  final double? bmkChickWeight;

  const _MetricGrid({
    required this.audit,
    required this.stats,
    required this.bmkChickWeight,
  });

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricSummaryItem(
        label: 'Sample Size',
        value: '${stats.count}/100',
        kind: _MetricKind.info,
      ),
      _MetricSummaryItem(
        label: 'BMK Chick Weight',
        value: (bmkChickWeight ?? audit.chickBmkWeight) == null
            ? '--'
            : '${(bmkChickWeight ?? audit.chickBmkWeight)!.toStringAsFixed(1)}g',
      ),
      _MetricSummaryItem(
        label: 'Avg Weight',
        value: stats.average == null
            ? '--'
            : '${stats.average!.toStringAsFixed(1)}g',
        kind: _MetricKind.info,
      ),
      _MetricSummaryItem(
        label: 'Low Margin',
        value: stats.low == null ? '--' : '${stats.low!.toStringAsFixed(1)}g',
      ),
      _MetricSummaryItem(
        label: 'High Margin',
        value: stats.high == null ? '--' : '${stats.high!.toStringAsFixed(1)}g',
      ),
      _MetricSummaryItem(
        label: 'Uniformity',
        value: stats.uniformity == null
            ? '--'
            : '${stats.uniformity!.toStringAsFixed(1)}%',
        kind:
            stats.uniformity == null ||
                stats.uniformity! >= AppThresholds.uniformityGood
            ? _MetricKind.good
            : _MetricKind.warn,
      ),
      _MetricSummaryItem(
        label: 'C.V',
        value: stats.cv == null ? '--' : '${stats.cv!.toStringAsFixed(1)}%',
        kind: stats.cv == null || stats.cv! <= AppThresholds.cvAlertPct
            ? _MetricKind.good
            : _MetricKind.warn,
      ),
    ];

    return Container(
      key: const ValueKey('chick-weight-metric-summary'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        children: [
          for (var i = 0; i < metrics.length; i++) ...[
            if (i > 0)
              Divider(height: 1, color: AppColors.borderDefault.withAlpha(170)),
            _MetricRow(item: metrics[i]),
          ],
        ],
      ),
    );
  }
}

enum _MetricKind { normal, info, good, warn }

class _MetricSummaryItem {
  final String label;
  final String value;
  final _MetricKind kind;

  const _MetricSummaryItem({
    required this.label,
    required this.value,
    this.kind = _MetricKind.normal,
  });
}

class _MetricRow extends StatelessWidget {
  final _MetricSummaryItem item;

  const _MetricRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final color = switch (item.kind) {
      _MetricKind.info => AppColors.primary,
      _MetricKind.good => AppColors.statusGood,
      _MetricKind.warn => AppColors.statusWarning,
      _MetricKind.normal => AppColors.textPrimary,
    };

    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 44),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Text(
              item.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.textSecondary,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Flexible(
            child: Text(
              item.value,
              textAlign: TextAlign.end,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.body.copyWith(
                color: color,
                fontWeight: FontWeight.w900,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeightStats {
  final int count;
  final double? average;
  final double? cv;
  final double? low;
  final double? high;
  final double? uniformity;

  const _WeightStats({
    required this.count,
    this.average,
    this.cv,
    this.low,
    this.high,
    this.uniformity,
  });

  factory _WeightStats.fromControllers(
    List<TextEditingController> controllers,
  ) {
    final weights = controllers
        .map((controller) => double.tryParse(controller.text))
        .where((weight) => weight != null && weight > 0)
        .map((weight) => weight!)
        .toList();
    if (weights.isEmpty) return const _WeightStats(count: 0);

    final avg = CalculationUtils.average(weights);
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;
    final low = avg * 0.9;
    final high = avg * 1.1;
    final uniformity = CalculationUtils.uniformityPercent(weights, low, high);
    return _WeightStats(
      count: weights.length,
      average: avg,
      cv: cv,
      low: low,
      high: high,
      uniformity: uniformity,
    );
  }
}
