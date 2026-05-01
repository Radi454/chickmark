import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../temperature/providers/temperature_rh_provider.dart';

class GoveeRecordingCard extends StatefulWidget {
  final TemperaturePlace place;
  final String auditSessionId;
  final String label;

  const GoveeRecordingCard({
    super.key,
    required this.place,
    required this.auditSessionId,
    required this.label,
  });

  @override
  State<GoveeRecordingCard> createState() => _GoveeRecordingCardState();
}

class _GoveeRecordingCardState extends State<GoveeRecordingCard> {
  bool _celsius = true;
  TemperatureRhProvider? _temperatureProvider;
  String? _tempSessionId;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _temperatureProvider = context.read<TemperatureRhProvider>();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tempSessionId = _temperatureProvider?.startAuditSession(
        widget.place,
        widget.auditSessionId,
        spotLabel: widget.label,
      );
    });
  }

  @override
  void dispose() {
    unawaited(
      _temperatureProvider?.stopAndSaveAuditSession(
        expectedTempSessionId: _tempSessionId,
      ),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TemperatureRhProvider>();
    final readings = provider.auditCompressedReadings;
    final connected = provider.isSensorConnected;
    final isRecording = provider.isAuditRecording;

    final last = readings.isEmpty ? null : readings.last;
    final rssi = last?.rssi ?? provider.signalStrength;
    final battery = last != null ? null : provider.batteryPercent;
    final updatedAt = last?.recordedAt ?? provider.liveUpdatedAt;

    final temps = readings.map((r) => r.temperatureFahrenheit).toList();
    final rhs = readings.map((r) => r.humidity).toList();

    final avgTemp = temps.isEmpty
        ? null
        : temps.reduce((a, b) => a + b) / temps.length;
    final minTemp = temps.isEmpty ? null : temps.reduce(math.min);
    final maxTemp = temps.isEmpty ? null : temps.reduce(math.max);
    final avgRh = rhs.isEmpty ? null : rhs.reduce((a, b) => a + b) / rhs.length;
    final minRh = rhs.isEmpty ? null : rhs.reduce(math.min);
    final maxRh = rhs.isEmpty ? null : rhs.reduce(math.max);

    final formattedTemp = last != null
        ? TempConverter.display(
            last.temperatureFahrenheit,
            showCelsius: _celsius,
          )
        : '--';
    final formattedRh = last != null
        ? '${last.humidity.toStringAsFixed(1)}%'
        : '--';
    final formattedAvgTemp = avgTemp != null
        ? TempConverter.display(avgTemp, showCelsius: _celsius)
        : '--';
    final formattedAvgRh = avgRh != null
        ? '${avgRh.toStringAsFixed(1)}%'
        : '--';
    final formattedMinTemp = minTemp != null
        ? TempConverter.display(minTemp, showCelsius: _celsius)
        : '--';
    final formattedMaxTemp = maxTemp != null
        ? TempConverter.display(maxTemp, showCelsius: _celsius)
        : '--';
    final formattedMinRh = minRh != null
        ? '${minRh.toStringAsFixed(1)}%'
        : '--';
    final formattedMaxRh = maxRh != null
        ? '${maxRh.toStringAsFixed(1)}%'
        : '--';

    final muted = !connected;

    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.cardBackground,
        borderRadius: BorderRadius.circular(12),
        boxShadow: const [
          BoxShadow(
            color: AppColors.cardShadow,
            blurRadius: AppSizes.cardShadowBlur,
            offset: Offset(0, AppSizes.cardShadowOffsetY),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w600,
                    color: muted ? Colors.grey : null,
                  ),
                ),
              ),
              if (connected && isRecording)
                _liveBadge()
              else if (!connected)
                _disconnectedBadge(),
              if (connected && isRecording) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  onTap: () => setState(() => _celsius = !_celsius),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 5,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.ageBadgeBg,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      _celsius ? '°C' : '°F',
                      style: AppTextStyles.caption.copyWith(
                        fontWeight: FontWeight.w700,
                        color: AppColors.primary,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _metricCard(
                  icon: Icons.thermostat,
                  label: formattedTemp,
                  subLabel: 'avg $formattedAvgTemp',
                  rangeLabel: 'min $formattedMinTemp  max $formattedMaxTemp',
                  muted: muted,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _metricCard(
                  icon: Icons.water_drop_outlined,
                  label: formattedRh,
                  subLabel: 'avg $formattedAvgRh',
                  rangeLabel: 'min $formattedMinRh  max $formattedMaxRh',
                  muted: muted,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (readings.length >= 2)
            SizedBox(height: 120, child: _buildChart(readings))
          else
            Container(
              width: double.infinity,
              height: 120,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: const Color(0xFFF7FAFD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFE0E7EF)),
              ),
              child: Text(
                'Warming up…',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  [
                    if (updatedAt != null) 'Updated ${_formatTime(updatedAt)}',
                    if (rssi != null) 'RSSI $rssi',
                    if (battery != null) 'Battery $battery%',
                    '${readings.length} pts',
                  ].join(' · '),
                  style: AppTextStyles.caption.copyWith(
                    color: muted ? Colors.grey : Colors.black54,
                  ),
                ),
              ),
              if (!connected)
                TextButton(
                  onPressed: () =>
                      context.read<TemperatureRhProvider>().connectSensor(),
                  child: const Text('Reconnect'),
                ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _liveBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.greenTab.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 6,
            height: 6,
            decoration: const BoxDecoration(
              color: AppColors.greenTab,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: AppTextStyles.caption.copyWith(
              color: AppColors.greenTab,
              fontWeight: FontWeight.w700,
              fontSize: 10,
            ),
          ),
        ],
      ),
    );
  }

  Widget _disconnectedBadge() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        'Disconnected',
        style: AppTextStyles.caption.copyWith(
          color: Colors.grey[600],
          fontWeight: FontWeight.w600,
          fontSize: 10,
        ),
      ),
    );
  }

  Widget _metricCard({
    required IconData icon,
    required String label,
    required String subLabel,
    required String rangeLabel,
    required bool muted,
  }) {
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: const Color(0xFFF5F8FC),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: muted ? Colors.grey[300]! : const Color(0xFFE0E7EF),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                icon,
                size: 16,
                color: muted ? Colors.grey : AppColors.primary,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                    fontSize: 17,
                    color: muted ? Colors.grey : null,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            subLabel,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: muted ? Colors.grey : Colors.black54,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            rangeLabel,
            style: AppTextStyles.caption.copyWith(
              fontSize: 11,
              color: muted ? Colors.grey : Colors.black54,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildChart(List<TemperatureReadingModel> readings) {
    final tempSpots = <FlSpot>[];
    final rhSpots = <FlSpot>[];

    for (var i = 0; i < readings.length; i++) {
      tempSpots.add(FlSpot(i.toDouble(), readings[i].temperatureFahrenheit));
      rhSpots.add(FlSpot(i.toDouble(), readings[i].humidity));
    }

    return LineChart(
      LineChartData(
        minX: 0,
        maxX: (readings.length - 1).toDouble().clamp(1, double.infinity),
        minY: _chartMin(tempSpots, rhSpots),
        maxY: _chartMax(tempSpots, rhSpots),
        clipData: const FlClipData.all(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: _chartInterval(
            _chartMin(tempSpots, rhSpots),
            _chartMax(tempSpots, rhSpots),
          ),
          getDrawingHorizontalLine: (_) =>
              FlLine(color: const Color(0xFFE2EAF2), strokeWidth: 1),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  value.toStringAsFixed(value.abs() >= 100 ? 0 : 1),
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.black54,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          ),
          rightTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 36,
              getTitlesWidget: (value, meta) => SideTitleWidget(
                meta: meta,
                child: Text(
                  value.toStringAsFixed(0),
                  style: AppTextStyles.caption.copyWith(
                    color: Colors.black54,
                    fontSize: 9,
                  ),
                ),
              ),
            ),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
        ),
        lineBarsData: [
          LineChartBarData(
            spots: tempSpots,
            isCurved: true,
            curveSmoothness: 0.22,
            color: AppColors.primary,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
          LineChartBarData(
            spots: rhSpots,
            isCurved: true,
            curveSmoothness: 0.22,
            color: Colors.green,
            barWidth: 2,
            isStrokeCapRound: true,
            dotData: FlDotData(show: false),
            belowBarData: BarAreaData(show: false),
          ),
        ],
      ),
      duration: const Duration(milliseconds: 150),
    );
  }

  double _chartMin(List<FlSpot> tempSpots, List<FlSpot> rhSpots) {
    final allY = [...tempSpots.map((s) => s.y), ...rhSpots.map((s) => s.y)];
    if (allY.isEmpty) return 0;
    final minY = allY.reduce(math.min);
    return minY - 5;
  }

  double _chartMax(List<FlSpot> tempSpots, List<FlSpot> rhSpots) {
    final allY = [...tempSpots.map((s) => s.y), ...rhSpots.map((s) => s.y)];
    if (allY.isEmpty) return 100;
    final maxY = allY.reduce(math.max);
    return maxY + 5;
  }

  double _chartInterval(double minY, double maxY) {
    return math.max((maxY - minY) / 3, 1.0);
  }

  String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
