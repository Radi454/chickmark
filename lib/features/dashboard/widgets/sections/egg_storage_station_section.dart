import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_thresholds.dart';
import '../../../../core/theme/app_page_route.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../models/egg_storage_models.dart';
import '../../providers/dashboard_provider.dart';
import '../../providers/scope_comparison_provider.dart';
import '../../scope/scope_config.dart';
import '../../scope/scope_models.dart';
import '../../scope/scope_severity.dart';
import '../../screens/photo_fullscreen_screen.dart';
import '../est_evidence_photos_card.dart';
import '../scope/alarm_triage_feed.dart';
import '../scope/scope_matrix_table.dart';

/// Storage station body for the dashboard, laid out like the egg audit station:
/// a triage feed first (Critical / Watch / collapsible In Target), then the EST
/// summary + 9-point grid photo, the Upside Down score, the storage checklist,
/// and finally Egg Quality with one tab per house sample.
///
/// EST / Upside / checklist are pool-level and read the filter-aware latest audit
/// ([DashboardProvider.eggStorageLatest] + EST photo evidence). Egg Quality is
/// per-house, so it reads the scope engine's per-house groups (same aggregation +
/// filter as the rest of the Scopes section).
class EggStorageStationSection extends StatelessWidget {
  const EggStorageStationSection({super.key});

