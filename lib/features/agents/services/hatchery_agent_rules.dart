import '../../../data/repositories/benchmark_lookup.dart';
import '../../../data/repositories/hatchery_agent_repository.dart';

enum HatcheryRowWarningKind {
  historicalChange,
  bmkContext,
  missingBmk,
  missingFlockAge,
  identityResolution,
}

enum HatcheryRowWarningSeverity { info, review, critical }

class HatcheryRowWarning {
  const HatcheryRowWarning({
    required this.kind,
    required this.severity,
    required this.messageEn,
    required this.messageAr,
    this.previousPct,
    this.currentPct,
    this.bmkPct,
    this.flockAgeWeeks,
  });

  final HatcheryRowWarningKind kind;
  final HatcheryRowWarningSeverity severity;
  final String messageEn;
  final String messageAr;
  final double? previousPct;
  final double? currentPct;
  final double? bmkPct;
  final int? flockAgeWeeks;

  factory HatcheryRowWarning.fromJson(Map<String, Object?> json) {
    return HatcheryRowWarning(
      kind: _warningKind(json['kind']),
      severity: _warningSeverity(json['severity']),
      messageEn: json['messageEn']?.toString() ?? '',
      messageAr: json['messageAr']?.toString() ?? '',
      previousPct: _double(json['previousPct']),
      currentPct: _double(json['currentPct']),
      bmkPct: _double(json['bmkPct']),
      flockAgeWeeks: _int(json['flockAgeWeeks']),
    );
  }

  Map<String, Object?> toJson() => {
    'kind': kind.name,
    'severity': severity.name,
    'messageEn': messageEn,
    'messageAr': messageAr,
    'previousPct': previousPct,
    'currentPct': currentPct,
    'bmkPct': bmkPct,
    'flockAgeWeeks': flockAgeWeeks,
  };
}

double? calculateHatchabilityPct({
  required int? totalProduction,
  required int? eggsPlaced,
}) {
  if (totalProduction == null || eggsPlaced == null || eggsPlaced <= 0) {
    return null;
  }
  if (totalProduction < 0) return null;
  return totalProduction / eggsPlaced * 100;
}

HatcheryRowWarning? buildHistoricalWarning({
  required double currentPct,
  required double? previousPct,
  double thresholdPoints = 3,
}) {
  if (previousPct == null) return null;

  final absoluteChange = (currentPct - previousPct).abs();
  if (absoluteChange + _percentagePointComparisonTolerance < thresholdPoints) {
    return null;
  }

  return HatcheryRowWarning(
    kind: HatcheryRowWarningKind.historicalChange,
    severity: HatcheryRowWarningSeverity.review,
    messageEn:
        'Hatchability changed from ${_pct(previousPct)}% to '
        '${_pct(currentPct)}% (${_pct(absoluteChange)} percentage points).',
    messageAr:
        'تغيرت قابلية الفقس من ${_pct(previousPct)}٪ إلى '
        '${_pct(currentPct)}٪ (${_pct(absoluteChange)} نقطة مئوية).',
    previousPct: previousPct,
    currentPct: currentPct,
  );
}

