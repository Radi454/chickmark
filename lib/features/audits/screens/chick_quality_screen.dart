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
import '../widgets/audit_keyboard_dismiss.dart';
import '../widgets/audit_numeric_keyboard.dart';
import '../widgets/sample_mode_controls.dart';
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
    _syncWeightControllers(audit);

    return UnsavedChangesGuard(
      enabled: widget.context.sessionId == null,
      child: Scaffold(
        backgroundColor: AppColors.background,
        appBar: widget.context.sessionId != null
            ? null
            : GradientAppBar(
                title: 'Chicks',
                toolbarHeight: 88,
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
            child: Column(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    key: const ValueKey('chick-quality-scroll'),
                    padding: const EdgeInsets.fromLTRB(22, 22, 22, 18),
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
    final leftColumn = Column(
      children: [
        _StationPanel(
          key: const ValueKey('chick-quality-panel-pasgar'),
          mark: 'PG',
          title: 'Pasgar Score',
          meta: 'Sample defects and final score',
          status: _pasgarStatus(audit),
          statusKind: _StatusKind.good,
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
          meta: 'Yolk-free body mass check',
          status: _yfbmStatus(audit),
          statusKind: _StatusKind.good,
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
          meta: 'Basket position measurements',
          status: _cvtStatus(audit),
          statusKind: _cvtStatusKind(audit),
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
          meta: 'Hatchery-side pathology sample',
          status: 'Review',
          statusKind: _StatusKind.warn,
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
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        final title = provider.isCompareMode
            ? '${provider.activeStationSample.sampleLabel} Chick Weight Sheet'
            : 'Chick Weight Sheet';
        return FractionallySizedBox(
          heightFactor: 0.86,
          child: Container(
            key: const ValueKey('chick-quality-weight-sheet'),
            margin: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: AppColors.borderDefault),
              boxShadow: const [
                BoxShadow(
                  color: Color(0x3D111827),
                  blurRadius: 32,
                  offset: Offset(0, 18),
                ),
              ],
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          style: AppTextStyles.sectionTitle.copyWith(
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: 'Close weight sheet',
                        onPressed: () => Navigator.of(sheetContext).pop(),
                        icon: const Icon(Icons.close),
                      ),
                    ],
                  ),
                ),
                const Divider(height: 1),
                Expanded(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(16),
                    child: KeyedSubtree(
                      key: const ValueKey('weight-grid-widget'),
                      child: WeightGridWidget(
                        controllers: _weightControllers,
                        focusNodes: _weightFocusNodes,
                        enabled: !provider.isReadOnly,
                        onChanged: _updateWeightCalculations,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  void _syncWeightControllers(AuditModel audit) {
    if (_loadedWeightsAuditId == audit.id) return;
    for (final controller in _weightControllers) {
      controller.text = '';
    }

    final weightsJson = audit.chickWeights;
    if (weightsJson != null && weightsJson.isNotEmpty) {
      try {
        final decoded = jsonDecode(weightsJson);
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
    _loadedWeightsAuditId = audit.id;
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
    provider.updateField('chickWeights', jsonEncode(allWeights));

    if (weights.isEmpty) {
      provider.updateField('chickAvgWeight', null);
      provider.updateField('chickUniformityPct', null);
      provider.updateField('chickCvPct', null);
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

    provider.updateField('chickAvgWeight', avg);
    provider.updateField('chickUniformityPct', uniformity);
    provider.updateField('chickCvPct', cv);
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(18),
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
              letterSpacing: 0.8,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'Chick quality',
            style: AppTextStyles.heading.copyWith(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 18),
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
      padding: const EdgeInsets.all(10),
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
              letterSpacing: 0.6,
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

  const _StationPanel({
    super.key,
    this.mark = '',
    this.title = '',
    this.meta = '',
    this.status = '',
    this.statusKind = _StatusKind.good,
    required this.child,
    this.showHeader = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
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
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (showHeader) ...[
            Padding(
              padding: const EdgeInsets.all(16),
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
                        const SizedBox(height: 2),
                        Text(meta, style: AppTextStyles.caption),
                      ],
                    ),
                  ),
                  _StatusPill(label: status, kind: statusKind),
                ],
              ),
            ),
            const Divider(height: 1),
          ],
          Padding(padding: const EdgeInsets.all(16), child: child),
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
      width: 34,
      height: 34,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.infoBg,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.primary.withValues(alpha: 0.16)),
      ),
      child: Text(
        mark,
        style: AppTextStyles.caption.copyWith(
          color: AppColors.primary,
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
      constraints: const BoxConstraints(minHeight: 30),
      padding: const EdgeInsets.symmetric(horizontal: 10),
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
        const SizedBox(height: 14),
        StationSampleModeControls(
          provider: provider,
          padding: EdgeInsets.zero,
          title: 'Chick Sample Mode',
          comparisonLabel: 'Multi House Samples',
        ),
        if (provider.isCompareMode) ...[
          const SizedBox(height: 14),
          Text(
            'House Samples',
            style: AppTextStyles.title.copyWith(fontWeight: FontWeight.w800),
          ),
        ],
        const SizedBox(height: 14),
        _MetricGrid(audit: audit, stats: stats),
        const SizedBox(height: 14),
        Align(
          alignment: Alignment.centerLeft,
          child: OutlinedButton(
            onPressed: onOpenWeightSheet,
            child: const Text('Enter Weights'),
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
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: AppColors.brandGradient,
        borderRadius: BorderRadius.circular(18),
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
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Flock-linked sample results',
                      style: AppTextStyles.caption.copyWith(
                        color: Colors.white.withValues(alpha: 0.78),
                        fontWeight: FontWeight.w700,
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
          const SizedBox(height: 18),
          LayoutBuilder(
            builder: (context, constraints) {
              final isWide = constraints.maxWidth >= 420;
              final tiles = [
                _FlockTile(label: 'Flock', value: contextData.flockId),
                _FlockTile(label: 'Breed', value: contextData.breed ?? '--'),
                _FlockTile(
                  label: 'BMK Age',
                  value: audit.chickBmkAge == null
                      ? contextData.flockAgeWeeks == null
                            ? '--'
                            : '${contextData.flockAgeWeeks} wks'
                      : '${audit.chickBmkAge} wks',
                ),
              ];
              if (!isWide) {
                return Column(
                  children: [
                    for (final tile in tiles) ...[
                      tile,
                      if (tile != tiles.last) const SizedBox(height: 10),
                    ],
                  ],
                );
              }
              return Row(
                children: [
                  for (var i = 0; i < tiles.length; i++) ...[
                    Expanded(child: tiles[i]),
                    if (i < tiles.length - 1) const SizedBox(width: 10),
                  ],
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}

class _FlockTile extends StatelessWidget {
  final String label;
  final String value;

  const _FlockTile({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(10),
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
      const _MetricTile.empty(),
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
  final bool hidden;

  const _MetricTile({
    required this.label,
    required this.value,
    this.kind = _MetricKind.normal,
  }) : hidden = false;

  const _MetricTile.empty()
    : label = '',
      value = '',
      kind = _MetricKind.normal,
      hidden = true;

  @override
  Widget build(BuildContext context) {
    if (hidden) return const SizedBox.shrink();

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
