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
import '../../screens/photo_fullscreen_screen.dart';
import '../est_evidence_photos_card.dart';

/// Storage station body for the dashboard, laid out like the egg audit station:
/// an Alarms & Actions card first, then the EST summary + 9-point grid photo,
/// the Upside Down score, the storage checklist, and finally Egg Quality with
/// one tab per house sample.
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
    final alarms = _collectAlarms(latest, houses, target);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _AlarmsCard(alarms: alarms),
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

  /// Roll up the station's out-of-spec readings into a flat action list. EST /
  /// CV / condensation come from the pooled latest audit; uniformity / egg-CV /
  /// UV are per house (so the alarm names the offending house).
  List<_Alarm> _collectAlarms(
    EggStorageTrend? latest,
    List<ScopeGroup> houses,
    _EstTarget target,
  ) {
    final out = <_Alarm>[];
    if (latest != null) {
      final avg = _estAverage(latest);
      if (avg != null && avg != 0) {
        if (avg < target.minC) {
          out.add(
            _Alarm(
              'EST average ${_one(avg)}°C is below target (${target.rangeLabel}).',
            ),
          );
        } else if (avg > target.maxC) {
          out.add(
            _Alarm(
              'EST average ${_one(avg)}°C is above target (${target.rangeLabel}).',
            ),
          );
        }
      }
      if (latest.estCvPct > AppThresholds.cvAlertPct) {
        out.add(
          _Alarm(
            'EST CV% ${_one(latest.estCvPct)}% is above the '
            '${_one(AppThresholds.cvAlertPct)}% limit.',
          ),
        );
      }
      if (latest.condensationPresent == true) {
        out.add(const _Alarm('Condensation present in the storage room.'));
      }
    }
    for (final house in houses) {
      final label = house.label;
      final unif = _cellValue(house, 'eggUniformityPct');
      if (unif != null && unif > 0 && unif < AppThresholds.uniformityGood) {
        out.add(
          _Alarm(
            '$label: egg uniformity ${_one(unif.toDouble())}% is below the '
            '${_one(AppThresholds.uniformityGood)}% target.',
          ),
        );
      }
      final cv = _cellValue(house, 'eggCvPct');
      if (cv != null && cv > AppThresholds.cvAlertPct) {
        out.add(
          _Alarm(
            '$label: egg CV% ${_one(cv.toDouble())}% is above the '
            '${_one(AppThresholds.cvAlertPct)}% limit.',
          ),
        );
      }
      final uv = _cellValue(house, 'uvAffectedPct');
      if (uv != null && uv > _uvAffectedLimitPct) {
        out.add(
          _Alarm(
            '$label: UV affected ${_one(uv.toDouble())}% is above the '
            '${_one(_uvAffectedLimitPct)}% limit.',
          ),
        );
      }
    }
    return out;
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
/// field name predates the °C cutover). Fall back to the shell-temp average.
double? _estAverage(EggStorageTrend latest) =>
    latest.estAvgF != 0 ? latest.estAvgF : latest.shellTempC;

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

// ── alarms ───────────────────────────────────────────────────────────────────

class _Alarm {
  final String message;
  const _Alarm(this.message);
}

class _AlarmsCard extends StatelessWidget {
  final List<_Alarm> alarms;

  const _AlarmsCard({required this.alarms});

  @override
  Widget build(BuildContext context) {
    final hasAlarms = alarms.isNotEmpty;
    final accent = hasAlarms ? AppColors.statusError : AppColors.statusGood;
    final bg = hasAlarms ? AppColors.statusErrorBg : AppColors.completedBg;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: accent.withValues(alpha: 0.30)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                hasAlarms ? Icons.warning_amber_rounded : Icons.check_circle,
                size: 20,
                color: accent,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alarms & Actions Required',
                  style: AppTextStyles.title.copyWith(
                    fontWeight: FontWeight.w900,
                    color: accent,
                  ),
                ),
              ),
              if (hasAlarms)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 9,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: accent,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  ),
                  child: Text(
                    '${alarms.length}',
                    style: AppTextStyles.caption.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          if (!hasAlarms)
            Text(
              'All recorded readings are within target. No action required.',
              style: AppTextStyles.caption.copyWith(
                color: AppColors.completedText,
                fontWeight: FontWeight.w700,
              ),
            )
          else
            for (var i = 0; i < alarms.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 5),
                    child: Icon(
                      Icons.arrow_right_alt,
                      size: 16,
                      color: AppColors.statusError,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      alarms[i].message,
                      style: AppTextStyles.body.copyWith(
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF7C2D12),
                      ),
                    ),
                  ),
                ],
              ),
            ],
        ],
      ),
    );
  }
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
        ],
      ),
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
