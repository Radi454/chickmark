import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/temp_converter.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../../providers/app_provider.dart';
import '../../../providers/customers_provider.dart';
import '../../../widgets/status_badge.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/temperature_rh_provider.dart';
import '../widgets/temperature_rh_panel.dart';

class TemperatureRhScreen extends StatefulWidget {
  const TemperatureRhScreen({super.key});

  @override
  State<TemperatureRhScreen> createState() => _TemperatureRhScreenState();
}

class _TemperatureRhScreenState extends State<TemperatureRhScreen> {
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      context.read<TemperatureRhProvider>().ensureInitialized();
      context.read<TemperatureRhProvider>().loadMeasureLog();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: const GradientAppBar(title: 'Temperature/RH'),
      body: Consumer3<TemperatureRhProvider, CustomersProvider, AppProvider>(
        builder: (context, measureProvider, customersProvider, appProvider, _) {
          final loading =
              measureProvider.isLoadingMeasureLog ||
              customersProvider.isLoading;
          final sessions = _filterSessions(measureProvider, customersProvider);
          final showCelsius = appProvider.tempUnit == TempUnit.celsius;

          return Column(
            children: [
              _buildSearchBar(),
              if (loading)
                const Expanded(
                  child: Center(child: CircularProgressIndicator()),
                )
              else
                Expanded(
                  child: _buildMeasureList(
                    measureProvider,
                    customersProvider,
                    sessions,
                    showCelsius,
                  ),
                ),
            ],
          );
        },
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'temperature-record-measures-fab',
        onPressed: _openRecorder,
        backgroundColor: AppColors.primary,
        tooltip: 'Record measures',
        child: const Icon(Icons.thermostat_auto, color: Colors.white),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: TextField(
        decoration: InputDecoration(
          hintText: 'Search measures...',
          prefixIcon: const Icon(Icons.search, size: 20),
          filled: true,
          fillColor: Colors.white,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            borderSide: BorderSide.none,
          ),
        ),
        onChanged: (value) {
          setState(() => _searchQuery = value);
        },
      ),
    );
  }

  Widget _buildMeasureList(
    TemperatureRhProvider measureProvider,
    CustomersProvider customersProvider,
    List<TemperatureSessionModel> sessions,
    bool showCelsius,
  ) {
    if (sessions.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.thermostat_outlined, size: 64, color: Colors.grey[400]),
            const SizedBox(height: 16),
            Text(
              'No measures yet',
              style: TextStyle(fontSize: 16, color: Colors.grey[600]),
            ),
            const SizedBox(height: 8),
            const Text(
              'Saved temperature and R.H. sessions will appear here',
              style: TextStyle(fontSize: 12, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      onRefresh: () async {
        await context.read<CustomersProvider>().loadCustomers(
          currentUser: context.read<AuthProvider>().user,
        );
        await measureProvider.loadMeasureLog();
      },
      child: ListView.builder(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        itemCount: sessions.length > 50 ? 50 : sessions.length,
        itemBuilder: (context, index) {
          final session = sessions[index];
          final readings = measureProvider.readingsForMeasureLogSession(
            session.id,
          );
          final customer = customersProvider.customerById(session.customerId);
          final hatchery = customersProvider.hatcheryById(session.hatcheryId);
          return _MeasureSessionCard(
            session: session,
            readings: readings,
            customerName: customer?.name ?? session.customerId,
            hatcheryName: hatchery?.name ?? session.hatcheryId,
            showCelsius: showCelsius,
            onTap: () => _showSessionDetails(
              session,
              readings,
              customer?.name ?? session.customerId,
              hatchery?.name ?? session.hatcheryId,
              showCelsius,
            ),
          );
        },
      ),
    );
  }

  List<TemperatureSessionModel> _filterSessions(
    TemperatureRhProvider measureProvider,
    CustomersProvider customersProvider,
  ) {
    final sessions = measureProvider.measureLogSessions.toList()
      ..sort((a, b) => b.startedAt.compareTo(a.startedAt));

    if (_searchQuery.trim().isEmpty) return sessions;

    final query = _searchQuery.toLowerCase().trim();
    return sessions.where((session) {
      final customer = customersProvider.customerById(session.customerId);
      final hatchery = customersProvider.hatcheryById(session.hatcheryId);
      final values = [
        customer?.name,
        hatchery?.name,
        session.customerId,
        session.hatcheryId,
        session.activePlace.label,
        session.status,
        session.deviceName,
        _formatDate(session.startedAt),
      ].whereType<String>().join(' ').toLowerCase();
      return values.contains(query);
    }).toList();
  }

  Future<void> _openRecorder() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.86,
        child: const TemperatureRhPanel(compact: true),
      ),
    );
    if (!mounted) return;
    await context.read<TemperatureRhProvider>().loadMeasureLog();
  }

  void _showSessionDetails(
    TemperatureSessionModel session,
    List<TemperatureReadingModel> readings,
    String customerName,
    String hatcheryName,
    bool showCelsius,
  ) {
    final stats = _MeasureStats.from(readings);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 8, 18, 18),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        session.activePlace.label,
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    _MeasureStatusBadge(status: session.status),
                  ],
                ),
                const SizedBox(height: 10),
                Text(
                  '$customerName · $hatcheryName · ${_formatDate(session.startedAt)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 4),
                Text(
                  '${_formatTime(session.startedAt)} - ${session.endedAt == null ? '--' : _formatTime(session.endedAt!)} · ${_formatDuration(session.startedAt, session.endedAt)}',
                  style: TextStyle(fontSize: 13, color: Colors.grey[700]),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _detailPill('Samples', '${stats.sampleCount}'),
                    _detailPill(
                      'Avg temp',
                      stats.hasData
                          ? _formatTemp(stats.avgTempF, showCelsius)
                          : '--',
                    ),
                    _detailPill(
                      'Avg R.H.',
                      stats.hasData
                          ? '${stats.avgHumidity.toStringAsFixed(1)}%'
                          : '--',
                    ),
                    _detailPill(
                      'Range',
                      stats.hasData
                          ? '${_formatTemp(stats.minTempF, showCelsius)} / ${_formatTemp(stats.maxTempF, showCelsius)}'
                          : '--',
                    ),
                  ],
                ),
                const SizedBox(height: 10),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _detailPill(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.ageBadgeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[700])),
          const SizedBox(height: 2),
          Text(
            value,
            style: const TextStyle(
              color: AppColors.primary,
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
          ),
        ],
      ),
    );
  }

  static String _formatDate(DateTime dateTime) {
    return dateTime.toIso8601String().split('T').first;
  }

  static String _formatTime(DateTime dateTime) {
    final hour = dateTime.hour.toString().padLeft(2, '0');
    final minute = dateTime.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }

  static String _formatDuration(DateTime start, DateTime? end) {
    if (end == null) return '--';
    final duration = end.difference(start);
    if (duration.inMinutes < 1) return '${duration.inSeconds}s';
    if (duration.inHours < 1) return '${duration.inMinutes}m';
    final minutes = duration.inMinutes.remainder(60);
    return '${duration.inHours}h ${minutes}m';
  }

  static String _formatTemp(double tempF, bool showCelsius) {
    return TempConverter.display(tempF, showCelsius: showCelsius);
  }
}

