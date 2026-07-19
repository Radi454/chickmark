import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../models/dashboard_intelligence_models.dart';
import '../providers/scope_comparison_provider.dart';
import '../scope/scope_config.dart';
import '../../settings/providers/settings_provider.dart';

class DashboardQualityStrip extends StatelessWidget {
  const DashboardQualityStrip({super.key, this.sectorId});

  final String? sectorId;

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ScopeComparisonProvider>();
    SettingsProvider? settings;
    try {
      settings = context.watch<SettingsProvider>();
    } on ProviderNotFoundException {
      // Focused widget tests may render the strip without app-wide providers.
    }
    final quality = sectorId == null
        ? _combined(provider.qualityBySector.values)
        : provider.qualityFor(sectorId!);
    if (quality.rowCount == 0 && quality.error == null) {
      return const SizedBox.shrink();
    }
    final freshness = quality.freshnessAt(DateTime.now());
    final coverage = (quality.coverage * 100).round();
    final latest = quality.latestAt;
    final latestText = latest == null
        ? 'No observation date'
        : 'Updated ${_relativeAge(latest)}';
    final policyWarning = quality.qualityFlags.contains('aggregate_drift');
    final completedStations = sectorId == null
        ? ScopeConfigRegistry.stations.where((station) {
            return ScopeConfigRegistry.forStation(
              station,
            ).any((sector) => provider.qualityFor(sector.id).rowCount > 0);
          }).length
        : 0;
    final chips = <({IconData icon, String label, Color color})>[
      (
        icon: _freshnessIcon(freshness),
        label: latestText,
        color: _freshnessColor(freshness),
      ),
      (
        icon: Icons.fact_check_outlined,
        label: '$coverage% data coverage',
        color: coverage >= 90 ? AppColors.statusGood : AppColors.statusWarning,
      ),
      (
        icon: Icons.science_outlined,
        label: '${quality.rowCount} source rows',
        color: AppColors.primary,
      ),
      if (sectorId == null)
        (
          icon: Icons.account_tree_outlined,
          label:
              '$completedStations/${ScopeConfigRegistry.stations.length} stations',
          color: completedStations == ScopeConfigRegistry.stations.length
              ? AppColors.statusGood
              : AppColors.statusWarning,
        ),
      if (quality.sampleCount > 0)
        (
          icon: Icons.numbers,
          label: '${quality.sampleCount} samples',
          color: AppColors.primary,
        ),
      if (quality.missingMetricCount > 0)
        (
          icon: Icons.rule_outlined,
          label: '${quality.missingMetricCount} missing measurements',
          color: AppColors.statusWarning,
        ),
      if (sectorId == null && settings?.lastSyncTimestamp != null)
        (
          icon: settings!.lastSyncError == null
              ? Icons.cloud_done_outlined
              : Icons.cloud_off_outlined,
          label:
              'Last synced: ${_relativeAge(DateTime.tryParse(settings.lastSyncTimestamp!)?.toLocal() ?? DateTime.now())}',
          color: settings.lastSyncError == null
              ? AppColors.statusGood
              : AppColors.statusError,
        ),
      if (quality.expectedPhotoCount > 0)
        (
          icon: Icons.photo_library_outlined,
          label:
              '${(quality.photoCoverage * 100).round()}% photo coverage (${quality.photoCount}/${quality.expectedPhotoCount})',
          color: quality.photoCoverage >= 0.8
              ? AppColors.statusGood
              : AppColors.statusWarning,
        ),
      if (quality.pendingSyncCount > 0)
        (
          icon: Icons.cloud_upload_outlined,
          label: '${quality.pendingSyncCount} pending sync',
          color: AppColors.statusWarning,
        ),
      if (quality.failedSyncCount > 0)
        (
          icon: Icons.cloud_off_outlined,
          label: '${quality.failedSyncCount} sync failed',
          color: AppColors.statusError,
        ),
      if (policyWarning)
        (
          icon: Icons.rule_folder_outlined,
          label: 'Raw and summary values need review',
          color: AppColors.statusError,
        ),
      if (quality.error != null)
        (
          icon: Icons.error_outline,
          label: 'Section could not refresh',
          color: AppColors.statusError,
        ),
    ];
    return Semantics(
      label: chips.map((chip) => context.tr(chip.label)).join(', '),
      child: Wrap(
        spacing: 6,
        runSpacing: 6,
        children: [
          for (final chip in chips)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
              decoration: BoxDecoration(
                color: chip.color.withValues(alpha: 0.10),
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                border: Border.all(color: chip.color.withValues(alpha: 0.24)),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(chip.icon, size: 14, color: chip.color),
                  const SizedBox(width: 5),
                  Text(
                    chip.label,
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                      color: chip.color,
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  DashboardDataQuality _combined(Iterable<DashboardDataQuality> values) {
    DateTime? latest;
    var rows = 0;
    var samples = 0;
    var ages = 0;
    var missing = 0;
    var expected = 0;
    var photos = 0;
    var expectedPhotos = 0;
    var failed = 0;
    var pending = 0;
    final flags = <String>{};
    String? error;
    for (final quality in values) {
      if (quality.latestAt != null &&
          (latest == null || quality.latestAt!.isAfter(latest))) {
        latest = quality.latestAt;
      }
      rows += quality.rowCount;
      samples += quality.sampleCount;
      ages += quality.ageCount;
      missing += quality.missingMetricCount;
      expected += quality.expectedMetricCount;
      photos += quality.photoCount;
      expectedPhotos += quality.expectedPhotoCount;
      failed += quality.failedSyncCount;
      pending += quality.pendingSyncCount;
      flags.addAll(quality.qualityFlags);
      error ??= quality.error;
    }
    return DashboardDataQuality(
      latestAt: latest,
      rowCount: rows,
      sampleCount: samples,
      ageCount: ages,
      missingMetricCount: missing,
      expectedMetricCount: expected,
      photoCount: photos,
      expectedPhotoCount: expectedPhotos,
      failedSyncCount: failed,
      pendingSyncCount: pending,
      qualityFlags: flags,
      error: error,
    );
  }

  static String _relativeAge(DateTime value) {
    final age = DateTime.now().difference(value);
    if (age.isNegative) return 'at an invalid future time';
    if (age.inMinutes < 60) return '${age.inMinutes} min ago';
    if (age.inHours < 48) return '${age.inHours} h ago';
    return '${age.inDays} d ago';
  }

  static IconData _freshnessIcon(DashboardFreshness freshness) =>
      switch (freshness) {
        DashboardFreshness.current => Icons.update,
        DashboardFreshness.aging => Icons.schedule,
        DashboardFreshness.stale => Icons.history,
        DashboardFreshness.invalid => Icons.warning_amber,
        DashboardFreshness.missing => Icons.help_outline,
      };

  static Color _freshnessColor(DashboardFreshness freshness) =>
      switch (freshness) {
        DashboardFreshness.current => AppColors.statusGood,
        DashboardFreshness.aging => AppColors.statusWarning,
        DashboardFreshness.stale => AppColors.textSecondary,
        DashboardFreshness.invalid => AppColors.statusError,
        DashboardFreshness.missing => AppColors.textSecondary,
      };
}