HatcheryRowWarning? buildBmkWarning({
  required double currentPct,
  required double? previousPct,
  required double? bmkPct,
  required int? flockAgeWeeks,
}) {
  final isRising = previousPct != null && currentPct > previousPct;
  if (!isRising) return null;

  if (flockAgeWeeks == null || flockAgeWeeks <= 0) {
    return HatcheryRowWarning(
      kind: HatcheryRowWarningKind.missingFlockAge,
      severity: HatcheryRowWarningSeverity.info,
      messageEn:
          'Flock age is needed to compare this rising hatchability result with BMK.',
      messageAr:
          'يلزم عمر القطيع لمقارنة نتيجة قابلية الفقس المرتفعة هذه بالمعيار.',
      previousPct: previousPct,
      currentPct: currentPct,
    );
  }

  if (bmkPct == null) {
    return HatcheryRowWarning(
      kind: HatcheryRowWarningKind.missingBmk,
      severity: HatcheryRowWarningSeverity.info,
      messageEn:
          'No hatchability BMK is available for this breed and flock age.',
      messageAr: 'لا يتوفر معيار قابلية فقس لهذه السلالة وعمر القطيع.',
      previousPct: previousPct,
      currentPct: currentPct,
      flockAgeWeeks: flockAgeWeeks,
    );
  }

  if (bmkPct < currentPct) return null;

  return HatcheryRowWarning(
    kind: HatcheryRowWarningKind.bmkContext,
    severity: HatcheryRowWarningSeverity.info,
    messageEn:
        'The hatchability increase may be consistent with the BMK of '
        '${_pct(bmkPct)}% at $flockAgeWeeks weeks.',
    messageAr:
        'قد تكون زيادة قابلية الفقس متسقة مع المعيار البالغ '
        '${_pct(bmkPct)}٪ عند عمر $flockAgeWeeks أسبوعًا.',
    previousPct: previousPct,
    currentPct: currentPct,
    bmkPct: bmkPct,
    flockAgeWeeks: flockAgeWeeks,
  );
}

class HatcheryAgentRuleEngine {
  HatcheryAgentRuleEngine({
    HatcheryAgentRepository? repository,
    BenchmarkLookup? benchmarkLookup,
  }) : _repository = repository ?? HatcheryAgentRepository(),
       _benchmarkLookup = benchmarkLookup ?? BenchmarkLookup();

  final HatcheryAgentRepository _repository;
  final BenchmarkLookup _benchmarkLookup;

  Future<List<HatcheryRowWarning>> buildReviewWarnings({
    required String customerId,
    required String flockId,
    required String stationName,
    required String breed,
    required DateTime hatchDate,
    required double currentHatchabilityPct,
    required int? flockAgeWeeks,
    double thresholdPoints = 3,
  }) async {
    final previous = await _repository.previousApprovedComparable(
      customerId: customerId,
      flockId: flockId,
      stationName: stationName,
      breed: breed,
      hatchDate: hatchDate,
    );
    final previousPct = previous?.hatchabilityPct;
    final warnings = <HatcheryRowWarning>[];
    final historicalWarning = buildHistoricalWarning(
      currentPct: currentHatchabilityPct,
      previousPct: previousPct,
      thresholdPoints: thresholdPoints,
    );
    if (historicalWarning != null) warnings.add(historicalWarning);

    final hasValidFlockAge = flockAgeWeeks != null && flockAgeWeeks > 0;
    Map<String, Object?>? benchmark;
    if (hasValidFlockAge) {
      benchmark = await _benchmarkLookup.nearestBreedBenchmark(
        calculatedBmkAgeDays: flockAgeWeeks * 7,
        breed: breed,
      );
    }
    final bmkWarning = buildBmkWarning(
      currentPct: currentHatchabilityPct,
      previousPct: previousPct,
      bmkPct: _double(benchmark?['hatchabilityPct']),
      flockAgeWeeks: _int(benchmark?['ageWeek']) ?? flockAgeWeeks,
    );
    if (bmkWarning != null) warnings.add(bmkWarning);

    return warnings;
  }
}

HatcheryRowWarningKind _warningKind(Object? value) {
  final name = value?.toString();
  return HatcheryRowWarningKind.values.firstWhere(
    (kind) => kind.name == name,
    orElse: () => throw FormatException('Unknown warning kind: $name'),
  );
}

HatcheryRowWarningSeverity _warningSeverity(Object? value) {
  final name = value?.toString();
  return HatcheryRowWarningSeverity.values.firstWhere(
    (severity) => severity.name == name,
    orElse: () => throw FormatException('Unknown warning severity: $name'),
  );
}

double? _double(Object? value) {
  if (value is num) return value.toDouble();
  return double.tryParse(value?.toString() ?? '');
}

int? _int(Object? value) {
  if (value is num) return value.toInt();
  return int.tryParse(value?.toString() ?? '');
}

String _pct(double value) => value.toStringAsFixed(1);

const _percentagePointComparisonTolerance = 1e-12;