  @override
  Widget build(BuildContext context) {
    final dashboard = _watchDashboardOrNull(context);
    final scope = context.watch<ScopeComparisonProvider>();

    final latest = dashboard?.eggStorageLatest;
    final evidence = dashboard?.eggStorageEstEvidence;
    final houses = scope.groupsFor('egg_quality');
    final eggQualityExample = scope.isDummyFor('egg_quality');

    final hasStorage = latest != null || evidence != null;
    final hasEggQuality = houses.isNotEmpty;
    if (!hasStorage && !hasEggQuality) return const _StorageEmptyState();

    final target = _EstTarget.fromStorageDays(latest?.storageDays);
    final triage = _collectTriage(latest, houses, target);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AlarmTriageFeed(items: triage),
        const SizedBox(height: AppSizes.spaceMd),
        _EstCard(
          latest: latest,
          evidence: evidence ?? EggStorageEstEvidence.fromJsonStrings(),
          target: target,
          onPhotoTap: (path) => _openPhoto(context, path),
        ),
        const SizedBox(height: AppSizes.spaceMd),
        _UpsideDownCard(latest: latest),
        const SizedBox(height: AppSizes.spaceMd),
        _StorageChecklistCard(latest: latest),
        const SizedBox(height: AppSizes.spaceMd),
        _EggQualityTabs(houses: houses, isExample: eggQualityExample),
      ],
    );
  }

  /// Grade every storage reading into a [TriageItem]: EST average vs the
  /// storage-day band, EST CV% / egg CV% / UV vs their caps, uniformity vs its
  /// floor, plus the condensation flag. In-target readings still emit (as `good`)
  /// so they fill the collapsible "In Target" list. EST / CV / condensation are
  /// pooled; uniformity / egg-CV / UV are per house (chip names the house).
  List<TriageItem> _collectTriage(
    EggStorageTrend? latest,
    List<ScopeGroup> houses,
    _EstTarget target,
  ) {
    final out = <TriageItem>[];
    if (latest != null) {
      final avg = _estAverage(latest);
      if (avg != null && avg != 0) {
        final sev = _estBandSeverity(avg, target);
        out.add(
          TriageItem(
            severity: sev,
            primaryTag: 'EST',
            secondaryTag: 'Pooled',
            metric: 'EST Average',
            value: '${_one(avg)}°C',
            context: 'Target ${target.rangeLabel}',
            advice: sev == ScopeSeverity.good
                ? null
                : (avg < target.minC
                    ? 'Below target band — warm storage toward range.'
                    : 'Above target band — cool storage toward range.'),
          ),
        );
      }
      if (latest.estCvPct != 0) {
        out.add(
          _ceilingItem(
            value: latest.estCvPct,
            limit: AppThresholds.cvAlertPct,
            margin: 1,
            primaryTag: 'EST',
            scopeTag: 'Pooled',
            metric: 'EST CV%',
            unit: '%',
            overAdvice: 'Uneven shell temperature — check grid uniformity.',
          ),
        );
      }
      if (latest.condensationPresent != null) {
        final present = latest.condensationPresent!;
        out.add(
          TriageItem(
            severity: present ? ScopeSeverity.warn : ScopeSeverity.good,
            primaryTag: 'Storage',
            secondaryTag: 'Pooled',
            metric: 'Condensation',
            value: present ? 'Present' : 'None',
            context: 'Storage room',
            advice: present
                ? 'Condensation present — wipe down & verify cooling.'
                : null,
          ),
        );
      }
    }
    for (final house in houses) {
      final label = house.label;
      final unif = _cellValue(house, 'eggUniformityPct');
      if (unif != null && unif > 0) {
        out.add(
          _floorItem(
            value: unif.toDouble(),
            limit: AppThresholds.uniformityGood,
            // ≥85 good, ≥80 warn, <80 err — the existing two bands.
            margin: AppThresholds.uniformityGood - AppThresholds.uniformityPoor,
            scopeTag: label,
            metric: 'Egg Uniformity',
            belowAdvice: 'Below the uniformity target — review flock spread.',
          ),
        );
      }
      final cv = _cellValue(house, 'eggCvPct');
      if (cv != null && cv > 0) {
        out.add(
          _ceilingItem(
            value: cv.toDouble(),
            limit: AppThresholds.cvAlertPct,
            margin: 1,
            primaryTag: 'Egg Quality',
            scopeTag: label,
            metric: 'Egg CV%',
            unit: '%',
            overAdvice: 'Weight spread high — review grading.',
          ),
        );
      }
      final uv = _cellValue(house, 'uvAffectedPct');
      if (uv != null && uv > 0) {
        out.add(
          _ceilingItem(
            value: uv.toDouble(),
            limit: _uvAffectedLimitPct,
            margin: 2,
            primaryTag: 'Egg Quality',
            scopeTag: label,
            metric: 'UV Affected',
            unit: '%',
            overAdvice: 'Shell contamination elevated — review nest hygiene.',
          ),
        );
      }
    }
    out.sort((a, b) => _sevRank(b.severity).compareTo(_sevRank(a.severity)));
    return out;
  }

  /// Defect reading (lower is better) vs a hard [limit]: at/under → good (a
  /// reading inside the limit never alarms), over by up to [margin] → warn
  /// (slightly off), beyond that → err (big gap).
  TriageItem _ceilingItem({
    required double value,
    required double limit,
    required double margin,
    required String primaryTag,
    required String scopeTag,
    required String metric,
    required String unit,
    required String overAdvice,
  }) {
    final sev = ceilingSeverity(value, limit, margin);
    return TriageItem(
      severity: sev,
      primaryTag: primaryTag,
      secondaryTag: scopeTag,
      metric: metric,
      value: '${_one(value)}$unit',
      context: 'Limit ≤ ${_one(limit)}$unit',
      advice: sev == ScopeSeverity.err
          ? overAdvice
          : (sev == ScopeSeverity.warn
              ? 'Slightly over limit — monitor next visit.'
              : null),
    );
  }

  /// Floor reading (higher is better) vs [limit]: ≥limit good, within [margin]
  /// below → warn, else err.
  TriageItem _floorItem({
    required double value,
    required double limit,
    required double margin,
    required String scopeTag,
    required String metric,
    required String belowAdvice,
  }) {
    final sev = floorSeverity(value, limit, margin);
    return TriageItem(
      severity: sev,
      primaryTag: 'Egg Quality',
      secondaryTag: scopeTag,
      metric: metric,
      value: '${_one(value)}%',
      context: 'Target ≥ ${_one(limit)}%',
      advice: sev == ScopeSeverity.err
          ? belowAdvice
          : (sev == ScopeSeverity.warn
              ? 'Near the target floor — monitor next visit.'
              : null),
    );
  }

  /// EST average vs the storage-day target band: inside good, ≤1.5°C out warn,
  /// further err.
  ScopeSeverity _estBandSeverity(double avg, _EstTarget target) {
    if (avg >= target.minC && avg <= target.maxC) return ScopeSeverity.good;
    final over = avg > target.maxC ? avg - target.maxC : target.minC - avg;
    return over > 1.5 ? ScopeSeverity.err : ScopeSeverity.warn;
  }

  int _sevRank(ScopeSeverity s) {
    switch (s) {
      case ScopeSeverity.err:
        return 3;
      case ScopeSeverity.warn:
        return 2;
      case ScopeSeverity.good:
        return 1;
      case ScopeSeverity.pool:
        return 0;
    }
  }

  void _openPhoto(BuildContext context, String path) {
    Navigator.push(
      context,
      AppPageRoute(builder: (_) => PhotoFullscreenScreen(filePath: path)),
    );
  }

  /// Egg storage's pooled EST / upside / checklist data lives in
  /// [DashboardProvider]. It's always present in the real dashboard, but
  /// [ScopeInsightsSection] is a composite that some harnesses mount with only the
  /// scope provider — so degrade to scope-only (Egg Quality still renders from its
  /// per-house groups) instead of crashing.
  static DashboardProvider? _watchDashboardOrNull(BuildContext context) {
    try {
      return context.watch<DashboardProvider>();
    } on ProviderNotFoundException {
      return null;
    }
  }
}

