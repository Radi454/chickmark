import '../../../data/models/lab_analysis_models.dart';

class LabElisaScopePoint {
  const LabElisaScopePoint({
    required this.date,
    required this.scope,
    required this.gmtTiter,
    required this.cvPct,
    required this.positivePct,
    required this.severity,
  });

  final DateTime date;
  final String scope;
  final double? gmtTiter;
  final double? cvPct;
  final double? positivePct;
  final LabSeverity severity;
}

class LabElisaTrendPoint {
  const LabElisaTrendPoint({
    required this.date,
    required this.scopeCount,
    required this.averageGmt,
    required this.minGmt,
    required this.maxGmt,
    required this.averageCv,
    required this.minCv,
    required this.maxCv,
    required this.positivePct,
    required this.minPositivePct,
    required this.maxPositivePct,
    this.pooledGmt,
    this.pooledCv,
    this.pooledPositivePct,
  });

  final DateTime date;
  final int scopeCount;
  final double? averageGmt;
  final double? minGmt;
  final double? maxGmt;
  final double? averageCv;
  final double? minCv;
  final double? maxCv;
  final double? positivePct;
  final double? minPositivePct;
  final double? maxPositivePct;
  final double? pooledGmt;
  final double? pooledCv;
  final double? pooledPositivePct;
}

class LabElisaTrendSeries {
  const LabElisaTrendSeries({
    required this.analyte,
    required this.points,
    required this.scopePoints,
  });

  final String analyte;
  final List<LabElisaTrendPoint> points;
  final List<LabElisaScopePoint> scopePoints;

  List<String> get scopes {
    final values = scopePoints.map((point) => point.scope).toSet().toList();
    values.sort(_compareScopes);
    return values;
  }

  static int _compareScopes(String left, String right) {
    int rank(String value) {
      final match = RegExp(r'(\d+)').firstMatch(value);
      if (match != null) return int.parse(match.group(1)!);
      if (value.toLowerCase().contains('isolation')) return 90;
      return 99;
    }

    final compared = rank(left).compareTo(rank(right));
    return compared == 0 ? left.compareTo(right) : compared;
  }
}

class LabAnalysisTrendBuilder {
  LabAnalysisTrendBuilder._();

  static List<LabElisaTrendSeries> buildElisa(
    List<LabAnalysisDashboardSummary> summaries,
  ) {
    final byAnalyte = <String, List<LabAnalysisDashboardSummary>>{};
    final labels = <String, String>{};
    for (final summary in summaries) {
      final group = summary.group;
      if (group.testType != LabTestType.elisa) continue;
      final analyte = group.analyte.trim();
      if (analyte.isEmpty) continue;
      final key = analyte.toLowerCase();
      labels.putIfAbsent(key, () => analyte);
      byAnalyte.putIfAbsent(key, () => []).add(summary);
    }

    final series = <LabElisaTrendSeries>[];
    for (final entry in byAnalyte.entries) {
      final canonicalByDate = <DateTime, List<LabAnalysisDashboardSummary>>{};
      final pooledByDate = <DateTime, List<LabAnalysisDashboardSummary>>{};
      final scopePoints = <LabElisaScopePoint>[];

      for (final summary in entry.value) {
        final day = DateTime(
          summary.group.reportDate.year,
          summary.group.reportDate.month,
          summary.group.reportDate.day,
        );
        if (_isPooledRepeat(summary.group)) {
          pooledByDate.putIfAbsent(day, () => []).add(summary);
          continue;
        }
        canonicalByDate.putIfAbsent(day, () => []).add(summary);
        scopePoints.add(
          LabElisaScopePoint(
            date: day,
            scope: _scopeLabel(summary.group),
            gmtTiter: summary.group.gmtTiter,
            cvPct: summary.group.cvPct,
            positivePct: summary.group.positivePct,
            severity: summary.group.severity,
          ),
        );
      }

      final dates = canonicalByDate.keys.toList()..sort();
      if (dates.length < 2) continue;
      final points = <LabElisaTrendPoint>[];
      for (final day in dates) {
        final canonical = canonicalByDate[day]!;
        final pooled = pooledByDate[day] ?? const [];
        final gmtValues = _values(canonical, (group) => group.gmtTiter);
        final cvValues = _values(canonical, (group) => group.cvPct);
        final positiveValues = _values(canonical, (group) => group.positivePct);
        points.add(
          LabElisaTrendPoint(
            date: day,
            scopeCount: canonical.length,
            averageGmt: _average(gmtValues),
            minGmt: _minimum(gmtValues),
            maxGmt: _maximum(gmtValues),
            averageCv: _average(cvValues),
            minCv: _minimum(cvValues),
            maxCv: _maximum(cvValues),
            positivePct: _weightedPositivePct(canonical),
            minPositivePct: _minimum(positiveValues),
            maxPositivePct: _maximum(positiveValues),
            pooledGmt: _average(_values(pooled, (group) => group.gmtTiter)),
            pooledCv: _average(_values(pooled, (group) => group.cvPct)),
            pooledPositivePct: _average(
              _values(pooled, (group) => group.positivePct),
            ),
          ),
        );
      }
      scopePoints.sort((left, right) {
        final dateOrder = left.date.compareTo(right.date);
        if (dateOrder != 0) return dateOrder;
        return LabElisaTrendSeries._compareScopes(left.scope, right.scope);
      });
      series.add(
        LabElisaTrendSeries(
          analyte: labels[entry.key]!,
          points: points,
          scopePoints: scopePoints,
        ),
      );
    }

    series.sort((left, right) {
      final dateCount = right.points.length.compareTo(left.points.length);
      if (dateCount != 0) return dateCount;
      final scopeCount = right.scopePoints.length.compareTo(
        left.scopePoints.length,
      );
      if (scopeCount != 0) return scopeCount;
      return left.analyte.compareTo(right.analyte);
    });
    return series;
  }

  static bool _isPooledRepeat(LabAnalysisGroupModel group) {
    final value =
        '${group.groupLabel} ${group.sampleScope} ${group.notes ?? ''}'
            .toLowerCase();
    return value.contains('pooled repeat') || value.contains('repeat plate');
  }

  static String _scopeLabel(LabAnalysisGroupModel group) {
    if (group.groupLabel.trim().isNotEmpty) return group.groupLabel.trim();
    if (group.sampleScope.trim().isNotEmpty) return group.sampleScope.trim();
    return 'Flock';
  }

  static List<double> _values(
    List<LabAnalysisDashboardSummary> summaries,
    double? Function(LabAnalysisGroupModel group) select,
  ) {
    return summaries
        .map((summary) => select(summary.group))
        .whereType<double>()
        .toList(growable: false);
  }

  static double? _weightedPositivePct(
    List<LabAnalysisDashboardSummary> summaries,
  ) {
    var positives = 0;
    var samples = 0;
    for (final summary in summaries) {
      final positive = summary.group.positiveCount;
      final sampleCount = summary.group.sampleCount;
      if (positive == null || sampleCount == null || sampleCount <= 0) {
        continue;
      }
      positives += positive;
      samples += sampleCount;
    }
    if (samples > 0) return positives * 100 / samples;
    return _average(_values(summaries, (group) => group.positivePct));
  }

  static double? _average(List<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left + right) / values.length;
  }

  static double? _minimum(List<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left < right ? left : right);
  }

  static double? _maximum(List<double> values) {
    if (values.isEmpty) return null;
    return values.reduce((left, right) => left > right ? left : right);
  }
}