class _MeasureSessionCard extends StatelessWidget {
  final TemperatureSessionModel session;
  final List<TemperatureReadingModel> readings;
  final String customerName;
  final String hatcheryName;
  final bool showCelsius;
  final VoidCallback onTap;

  const _MeasureSessionCard({
    required this.session,
    required this.readings,
    required this.customerName,
    required this.hatcheryName,
    required this.showCelsius,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final stats = _MeasureStats.from(readings);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _buildSampleBadge(stats.sampleCount),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      customerName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _MeasureStatusBadge(status: session.status),
                ],
              ),
              const SizedBox(height: 8),
              Text(
                '$hatcheryName · ${_TemperatureRhScreenState._formatDate(session.startedAt)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
              const SizedBox(height: 4),
              Text(
                '${session.activePlace.label} · ${_TemperatureRhScreenState._formatDuration(session.startedAt, session.endedAt)} · ${_summary(stats)}',
                style: TextStyle(fontSize: 12, color: Colors.grey[600]),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSampleBadge(int sampleCount) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: AppColors.ageBadgeBg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        sampleCount > 0 ? '${sampleCount}x' : '--',
        style: const TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  String _summary(_MeasureStats stats) {
    if (!stats.hasData) return 'No samples';
    final temp = _TemperatureRhScreenState._formatTemp(
      stats.avgTempF,
      showCelsius,
    );
    return '$temp · ${stats.avgHumidity.toStringAsFixed(1)}% R.H.';
  }
}

class _MeasureStatusBadge extends StatelessWidget {
  final String status;

  const _MeasureStatusBadge({required this.status});

  @override
  Widget build(BuildContext context) {
    return StatusBadge(status: _badgeStatus, label: _badgeLabel);
  }

  String get _badgeStatus {
    return status == 'syncFailed' ? 'failed' : status;
  }

  String get _badgeLabel {
    switch (status) {
      case 'active':
        return 'Active';
      case 'syncing':
        return 'Syncing';
      case 'syncFailed':
        return 'Needs retry';
      case 'synced':
        return 'Saved';
      default:
        return status.isEmpty
            ? 'Saved'
            : status[0].toUpperCase() + status.substring(1);
    }
  }
}

class _MeasureStats {
  final int sampleCount;
  final double avgTempF;
  final double avgHumidity;
  final double minTempF;
  final double maxTempF;

  const _MeasureStats({
    required this.sampleCount,
    required this.avgTempF,
    required this.avgHumidity,
    required this.minTempF,
    required this.maxTempF,
  });

  bool get hasData => sampleCount > 0;

  factory _MeasureStats.from(List<TemperatureReadingModel> readings) {
    if (readings.isEmpty) {
      return const _MeasureStats(
        sampleCount: 0,
        avgTempF: 0,
        avgHumidity: 0,
        minTempF: 0,
        maxTempF: 0,
      );
    }

    var tempTotal = 0.0;
    var humidityTotal = 0.0;
    var minTemp = readings.first.temperatureFahrenheit;
    var maxTemp = readings.first.temperatureFahrenheit;
    for (final reading in readings) {
      final temp = reading.temperatureFahrenheit;
      tempTotal += temp;
      humidityTotal += reading.humidity;
      if (temp < minTemp) minTemp = temp;
      if (temp > maxTemp) maxTemp = temp;
    }

    return _MeasureStats(
      sampleCount: readings.length,
      avgTempF: tempTotal / readings.length,
      avgHumidity: humidityTotal / readings.length,
      minTempF: minTemp,
      maxTempF: maxTemp,
    );
  }
}