const double _uvAffectedLimitPct = 5.0;

/// EST grid is recorded in °C; [EggStorageTrend.estAvgF] holds that average (the
/// field name predates the °C cutover).
double? _estAverage(EggStorageTrend latest) =>
    latest.estAvgF != 0 ? latest.estAvgF : null;

/// Read a scope cell's numeric value by its sector column name (null if absent).
num? _cellValue(ScopeGroup group, String column) {
  final params = ScopeConfigRegistry.byId('egg_quality').params;
  final index = params.indexWhere((p) => p.column == column);
  if (index < 0 || index >= group.cells.length) return null;
  return group.cells[index].value;
}

String _one(double value) => value.toStringAsFixed(1);

String _text(String? value) {
  final text = value?.trim();
  return text == null || text.isEmpty ? '--' : text;
}

String _turningLabel(int? turningTimes) {
  if (turningTimes == null) return '--';
  if (turningTimes == 0) return 'No Turning';
  if (turningTimes == 1) return '1 time';
  return '$turningTimes times';
}

// ── shared sub-card shell (mirrors the audit station workbench panels) ────────

class _SubCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final Widget child;

  const _SubCard({
    required this.icon,
    required this.title,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
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
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Row(
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
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(AppSizes.cardPadding),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Compact label/value tile used inside the summary rows. Turns amber-tinted when
/// [isAlarm] so an out-of-spec figure stands out at a glance.
class _MetricTile extends StatelessWidget {
  final String label;
  final String value;
  final bool isAlarm;

  const _MetricTile({
    required this.label,
    required this.value,
    this.isAlarm = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: isAlarm ? AppColors.statusErrorBg : AppColors.surfaceRaised,
        border: Border.all(
          color: isAlarm
              ? AppColors.statusError.withValues(alpha: 0.30)
              : AppColors.borderDefault,
        ),
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w900,
              color: isAlarm ? AppColors.statusError : AppColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

/// Responsive grid of [_MetricTile]s (same wrap math as the scope tiles grid).
class _MetricGrid extends StatelessWidget {
  final List<_MetricTile> tiles;

  const _MetricGrid({required this.tiles});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const gap = AppSizes.spaceSm;
        const minTile = 132.0;
        final cols = (constraints.maxWidth / (minTile + gap))
            .floor()
            .clamp(1, 5);
        final tileW = (constraints.maxWidth - gap * (cols - 1)) / cols;
        return Wrap(
          spacing: gap,
          runSpacing: gap,
          children: [
            for (final tile in tiles) SizedBox(width: tileW, child: tile),
          ],
        );
      },
    );
  }
}

// ── EST summary + 9-point grid photo ──────────────────────────────────────────

class _EstCard extends StatelessWidget {
  final EggStorageTrend? latest;
  final EggStorageEstEvidence evidence;
  final _EstTarget target;
  final ValueChanged<String> onPhotoTap;

  const _EstCard({
    required this.latest,
    required this.evidence,
    required this.target,
    required this.onPhotoTap,
  });

  @override
  Widget build(BuildContext context) {
    final avg = latest == null ? null : _estAverage(latest!);
    final cv = latest?.estCvPct;
    final tempStatus = _EstTempStatus.from(avg, target);
    final cvIsAlarm = cv != null && cv > AppThresholds.cvAlertPct;

    return _SubCard(
      icon: Icons.thermostat_outlined,
      title: 'Egg Shell Temperature (EST)',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _MetricGrid(
            tiles: [
              _MetricTile(
                label: 'Average',
                value: avg == null || avg == 0 ? '--' : '${_one(avg)}°C',
                isAlarm: tempStatus.isAlarm,
              ),
              _MetricTile(label: 'Target', value: target.rangeLabel),
              _MetricTile(
                label: 'CV%',
                value: cv == null ? '--' : '${_one(cv)}%',
                isAlarm: cvIsAlarm,
              ),
              _MetricTile(label: 'Storage', value: target.label),
            ],
          ),
          const SizedBox(height: AppSizes.spaceMd),
          EstEvidencePhotosCard(evidence: evidence, onPhotoTap: onPhotoTap),
        ],
      ),
    );
  }
}

// ── Upside down score ─────────────────────────────────────────────────────────

class _UpsideDownCard extends StatelessWidget {
  final EggStorageTrend? latest;

  const _UpsideDownCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    return _SubCard(
      icon: Icons.flip_camera_android_outlined,
      title: 'Upside Down Score',
      child: _MetricGrid(
        tiles: [
          _MetricTile(
            label: 'Count',
            value: latest == null ? '--' : '${latest!.upsideDownCount} eggs',
          ),
          _MetricTile(
            label: 'Rate',
            value: latest == null ? '--' : '${_one(latest!.upsideDownPct)}%',
          ),
        ],
      ),
    );
  }
}

