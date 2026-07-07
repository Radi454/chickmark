import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../providers/app_provider.dart';
import '../../../services/govee/govee_service.dart';
import '../../dashboard/models/govee_capture_summary.dart';
import '../../dashboard/widgets/govee_capture_chart.dart';
import 'package:provider/provider.dart';

/// Compact plot height for the live preview charts so the Govee main card and
/// both charts stay visible together without scrolling on a phone.
const double _previewPlotHeight = 114.0;

class GoveeChartPreview extends StatelessWidget {
  final List<GoveeSensorReading> readings;
  final String? machineId;

  const GoveeChartPreview({super.key, required this.readings, this.machineId});

  @override
  Widget build(BuildContext context) {
    final points = _previewPoints();
    if (points.isEmpty) return const SizedBox.shrink();
    final showCelsius =
        context.watch<AppProvider>().tempUnit == TempUnit.celsius;
    final tempUnit = showCelsius ? '°C' : 'F';
    final tempValues = points
        .map(
          (point) =>
              _temperatureValue(point.temperatureFahrenheit, showCelsius),
        )
        .toList(growable: false);
    final rhValues = points
        .map((point) => point.humidity)
        .toList(growable: false);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        GoveeMetricChart(
          chartKey: const ValueKey('govee-temperature-preview-chart'),
          title: 'Temperature',
          points: points,
          valueFor: (point) =>
              _temperatureValue(point.temperatureFahrenheit, showCelsius),
          unit: tempUnit,
          color: AppColors.chart1,
          average: _average(tempValues),
          minimum: _min(tempValues),
          maximum: _max(tempValues),
          tooltipTextFor: (point) =>
              _tooltipText(point, showCelsius: showCelsius),
          interactionEnabled: false,
          compact: true,
          plotHeight: _previewPlotHeight,
        ),
        const SizedBox(height: AppSizes.spaceSm),
        GoveeMetricChart(
          chartKey: const ValueKey('govee-rh-preview-chart'),
          title: 'Relative Humidity',
          points: points,
          valueFor: (point) => point.humidity,
          unit: '%',
          color: AppColors.chart2,
          average: _average(rhValues),
          minimum: _min(rhValues),
          maximum: _max(rhValues),
          tooltipTextFor: (point) =>
              _tooltipText(point, showCelsius: showCelsius),
          interactionEnabled: false,
          compact: true,
          plotHeight: _previewPlotHeight,
        ),
        const SizedBox(height: AppSizes.spaceSm),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            _PreviewPill(label: '${readings.length} live readings'),
            if (machineId != null) _PreviewPill(label: machineId!),
          ],
        ),
      ],
    );
  }

  List<GoveeChartPoint> _previewPoints() {
    final points = <GoveeChartPoint>[];
    for (var i = 0; i < readings.length; i += 1) {
      final reading = readings[i];
      if (reading.temperatureFahrenheit == null || reading.humidity == null) {
        continue;
      }
      points.add(
        GoveeChartPoint(
          x: reading.timestamp.millisecondsSinceEpoch.toDouble(),
          temperatureFahrenheit: reading.temperatureFahrenheit!,
          humidity: reading.humidity!,
          recordedAt: reading.timestamp,
        ),
      );
    }
    return points;
  }

  String _tooltipText(GoveeChartPoint point, {required bool showCelsius}) {
    final tempUnit = showCelsius ? '°C' : 'F';
    return [
      _exactTimestamp(point.recordedAt),
      'Temp ${_temperatureValue(point.temperatureFahrenheit, showCelsius).toStringAsFixed(1)}$tempUnit',
      'RH ${point.humidity.toStringAsFixed(1)}%',
      ?machineId,
    ].join('\n');
  }

  double _average(List<double> values) {
    return CalculationUtils.average(values);
  }

  double _min(List<double> values) => CalculationUtils.minValue(values)!;

  double _max(List<double> values) => CalculationUtils.maxValue(values)!;

  double _temperatureValue(double fahrenheit, bool showCelsius) {
    return showCelsius ? TempConverter.toCelsius(fahrenheit) : fahrenheit;
  }

  String _exactTimestamp(DateTime timestamp) {
    return HatchDateUtils.formatDisplayTimestamp(timestamp);
  }
}

class _PreviewPill extends StatelessWidget {
  final String label;

  const _PreviewPill({required this.label});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      decoration: BoxDecoration(
        color: AppColors.statusNeutralBg,
        borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
      ),
      child: Text(
        label,
        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700),
      ),
    );
  }
}
