import '../../../../data/models/temperature_rh_model.dart';
import '../../models/govee_capture_summary.dart';
import '../../scope/scope_models.dart';
import '../../scope/scope_severity.dart';
import 'alarm_triage_feed.dart';

/// Per-place environmental targets. Temperatures are °C. A place with both
/// [tempMin] and [tempMax] is graded as a band; with only [tempMax] as a soft
/// ceiling. [rhMax] is a soft RH ceiling. Values confirmed against the V5
/// prototype (inside-hatcher band, hatcher-room RH, chick-holding) are exact;
/// the rest are sensible incubation defaults — tune as field data dictates.
class _GoveeTarget {
  final double? tempMin;
  final double? tempMax;
  final double? rhMax;

  const _GoveeTarget({this.tempMin, this.tempMax, this.rhMax});

  static _GoveeTarget? forPlace(TemperaturePlace place) {
    switch (place) {
      case TemperaturePlace.insideSetter:
        return const _GoveeTarget(tempMin: 37.4, tempMax: 37.8);
      case TemperaturePlace.insideHatcher:
        return const _GoveeTarget(tempMin: 36.7, tempMax: 37.2);
      case TemperaturePlace.setterRoom:
        return const _GoveeTarget(tempMin: 23, tempMax: 25, rhMax: 60);
      case TemperaturePlace.hatcherRoom:
        return const _GoveeTarget(tempMin: 23, tempMax: 25, rhMax: 65);
      case TemperaturePlace.eggStorageRoom:
        return const _GoveeTarget(tempMin: 16, tempMax: 21, rhMax: 80);
      case TemperaturePlace.chickHoldingArea:
        return const _GoveeTarget(tempMax: 25, rhMax: 70);
      case TemperaturePlace.outsideHatchery:
        return null;
    }
  }
}

/// Build triage items from the latest Govee capture per place: one Temperature
/// item and (where a target exists) one Relative Humidity item, graded against
/// [_GoveeTarget]. In-target readings emit as `good` for the collapsible list.
List<TriageItem> goveeTriageItems(List<GoveeCaptureSummary> captures) {
  final latest = <TemperaturePlace, GoveeCaptureSummary>{};
  for (final s in captures) {
    final place = s.capture.place;
    final cur = latest[place];
    // captureDate is an ISO date string (sorts lexically).
    if (cur == null ||
        s.capture.captureDate.compareTo(cur.capture.captureDate) > 0) {
      latest[place] = s;
    }
  }

  final out = <TriageItem>[];
  final places = latest.keys.toList()
    ..sort((a, b) => a.index.compareTo(b.index));

  for (final place in places) {
    final target = _GoveeTarget.forPlace(place);
    if (target == null) continue;
    final summary = latest[place]!;
    final points = summary.combinedPoints;
    if (points.isEmpty) continue;

    final scopeTag = (summary.capture.machineId ?? '').trim();
    final tag = scopeTag.isEmpty ? null : scopeTag;

    if (target.tempMin != null || target.tempMax != null) {
      final avgC = _avg(points.map((p) => _fToC(p.temperatureFahrenheit)));
      out.add(_tempItem(place.label, tag, avgC, target));
    }
    if (target.rhMax != null) {
      final avgRh = _avg(points.map((p) => p.humidity));
      out.add(_rhItem(place.label, tag, avgRh, target.rhMax!));
    }
  }

  out.sort((a, b) => _rank(b.severity).compareTo(_rank(a.severity)));
  return out;
}

TriageItem _tempItem(
  String placeLabel,
  String? tag,
  double avgC,
  _GoveeTarget target,
) {
  final ScopeSeverity sev;
  final String context;
  if (target.tempMin != null && target.tempMax != null) {
    final min = target.tempMin!, max = target.tempMax!;
    context = 'Band ${_one(min)}–${_one(max)} °C';
    if (avgC >= min && avgC <= max) {
      sev = ScopeSeverity.good;
    } else {
      final out = avgC > max ? avgC - max : min - avgC;
      sev = out > 1.0 ? ScopeSeverity.err : ScopeSeverity.warn;
    }
  } else {
    final max = target.tempMax!;
    context = 'Target ≤ ${_one(max)} °C';
    sev = ceilingSeverity(avgC, max, 2.0);
  }
  return TriageItem(
    severity: sev,
    primaryTag: placeLabel,
    secondaryTag: tag,
    metric: 'Temperature',
    value: '${_one(avgC)} °C',
    context: context,
    advice: _advice(sev, 'temperature'),
  );
}

TriageItem _rhItem(String placeLabel, String? tag, double avgRh, double max) {
  final sev = ceilingSeverity(avgRh, max, 8.0);
  return TriageItem(
    severity: sev,
    primaryTag: placeLabel,
    secondaryTag: tag,
    metric: 'Relative Humidity',
    value: '${avgRh.round()}%',
    context: 'Target ≤ ${max.round()}%',
    advice: _advice(sev, 'humidity'),
  );
}

String? _advice(ScopeSeverity sev, String what) {
  switch (sev) {
    case ScopeSeverity.err:
      return 'Out of range — check ventilation / set-point now.';
    case ScopeSeverity.warn:
      return 'Drifting on $what — monitor the trend.';
    case ScopeSeverity.good:
    case ScopeSeverity.pool:
      return null;
  }
}

double _fToC(double f) => (f - 32) * 5 / 9;

double _avg(Iterable<double> xs) {
  var sum = 0.0;
  var n = 0;
  for (final x in xs) {
    sum += x;
    n++;
  }
  return n == 0 ? 0 : sum / n;
}

String _one(double v) => v.toStringAsFixed(1);

int _rank(ScopeSeverity s) {
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