// ── storage checklist ─────────────────────────────────────────────────────────

class _StorageChecklistCard extends StatelessWidget {
  final EggStorageTrend? latest;

  const _StorageChecklistCard({required this.latest});

  @override
  Widget build(BuildContext context) {
    return _SubCard(
      icon: Icons.checklist,
      title: 'Storage Checklist',
      child: _MetricGrid(
        tiles: [
          _MetricTile(
            label: 'Storage',
            value: latest?.storageDays == null
                ? '--'
                : '${latest!.storageDays} days',
          ),
          _MetricTile(
            label: 'Turning',
            value: _turningLabel(latest?.turningTimes),
          ),
          _MetricTile(label: 'Tray spacing', value: _text(latest?.traySpacing)),
          _MetricTile(label: 'Cooler', value: _text(latest?.coolerProximity)),
          _MetricTile(
            label: 'Condensation',
            value: latest?.condensationPresent == null
                ? '--'
                : (latest!.condensationPresent! ? 'Yes' : 'No'),
            isAlarm: latest?.condensationPresent == true,
          ),
        ],
      ),
    );
  }
}

// ── egg quality: one tab per house ────────────────────────────────────────────

class _EggQualityTabs extends StatefulWidget {
  final List<ScopeGroup> houses;
  final bool isExample;

  const _EggQualityTabs({required this.houses, required this.isExample});

  @override
  State<_EggQualityTabs> createState() => _EggQualityTabsState();
}

class _EggQualityTabsState extends State<_EggQualityTabs> {
  int _selected = 0;

