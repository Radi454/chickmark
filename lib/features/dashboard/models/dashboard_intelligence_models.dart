import '../scope/scope_config.dart';
import '../scope/scope_models.dart';
import 'scope_cumulative.dart';

enum DashboardFreshness { current, aging, stale, invalid, missing }

enum MetricTrendState {
  newIssue,
  persistent,
  improving,
  worsening,
  resolved,
  stable,
  insufficient,
}

class ScopeDataBundle {
  const ScopeDataBundle({
    this.leavesBySector = const {},
    this.periodsBySector = const {},
    this.observationsBySector = const {},
    this.qualityBySector = const {},
    this.errorsBySector = const {},
  });

  final Map<String, List<ScopeLeafRow>> leavesBySector;
  final Map<String, List<ScopePeriod>> periodsBySector;
  final Map<String, List<MetricObservation>> observationsBySector;
  final Map<String, DashboardDataQuality> qualityBySector;
  final Map<String, String> errorsBySector;
}

class MetricObservation {
  const MetricObservation({
    required this.tableName,
    required this.rowId,
    required this.sessionId,
    required this.customerId,
    required this.hatcheryId,
    this.flockId,
    required this.sectorId,
    required this.metricKey,
    required this.metricLabel,
    required this.policy,
    required this.observedAt,
    this.bmkAge,
    this.value,
    this.numerator,
    this.denominator,
    this.sampleCount = 0,
    this.layerSegments = const {},
    this.qualityFlags = const {},
  });

  final String tableName;
  final String rowId;
  final String sessionId;
  final String customerId;
  final String hatcheryId;
  final String? flockId;
  final String sectorId;
  final String metricKey;
  final String metricLabel;
  final ScopeAggregationPolicy policy;
  final DateTime observedAt;
  final int? bmkAge;
  final num? value;
  final num? numerator;
  final num? denominator;
  final int sampleCount;
  final Map<Object, String> layerSegments;
  final Set<String> qualityFlags;
}

class DashboardDataQuality {
  const DashboardDataQuality({
    this.latestAt,
    this.rowCount = 0,
    this.sampleCount = 0,
    this.ageCount = 0,
    this.missingMetricCount = 0,
    this.expectedMetricCount = 0,
    this.photoCount = 0,
    this.expectedPhotoCount = 0,
    this.failedSyncCount = 0,
    this.pendingSyncCount = 0,
    this.qualityFlags = const {},
    this.error,
  });

  final DateTime? latestAt;
  final int rowCount;
  final int sampleCount;
  final int ageCount;
  final int missingMetricCount;
  final int expectedMetricCount;
  final int photoCount;
  final int expectedPhotoCount;
  final int failedSyncCount;
  final int pendingSyncCount;
  final Set<String> qualityFlags;
  final String? error;

  double get coverage => expectedMetricCount == 0
      ? 0
      : (expectedMetricCount - missingMetricCount) / expectedMetricCount;

  double get photoCoverage =>
      expectedPhotoCount == 0 ? 0 : photoCount / expectedPhotoCount;

  DashboardFreshness freshnessAt(
    DateTime now, {
    Duration currentFor = const Duration(days: 2),
    Duration agingFor = const Duration(days: 7),
  }) {
    final latest = latestAt;
    if (latest == null) return DashboardFreshness.missing;
    if (latest.isAfter(now.add(const Duration(minutes: 5)))) {
      return DashboardFreshness.invalid;
    }
    final age = now.difference(latest);
    if (age <= currentFor) return DashboardFreshness.current;
    if (age <= agingFor) return DashboardFreshness.aging;
    return DashboardFreshness.stale;
  }
}

class HistoricalMetricComparison {
  const HistoricalMetricComparison({
    required this.sectorId,
    required this.metricKey,
    this.latestValue,
    this.previousValue,
    this.latestAt,
    this.previousAt,
    this.state = MetricTrendState.insufficient,
  });

  final String sectorId;
  final String metricKey;
  final num? latestValue;
  final num? previousValue;
  final DateTime? latestAt;
  final DateTime? previousAt;
  final MetricTrendState state;

  num? get delta => latestValue == null || previousValue == null
      ? null
      : latestValue! - previousValue!;
}

class DashboardFinding {
  const DashboardFinding({
    required this.key,
    required this.station,
    required this.sectorId,
    required this.metricKey,
    required this.metricLabel,
    required this.valueText,
    required this.severity,
    required this.rank,
    this.context = '',
    this.advice,
    this.latestAt,
    this.confidence = 1,
    this.history,
    this.sessionId,
    this.panelName,
    this.panelRowId,
  });

  final String key;
  final String station;
  final String sectorId;
  final String metricKey;
  final String metricLabel;
  final String valueText;
  final ScopeSeverity severity;
  final double rank;
  final String context;
  final String? advice;
  final DateTime? latestAt;
  final double confidence;
  final HistoricalMetricComparison? history;
  final String? sessionId;
  final String? panelName;
  final String? panelRowId;
}
