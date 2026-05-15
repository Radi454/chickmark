import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/station_sample_model.dart';
import '../providers/audit_provider.dart';
import '../widgets/audit_autosave_status.dart';
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/weight_grid_widget.dart';
import '../widgets/tabs/cvt_tab.dart';
import '../widgets/tabs/pasgar_tab.dart';
import '../widgets/tabs/pm_necropsy_tab.dart';
import '../widgets/tabs/yfbm_tab.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class ChickQualityScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final List<AuditModel> initialAudits;
  final List<StationSampleModel> initialStationSamples;
  final int initialTabIndex;

  const ChickQualityScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialAudits = const [],
    this.initialStationSamples = const [],
    this.initialTabIndex = 0,
  });

  @override
  State<ChickQualityScreen> createState() => _ChickQualityScreenState();
}

class _ChickQualityScreenState extends State<ChickQualityScreen> {
  static const double _wideWorkbenchBreakpoint = 980;

  final List<TextEditingController> _weightControllers = List.generate(
    100,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _weightFocusNodes = List.generate(
    100,
    (_) => FocusNode(),
  );
  String? _loadedWeightsAuditId;

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
  }

  @override
  void dispose() {
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
                  child: SingleChildScrollView(
                    key: const ValueKey('chick-quality-scroll'),
                    padding: const EdgeInsets.fromLTRB(16, 18, 16, 18),
                    child: Center(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 1240),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            _HeaderCard(contextData: widget.context),
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
          mark: 'CQ',
          title: 'Chick Quality',
          meta: 'Setter/hatcher sample scope',
          status: provider.isCompareMode ? 'Compare' : 'Single',
          statusKind: _StatusKind.good,
          showHeader: false,
          child: _MachineSampleControls(provider: provider),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-pasgar'),
          mark: 'PG',
          title: 'Pasgar Score',
          meta: activeQualitySampleMeta,
          status: _pasgarStatus(audit),
          statusKind: _StatusKind.good,
          collapsible: true,
          child: PasgarTab(
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-yfbm'),
          mark: 'YF',
          title: 'YFBM',
          meta: activeQualitySampleMeta,
          status: _yfbmStatus(audit),
          statusKind: _StatusKind.good,
          collapsible: true,
          child: YfbmTab(
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-cvt'),
          mark: 'CVT',
          title: 'Chick Vent Temperature',
          meta: activeQualitySampleMeta,
          status: _cvtStatus(audit),
          statusKind: _cvtStatusKind(audit),
          collapsible: true,
          child: CvtTab(
            audit: audit,
            isReadOnly: provider.isReadOnly,
            embedded: true,
            onFieldChanged: provider.updateField,
          ),
        ),
        const SizedBox(height: 16),
        _StationPanel(
          key: const ValueKey('chick-quality-panel-pm'),
          mark: 'PM',
          title: 'PM Necropsy',
          meta: activeQualitySampleMeta,
          status: 'Review',
          statusKind: _StatusKind.warn,
          collapsible: true,
          child: PmNecropsyTab(
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
                                  tooltip: 'Close',
                                  onPressed: () =>
                                      Navigator.of(sheetContext).pop(),
                                  icon: const Icon(Icons.close),
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
                                    _updateWeightCalculations();
                                    setSheetState(() {});
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
    } else if (audit.chickWeights != null && audit.chickWeights!.isNotEmpty) {
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

  void _updateWeightCalculations() {
    final provider = context.read<AuditProvider>();
    final weights = _weightControllers
        .map((controller) => double.tryParse(controller.text))
        .where((weight) => weight != null && weight > 0)
        .map((weight) => weight!)
        .toList();

    final allWeights = _weightControllers
        .map((controller) => double.tryParse(controller.text))
        .toList();

    if (weights.isEmpty) {
      provider.updateChickWeightSampleResult(
        weightsJson: jsonEncode(allWeights),
      );
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
      weightsJson: jsonEncode(allWeights),
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

  String _pasgarStatus(AuditModel audit) {
    final score = audit.pasgarFinalScore;
    return score == null ? '--' : '${score.toStringAsFixed(1)}/10';
  }

  String _yfbmStatus(AuditModel audit) {
    final avg = audit.yfbmAvgPct;
    return avg == null ? 'Stable' : '${avg.toStringAsFixed(1)}%';
  }

  String _cvtStatus(AuditModel audit) {
    final avg = audit.cvtAvg;
    return avg == null ? '--' : '${avg.toStringAsFixed(1)}F';
  }

  _StatusKind _cvtStatusKind(AuditModel audit) {
    final avg = audit.cvtAvg;
    if (avg == null) return _StatusKind.good;
    return avg >= AppThresholds.cvtMin && avg <= AppThresholds.cvtMax
        ? _StatusKind.good
        : _StatusKind.warn;
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
              fontSize: 26,
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

enum _StatusKind { good, warn }

class _StationPanel extends StatelessWidget {
  final String mark;
  final String title;
  final String meta;
  final String status;
  final _StatusKind statusKind;
  final Widget child;
  final bool showHeader;
  final bool collapsible;

  const _StationPanel({
    super.key,
    this.mark = '',
    this.title = '',
    this.meta = '',
    this.status = '',
    this.statusKind = _StatusKind.good,
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
            leading: _SectionMark(mark: mark),
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
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                _StatusPill(label: status, kind: statusKind),
                const SizedBox(width: 8),
                const Icon(Icons.expand_more),
              ],
            ),
            children: [child],
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
                  _SectionMark(mark: mark),
                  const SizedBox(width: 10),
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
                  _StatusPill(label: status, kind: statusKind),
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

class _SectionMark extends StatelessWidget {
  final String mark;

  const _SectionMark({required this.mark});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 32,
      height: 32,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Text(
        mark,
        textAlign: TextAlign.center,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
          fontSize: mark.length > 2 ? 11 : 12,
          fontWeight: FontWeight.w900,
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String label;
  final _StatusKind kind;

  const _StatusPill({required this.label, required this.kind});

  @override
  Widget build(BuildContext context) {
    final isGood = kind == _StatusKind.good;
    return Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isGood ? AppColors.statusGoodBg : AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: isGood ? AppColors.statusGood : AppColors.statusWarning,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

class _GradientIcon extends StatelessWidget {
  final IconData icon;
  final double size;
  final bool framed;

  const _GradientIcon(
    this.icon, {
    super.key,
    this.size = 18,
    this.framed = false,
  });

  @override
  Widget build(BuildContext context) {
    if (framed) {
      return Container(
        width: size + 10,
        height: size + 10,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: AppColors.brandGradient,
          borderRadius: BorderRadius.circular(7),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withValues(alpha: 0.18),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: Icon(icon, size: size, color: Colors.white),
      );
    }

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
  final List<TextEditingController> weightControllers;
  final List<FocusNode> weightFocusNodes;
  final VoidCallback onWeightsChanged;
  final VoidCallback onOpenWeightSheet;

  const _ChickWeightsPanel({
    required this.contextData,
    required this.provider,
    required this.audit,
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
        _MetricGrid(audit: audit, stats: stats),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
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
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
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
                  ],
                ),
              ),
              _StatusPill(
                label: stats.uniformity == null
                    ? 'Uniform'
                    : stats.uniformity! >= AppThresholds.uniformityGood
                    ? 'Uniform'
                    : 'Review',
                kind:
                    stats.uniformity == null ||
                        stats.uniformity! >= AppThresholds.uniformityGood
                    ? _StatusKind.good
                    : _StatusKind.warn,
              ),
            ],
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
    final bmkAge = audit.chickBmkAge ?? contextData.flockAgeWeeks;
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

class _HouseWeightSampleControls extends StatelessWidget {
  final AuditProvider provider;

  const _HouseWeightSampleControls({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSampleControlCard(
          title: 'House scope',
          child: _buildHouseScopeSelector(),
        ),
        if (provider.isChickWeightCompareMode) ...[
          const SizedBox(height: 10),
          _buildSampleControlCard(
            title: 'House Samples',
            note: 'Compare chick weights by house',
            child: _buildHouseSampleChips(),
          ),
        ],
        const SizedBox(height: 10),
        _buildSampleControlCard(
          title: 'Active house',
          note: 'Weight sample source',
          child: _buildHouseFields(context),
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

  Widget _buildHouseScopeSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: true,
        selectedIcon: const _GradientIcon(
          Icons.check,
          key: ValueKey('house-scope-selected-icon'),
          size: 14,
          framed: true,
        ),
        segments: const [
          ButtonSegment<bool>(
            value: false,
            icon: _GradientIcon(
              Icons.home_outlined,
              key: ValueKey('house-scope-one-icon'),
              size: 14,
              framed: true,
            ),
            label: Text('One sample'),
          ),
          ButtonSegment<bool>(
            value: true,
            icon: _GradientIcon(
              Icons.compare_arrows,
              key: ValueKey('house-scope-multi-icon'),
              size: 14,
              framed: true,
            ),
            label: Text('Multisamples'),
          ),
        ],
        selected: {provider.isChickWeightCompareMode},
        onSelectionChanged: provider.isReadOnly
            ? null
            : (values) {
                final compare = values.first;
                if (compare == provider.isChickWeightCompareMode) return;
                provider.setChickWeightSampleMode(
                  compare
                      ? StationSampleModel.sampleModeComparison
                      : StationSampleModel.sampleModePooled,
                );
              },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return BorderSide(
              color: selected ? AppColors.primary : AppColors.borderDefault,
            );
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textBody;
          }),
          textStyle: WidgetStateProperty.all(
            AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Widget _buildHouseSampleChips() {
    final chips = [
      for (final entry in provider.chickWeightSamples.asMap().entries)
        ChoiceChip(
          label: Text(entry.value.sampleLabel),
          selected: entry.key == provider.activeChickWeightSampleIndex,
          onSelected: provider.isReadOnly
              ? null
              : (_) => provider.switchChickWeightSample(entry.key),
          selectedColor: AppColors.primary.withAlpha(30),
          checkmarkColor: AppColors.primary,
          labelStyle: AppTextStyles.body.copyWith(
            color: entry.key == provider.activeChickWeightSampleIndex
                ? AppColors.primary
                : AppColors.textBody,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: entry.key == provider.activeChickWeightSampleIndex
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
          onPressed: provider.isReadOnly ? null : provider.addChickWeightSample,
        ),
        if (provider.chickWeightSamples.length > 1) ...[
          const SizedBox(width: 8),
          _buildHouseSampleActionButton(
            tooltip: 'Remove active house sample',
            icon: Icons.remove,
            onPressed: provider.isReadOnly
                ? null
                : provider.removeActiveChickWeightSample,
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
      icon: _GradientIcon(icon, size: 24),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _buildHouseFields(BuildContext context) {
    final sample = provider.activeChickWeightSample;
    return TextFormField(
      key: ValueKey('chick-weight-house-${sample.id}'),
      initialValue: sample.houseNo ?? '',
      enabled: !provider.isReadOnly,
      textInputAction: TextInputAction.done,
      decoration: _houseInputDecoration('House'),
      onChanged: (value) {
        provider.updateChickWeightSampleMetadata({'houseNo': value.trim()});
      },
    );
  }

  InputDecoration _houseInputDecoration(String label) {
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

class _MachineSampleControls extends StatelessWidget {
  final AuditProvider provider;

  const _MachineSampleControls({required this.provider});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSampleControlCard(
          title: 'Quality sampling',
          child: _buildMachineScopeSelector(),
        ),
        if (provider.isCompareMode) ...[
          const SizedBox(height: 10),
          _buildSampleControlCard(child: _buildMachineSampleChips()),
        ],
        const SizedBox(height: 10),
        _buildSampleControlCard(
          title: 'Active machine',
          note: 'Setter and hatcher pair',
          child: _buildMachineFields(context),
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

  Widget _buildMachineScopeSelector() {
    return SizedBox(
      width: double.infinity,
      child: SegmentedButton<bool>(
        showSelectedIcon: true,
        selectedIcon: const _GradientIcon(
          Icons.check,
          key: ValueKey('quality-scope-selected-icon'),
          size: 14,
          framed: true,
        ),
        segments: const [
          ButtonSegment<bool>(
            value: false,
            icon: _GradientIcon(
              Icons.precision_manufacturing_outlined,
              key: ValueKey('quality-scope-one-icon'),
              size: 14,
              framed: true,
            ),
            label: Text('One sample'),
          ),
          ButtonSegment<bool>(
            value: true,
            icon: _GradientIcon(
              Icons.compare_arrows,
              key: ValueKey('quality-scope-multi-icon'),
              size: 14,
              framed: true,
            ),
            label: Text('Multisamples'),
          ),
        ],
        selected: {provider.isCompareMode},
        onSelectionChanged: provider.isReadOnly
            ? null
            : (values) {
                final compare = values.first;
                if (compare == provider.isCompareMode) return;
                provider.setStationSampleMode(
                  compare
                      ? StationSampleModel.sampleModeComparison
                      : StationSampleModel.sampleModePooled,
                );
              },
        style: ButtonStyle(
          visualDensity: VisualDensity.compact,
          side: WidgetStateProperty.resolveWith((states) {
            final selected = states.contains(WidgetState.selected);
            return BorderSide(
              color: selected ? AppColors.primary : AppColors.borderDefault,
            );
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            return states.contains(WidgetState.selected)
                ? AppColors.primary
                : AppColors.textBody;
          }),
          textStyle: WidgetStateProperty.all(
            AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
          ),
        ),
      ),
    );
  }

  Widget _buildMachineSampleChips() {
    final chips = [
      for (final entry in provider.stationSamples.asMap().entries)
        ChoiceChip(
          label: Text(entry.value.sampleLabel),
          selected: entry.key == provider.activeSampleIndex,
          onSelected: provider.isReadOnly
              ? null
              : (_) => provider.switchSample(entry.key),
          selectedColor: AppColors.primary.withAlpha(30),
          checkmarkColor: AppColors.primary,
          labelStyle: AppTextStyles.body.copyWith(
            color: entry.key == provider.activeSampleIndex
                ? AppColors.primary
                : AppColors.textBody,
            fontWeight: FontWeight.w800,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: entry.key == provider.activeSampleIndex
                  ? AppColors.primary
                  : AppColors.borderDefault,
            ),
          ),
        ),
    ];

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _buildMachineSampleActionButton(
          tooltip: 'Add machine sample',
          icon: Icons.add,
          onPressed: provider.isReadOnly ? null : provider.addSample,
        ),
        if (provider.sampleCount > 1) ...[
          const SizedBox(width: 8),
          _buildMachineSampleActionButton(
            tooltip: 'Remove active machine sample',
            icon: Icons.remove,
            onPressed: provider.isReadOnly ? null : provider.removeActiveSample,
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

  Widget _buildMachineSampleActionButton({
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
  }) {
    return IconButton.filledTonal(
      tooltip: tooltip,
      onPressed: onPressed,
      icon: _GradientIcon(icon, size: 24),
      style: IconButton.styleFrom(
        fixedSize: const Size(44, 44),
        shape: const CircleBorder(),
      ),
    );
  }

  Widget _buildMachineFields(BuildContext context) {
    final sample = provider.activeStationSample;
    final fields = [
      TextFormField(
        key: ValueKey('chick-machine-setter-${sample.id}'),
        initialValue: sample.setterNo ?? '',
        enabled: !provider.isReadOnly,
        textInputAction: TextInputAction.next,
        decoration: _machineInputDecoration('Setter'),
        onChanged: (value) {
          provider.updateSampleMetadata({'setterNo': value.trim()});
        },
      ),
      TextFormField(
        key: ValueKey('chick-machine-hatcher-${sample.id}'),
        initialValue: sample.hatcherNo ?? '',
        enabled: !provider.isReadOnly,
        textInputAction: TextInputAction.done,
        decoration: _machineInputDecoration('Hatcher'),
        onChanged: (value) {
          provider.updateSampleMetadata({'hatcherNo': value.trim()});
        },
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 420) {
          return Column(
            children: [fields[0], const SizedBox(height: 10), fields[1]],
          );
        }
        return Row(
          children: [
            Expanded(child: fields[0]),
            const SizedBox(width: 10),
            Expanded(child: fields[1]),
          ],
        );
      },
    );
  }

  InputDecoration _machineInputDecoration(String label) {
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

  const _MetricGrid({required this.audit, required this.stats});

  @override
  Widget build(BuildContext context) {
    final metrics = [
      _MetricTile(
        label: 'Avg Weight',
        value: stats.average == null
            ? '--'
            : '${stats.average!.toStringAsFixed(1)}g',
        kind: _MetricKind.info,
      ),
      _MetricTile(
        label: 'BMK Chick Weight',
        value: audit.chickBmkWeight == null
            ? '--'
            : '${audit.chickBmkWeight!.toStringAsFixed(1)}g',
      ),
      _MetricTile(
        label: 'Sample Size',
        value: '${stats.count}/100',
        kind: _MetricKind.info,
      ),
      _MetricTile(
        label: 'Low Margin',
        value: stats.low == null ? '--' : '${stats.low!.toStringAsFixed(1)}g',
      ),
      _MetricTile(
        label: 'High Margin',
        value: stats.high == null ? '--' : '${stats.high!.toStringAsFixed(1)}g',
      ),
      _MetricTile(
        label: 'C.V',
        value: stats.cv == null ? '--' : '${stats.cv!.toStringAsFixed(1)}%',
        kind: stats.cv == null || stats.cv! <= AppThresholds.cvAlertPct
            ? _MetricKind.good
            : _MetricKind.warn,
      ),
      _MetricTile(
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
    ];

    return GridView.count(
      crossAxisCount: 2,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: 10,
      crossAxisSpacing: 10,
      childAspectRatio: 2.15,
      children: metrics,
    );
  }
}

enum _MetricKind { normal, info, good, warn }

class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final _MetricKind kind;

  const _MetricTile({
    required this.label,
    required this.value,
    this.kind = _MetricKind.normal,
  });

  @override
  Widget build(BuildContext context) {
    final color = switch (kind) {
      _MetricKind.info => AppColors.primary,
      _MetricKind.good => AppColors.statusGood,
      _MetricKind.warn => AppColors.statusWarning,
      _MetricKind.normal => AppColors.textPrimary,
    };

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: AppTextStyles.sectionTitle.copyWith(
              color: color,
              fontWeight: FontWeight.w900,
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