  @override
  Widget build(BuildContext context) {
    final houses = widget.houses;
    if (houses.isEmpty) {
      return const _SubCard(
        icon: Icons.egg_alt_outlined,
        title: 'Egg Quality',
        child: _InlineEmpty(label: 'No egg quality samples for this filter yet.'),
      );
    }
    final selected = _selected.clamp(0, houses.length - 1);
    final house = houses[selected];

    return _SubCard(
      icon: Icons.egg_alt_outlined,
      title: 'Egg Quality',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (widget.isExample) ...[
            const _ExampleBadge(),
            const SizedBox(height: AppSizes.spaceSm),
          ],
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < houses.length; i++)
                  Padding(
                    padding: EdgeInsets.only(
                      right: i == houses.length - 1 ? 0 : 6,
                    ),
                    child: _HouseTab(
                      label: houses[i].label,
                      selected: i == selected,
                      onTap: () => setState(() => _selected = i),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSizes.spaceMd),
          _EggQualityHousePanels(house: house),
          // Tabs show one house at a time; the old scope view compared houses
          // side-by-side. Keep that one tap away via a collapsible matrix.
          if (houses.length > 1) ...[
            const SizedBox(height: AppSizes.spaceSm),
            const _CompareHousesTile(),
          ],
        ],
      ),
    );
  }
}

/// Collapsible "Compare houses" reveal wrapping the per-house comparison matrix
/// (the same [ScopeMatrixTable] the generic scope view used). Built lazily — the
/// matrix is kept out of the tree until opened, so its column headers (house
/// labels) don't duplicate the tab pills and the heavy table isn't laid out
/// until asked for.
class _CompareHousesTile extends StatefulWidget {
  const _CompareHousesTile();

  @override
  State<_CompareHousesTile> createState() => _CompareHousesTileState();
}

class _CompareHousesTileState extends State<_CompareHousesTile> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        InkWell(
          onTap: () => setState(() => _open = !_open),
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    'Compare houses',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
                Icon(
                  _open ? Icons.expand_less : Icons.expand_more,
                  size: 20,
                  color: AppColors.textSecondary,
                ),
              ],
            ),
          ),
        ),
        if (_open) ...[
          const SizedBox(height: AppSizes.spaceSm),
          const ScopeMatrixTable(sectorId: 'egg_quality'),
        ],
      ],
    );
  }
}

class _HouseTab extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _HouseTab({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? AppColors.statusActive : AppColors.surfaceVariant,
          borderRadius: BorderRadius.circular(AppSizes.pillRadius),
          border: Border.all(
            color: selected ? AppColors.statusActive : AppColors.borderDefault,
          ),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : AppColors.textSecondary,
          ),
        ),
      ),
    );
  }
}

/// The selected house's egg-quality readings, split into the same two groups the
/// audit station uses: Weights & Uniformity, then Shell Quality (UV).
class _EggQualityHousePanels extends StatelessWidget {
  final ScopeGroup house;

  const _EggQualityHousePanels({required this.house});

  @override
  Widget build(BuildContext context) {
    final sample = _cellValue(house, 'eggSampleSize');
    final avgWt = _cellValue(house, 'eggAvgWeight');
    final unif = _cellValue(house, 'eggUniformityPct');
    final cv = _cellValue(house, 'eggCvPct');
    final bmk = _cellValue(house, 'eggBmkWeight');

    final affected = _cellValue(house, 'uvAffectedPct');
    final cuticle = _cellValue(house, 'uvCuticleDamagePct');
    final washed = _cellValue(house, 'uvWashedPct');
    final dirty = _cellValue(house, 'uvDirtyPct');

    final unifIsAlarm =
        unif != null && unif > 0 && unif < AppThresholds.uniformityGood;
    final cvIsAlarm = cv != null && cv > AppThresholds.cvAlertPct;
    final affectedIsAlarm = affected != null && affected > _uvAffectedLimitPct;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _PanelLabel('Weights & Uniformity'),
        const SizedBox(height: AppSizes.spaceSm),
        _MetricGrid(
          tiles: [
            _MetricTile(
              label: 'Sample',
              value: sample == null ? '--' : '${sample.round()}/100',
            ),
            _MetricTile(
              label: 'Avg wt',
              value: avgWt == null ? '--' : '${_one(avgWt.toDouble())}g',
            ),
            _MetricTile(
              label: 'Uniformity',
              value: unif == null ? '--' : '${_one(unif.toDouble())}%',
              isAlarm: unifIsAlarm,
            ),
            _MetricTile(
              label: 'CV%',
              value: cv == null ? '--' : '${_one(cv.toDouble())}%',
              isAlarm: cvIsAlarm,
            ),
            _MetricTile(
              label: 'BMK wt',
              value: bmk == null ? '--' : '${_one(bmk.toDouble())}g',
            ),
          ],
        ),
        const SizedBox(height: AppSizes.spaceMd),
        _PanelLabel('Shell Quality (UV)'),
        const SizedBox(height: AppSizes.spaceSm),
        _MetricGrid(
          tiles: [
            _MetricTile(
              label: 'Affected',
              value: affected == null ? '--' : '${_one(affected.toDouble())}%',
              isAlarm: affectedIsAlarm,
            ),
            _MetricTile(
              label: 'Cuticle',
              value: cuticle == null ? '--' : '${_one(cuticle.toDouble())}%',
            ),
            _MetricTile(
              label: 'Washed',
              value: washed == null ? '--' : '${_one(washed.toDouble())}%',
            ),
            _MetricTile(
              label: 'Dirty',
              value: dirty == null ? '--' : '${_one(dirty.toDouble())}%',
            ),
          ],
        ),
      ],
    );
  }
}

class _PanelLabel extends StatelessWidget {
  final String text;

  const _PanelLabel(this.text);

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w800),
    );
  }
}

// ── target / status helpers (mirrors the audit station's storage-day bands) ────

class _EstTarget {
  final String label;
  final int minC;
  final int maxC;

  const _EstTarget({
    required this.label,
    required this.minC,
    required this.maxC,
  });

  String get rangeLabel => '$minC-$maxC°C';

  factory _EstTarget.fromStorageDays(int? storageDays) {
    final days = storageDays ?? 0;
    if (days <= 4) {
      return const _EstTarget(label: 'Short storage', minC: 19, maxC: 21);
    }
    if (days <= 7) {
      return const _EstTarget(label: 'Medium storage', minC: 18, maxC: 20);
    }
    return const _EstTarget(label: 'Long storage', minC: 16, maxC: 18);
  }
}

class _EstTempStatus {
  final bool isAlarm;

  const _EstTempStatus({required this.isAlarm});

  factory _EstTempStatus.from(double? avg, _EstTarget target) {
    if (avg == null || avg == 0) return const _EstTempStatus(isAlarm: false);
    return _EstTempStatus(isAlarm: avg < target.minC || avg > target.maxC);
  }
}

// ── empty / example states ────────────────────────────────────────────────────

class _StorageEmptyState extends StatelessWidget {
  const _StorageEmptyState();

  @override
  Widget build(BuildContext context) {
    return const _InlineEmpty(
      label: 'No egg storage or quality data for this filter yet.',
    );
  }
}

class _InlineEmpty extends StatelessWidget {
  final String label;

  const _InlineEmpty({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: AppSizes.spaceSm),
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        border: Border.all(color: AppColors.borderDefault),
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w700,
          color: AppColors.textTertiary,
        ),
      ),
    );
  }
}

class _ExampleBadge extends StatelessWidget {
  const _ExampleBadge();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: AppColors.statusWarningBg,
        borderRadius: BorderRadius.circular(AppSizes.pillRadius),
      ),
      child: const Text(
        'Example data',
        style: TextStyle(
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.4,
          color: AppColors.scopeWarnText,
        ),
      ),
    );
  }
}
