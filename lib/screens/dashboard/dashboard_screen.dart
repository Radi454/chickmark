import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import '../../providers/app_provider.dart';
import '../../models/audit_session.dart';
import '../../models/hatchery_results.dart';
import '../../models/chick_quality.dart';
import '../../models/egg_breakout.dart';
import '../../models/customer.dart';
import '../../models/flock.dart';
import '../../models/setter_measurements.dart';
import '../../models/hatcher_measurements.dart';
import '../../models/vaccine_storage.dart';
import '../../models/egg_storage.dart';
import '../../utils/app_theme.dart';

// ---------------------------------------------------------------------------
// Data container for a single flock-age audit snapshot
// ---------------------------------------------------------------------------
class _AuditSnapshot {
  final AuditSession session;
  final HatcheryResults? hatcheryResults;
  final ChickQuality? chickQuality;
  final EggBreakout? eggBreakout;
  final SetterMeasurements? setterMeasurements;
  final HatcherMeasurements? hatcherMeasurements;
  final VaccineStorage? vaccineStorage;
  final EggStorage? eggStorage;

  const _AuditSnapshot({
    required this.session,
    this.hatcheryResults,
    this.chickQuality,
    this.eggBreakout,
    this.setterMeasurements,
    this.hatcherMeasurements,
    this.vaccineStorage,
    this.eggStorage,
  });
}

// ---------------------------------------------------------------------------
// Dashboard Screen
// ---------------------------------------------------------------------------
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  // Filter state
  Customer? _selectedCustomer;
  Flock? _selectedFlock;
  AuditSession? _selectedSession;
  bool _showSoldFlocks = false;

  // Data
  List<Customer> _customers = [];
  List<Flock> _flocks = [];
  List<AuditSession> _sessions = [];
  List<_AuditSnapshot> _history = [];

  bool _loading = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _init());
  }

  Future<void> _init() async {
    final provider = context.read<AppProvider>();
    setState(() => _loading = true);

    _customers = provider.customers;

    if (provider.currentSession != null) {
      _selectedCustomer =
          _customers.firstWhereOrNull((c) => c.id == provider.currentSession!.customerId);
      if (_selectedCustomer != null) {
        await _loadFlocks(_selectedCustomer!);
        _selectedFlock =
            _flocks.firstWhereOrNull((f) => f.id == provider.currentSession!.flockId);
        if (_selectedFlock != null) {
          await _loadSessions(_selectedFlock!);
          _selectedSession = provider.currentSession;
          await _loadHistory(_selectedFlock!);
        }
      }
    }

    setState(() => _loading = false);
  }

  Future<void> _loadFlocks(Customer customer) async {
    final provider = context.read<AppProvider>();
    final all = await provider.db.getFlocksByCustomer(customer.id);
    _flocks = _showSoldFlocks ? all : all.where((f) => f.status == 'active').toList();
  }

  Future<void> _loadSessions(Flock flock) async {
    final provider = context.read<AppProvider>();
    final all = await provider.db.getAuditSessionsByFlock(flock.id);
    // Deduplicate: keep only the most recent session per calendar day
    final seen = <String>{};
    _sessions = all.where((s) {
      final key = DateFormat('yyyy-MM-dd').format(s.auditDate);
      return seen.add(key);
    }).toList();
    if (_sessions.isNotEmpty && _selectedSession == null) {
      _selectedSession = _sessions.first;
    }
  }

  Future<void> _loadHistory(Flock flock) async {
    final provider = context.read<AppProvider>();
    final all = await provider.db.getAuditSessionsByFlock(flock.id);

    // Group sessions by calendar day (DB returns newest-first, so first in each
    // group is the most recent session of that day — same one used in _sessions)
    final Map<String, List<AuditSession>> byDay = {};
    for (final s in all) {
      final key = DateFormat('yyyy-MM-dd').format(s.auditDate);
      byDay.putIfAbsent(key, () => []).add(s);
    }

    final snapshots = <_AuditSnapshot>[];

    for (final daySessions in byDay.values) {
      // Load data for every session of this day in parallel
      final allResults = await Future.wait(
        daySessions.map((s) => Future.wait([
          provider.db.getHatcheryResultsBySession(s.id),
          provider.db.getChickQualityBySession(s.id),
          provider.db.getEggBreakoutBySession(s.id),
          provider.db.getSetterMeasurementsBySession(s.id),
          provider.db.getHatcherMeasurementsBySession(s.id),
          provider.db.getVaccineStorageBySession(s.id),
          provider.db.getEggStorageBySession(s.id),
        ])),
      );

      // Collect non-null objects for each type across all sessions of the day
      final hatcheryList = allResults
          .map((r) => r[0] as HatcheryResults?)
          .whereType<HatcheryResults>()
          .toList();
      final chickList = allResults
          .map((r) => r[1] as ChickQuality?)
          .whereType<ChickQuality>()
          .toList();
      final breakoutList = allResults
          .map((r) => r[2] as EggBreakout?)
          .whereType<EggBreakout>()
          .toList();
      final setterList = allResults
          .map((r) => r[3] as SetterMeasurements?)
          .whereType<SetterMeasurements>()
          .toList();
      final hatcherList = allResults
          .map((r) => r[4] as HatcherMeasurements?)
          .whereType<HatcherMeasurements>()
          .toList();
      final vaccineList = allResults
          .map((r) => r[5] as VaccineStorage?)
          .whereType<VaccineStorage>()
          .toList();
      final eggStorageList = allResults
          .map((r) => r[6] as EggStorage?)
          .whereType<EggStorage>()
          .toList();

      // Use the first (most recent) session as representative — matches _sessions
      snapshots.add(_AuditSnapshot(
        session: daySessions.first,
        hatcheryResults: _mergeHatcheryResults(hatcheryList),
        chickQuality: _mergeChickQuality(chickList),
        eggBreakout: _mergeEggBreakout(breakoutList),
        setterMeasurements: _mergeSetterMeasurements(setterList),
        hatcherMeasurements: _mergeHatcherMeasurements(hatcherList),
        vaccineStorage: _mergeVaccineStorage(vaccineList),
        eggStorage: _mergeEggStorage(eggStorageList),
      ));
    }

    snapshots.sort((a, b) => a.session.flockAgeWeeks.compareTo(b.session.flockAgeWeeks));
    _history = snapshots;
  }

  _AuditSnapshot? get _currentSnapshot =>
      _history.firstWhereOrNull((s) => s.session.id == _selectedSession?.id);

  // ── Day-merge helpers ────────────────────────────────────────────────────

  SetterMeasurements? _mergeSetterMeasurements(List<SetterMeasurements> list) {
    if (list.isEmpty) return null;
    final b = list.first;
    for (final s in list.skip(1)) {
      b.setterId ??= s.setterId;
      b.incubationAge ??= s.incubationAge;
      b.temperature ??= s.temperature;
      b.humidity ??= s.humidity;
      b.topFront ??= s.topFront;
      b.topMiddle ??= s.topMiddle;
      b.topBack ??= s.topBack;
      b.midFront ??= s.midFront;
      b.midMiddle ??= s.midMiddle;
      b.midBack ??= s.midBack;
      b.botFront ??= s.botFront;
      b.botMiddle ??= s.botMiddle;
      b.botBack ??= s.botBack;
    }
    return b;
  }

  HatcherMeasurements? _mergeHatcherMeasurements(List<HatcherMeasurements> list) {
    if (list.isEmpty) return null;
    final b = list.first;
    for (final s in list.skip(1)) {
      b.hatcherId ??= s.hatcherId;
      b.temperature ??= s.temperature;
      b.humidity ??= s.humidity;
      b.topFront ??= s.topFront;
      b.topMiddle ??= s.topMiddle;
      b.topBack ??= s.topBack;
      b.midFront ??= s.midFront;
      b.midMiddle ??= s.midMiddle;
      b.midBack ??= s.midBack;
      b.botFront ??= s.botFront;
      b.botMiddle ??= s.botMiddle;
      b.botBack ??= s.botBack;
    }
    return b;
  }

  ChickQuality? _mergeChickQuality(List<ChickQuality> list) {
    if (list.isEmpty) return null;
    final b = list.first;
    for (final s in list.skip(1)) {
      b.eggStorageDays ??= s.eggStorageDays;
      b.temperature ??= s.temperature;
      b.humidity ??= s.humidity;
      b.co2Level ??= s.co2Level;
      b.pm10 ??= s.pm10;
      b.pm25 ??= s.pm25;
      b.airVelocityDoor ??= s.airVelocityDoor;
      b.airVelocityCenter ??= s.airVelocityCenter;
      b.airVelocityCorner ??= s.airVelocityCorner;
      b.noiseLevel ??= s.noiseLevel;
      if (b.weights.isEmpty && s.weights.isNotEmpty) b.weights = List.from(s.weights);
      if (b.yfbmDataJson == '[]' && s.yfbmDataJson != '[]') b.yfbmDataJson = s.yfbmDataJson;
      if (b.pasgarSampleSize == 0 && s.pasgarSampleSize > 0) {
        b.pasgarSampleSize = s.pasgarSampleSize;
        b.reflexesDefects = s.reflexesDefects;
        b.beakDefects = s.beakDefects;
        b.navelDefects = s.navelDefects;
        b.bellyDefects = s.bellyDefects;
        b.legsDefects = s.legsDefects;
      }
      b.featheredCount ??= s.featheredCount;
    }
    return b;
  }

  HatcheryResults? _mergeHatcheryResults(List<HatcheryResults> list) {
    if (list.isEmpty) return null;
    final b = list.first;
    final allHatchers = List<HatcherEntry>.from(b.hatchers);
    for (final s in list.skip(1)) {
      b.eggStorageDays ??= s.eggStorageDays;
      b.totalHatcherCapacity ??= s.totalHatcherCapacity;
      allHatchers.addAll(s.hatchers);
    }
    b.hatchers = allHatchers;
    return b;
  }

  EggBreakout? _mergeEggBreakout(List<EggBreakout> list) {
    if (list.isEmpty) return null;
    final b = list.first;
    final allTrays = List<Map<String, dynamic>>.from(b.trayData);
    for (final s in list.skip(1)) {
      b.eggStorageDays ??= s.eggStorageDays;
      b.eggBreakoutAgeDays ??= s.eggBreakoutAgeDays;
      b.incubatorId ??= s.incubatorId;
      b.hatcherId ??= s.hatcherId;
      b.sampleSize ??= s.sampleSize;
      allTrays.addAll(s.trayData);
    }
    b.trayData = allTrays;
    return b;
  }

  VaccineStorage? _mergeVaccineStorage(List<VaccineStorage> list) {
    if (list.isEmpty) return null;
    final b = list.first;
    final allFridge = List<FridgeVaccine>.from(b.fridgeVaccines);
    final allHvt = List<HvtContainer>.from(b.hvtContainers);
    for (final s in list.skip(1)) {
      b.roomTemperature ??= s.roomTemperature;
      b.roomHumidity ??= s.roomHumidity;
      allFridge.addAll(s.fridgeVaccines);
      allHvt.addAll(s.hvtContainers);
      if (s.coldChainMaintained) b.coldChainMaintained = true;
      if (s.expiryDatesChecked) b.expiryDatesChecked = true;
      if (s.dilutionProtocolFollowed) b.dilutionProtocolFollowed = true;
      if (s.vaccinationRoomBiosecure) b.vaccinationRoomBiosecure = true;
    }
    b.fridgeVaccines = allFridge;
    b.hvtContainers = allHvt;
    return b;
  }

  EggStorage? _mergeEggStorage(List<EggStorage> list) {
    if (list.isEmpty) return null;
    final b = list.first;
    for (final s in list.skip(1)) {
      b.temperature ??= s.temperature;
      b.humidity ??= s.humidity;
      b.eggshellTemperature ??= s.eggshellTemperature;
      b.turningFrequency ??= s.turningFrequency;
      b.uvTrays ??= s.uvTrays;
      b.storageDays ??= s.storageDays;
      b.sanitizationMethod ??= s.sanitizationMethod;
      b.sanitizationAgent ??= s.sanitizationAgent;
    }
    return b;
  }

  // ── UI ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Consumer<AppProvider>(
      builder: (context, provider, _) {
        return Scaffold(
          backgroundColor: AppTheme.background,
          body: _loading
              ? const Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    _buildFilterBar(),
                    Expanded(
                      child: _currentSnapshot == null
                          ? _buildEmptyState()
                          : _buildDashboard(_currentSnapshot!),
                    ),
                  ],
                ),
          floatingActionButton: null,
        );
      },
    );
  }

  Widget _buildFilterBar() {
    return Container(
      color: AppTheme.primary,
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: _buildDropdown<Customer>(
                  label: 'Customer',
                  value: _selectedCustomer,
                  items: _customers,
                  displayString: (c) => c.name,
                  onChanged: (c) async {
                    setState(() {
                      _selectedCustomer = c;
                      _selectedFlock = null;
                      _selectedSession = null;
                      _sessions = [];
                      _flocks = [];
                      _history = [];
                    });
                    if (c != null) {
                      await _loadFlocks(c);
                      setState(() {});
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildDropdown<Flock>(
                  label: 'Flock',
                  value: _selectedFlock,
                  items: _flocks,
                  displayString: (f) => f.flockCode,
                  onChanged: (f) async {
                    setState(() {
                      _selectedFlock = f;
                      _selectedSession = null;
                      _sessions = [];
                      _history = [];
                    });
                    if (f != null) {
                      await _loadSessions(f);
                      await _loadHistory(f);
                      setState(() {});
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildDropdown<AuditSession>(
                  label: 'Age (wks)',
                  value: _selectedSession,
                  items: _sessions,
                  displayString: (s) =>
                      '${s.flockAgeWeeks.toStringAsFixed(1)}w  '
                      '${DateFormat('dd MMM').format(s.auditDate)}',
                  onChanged: (s) => setState(() => _selectedSession = s),
                ),
              ),
              const SizedBox(width: 8),
              Row(
                children: [
                  const Text('Sold',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  Switch(
                    value: _showSoldFlocks,
                    onChanged: (v) async {
                      setState(() {
                        _showSoldFlocks = v;
                        _selectedFlock = null;
                        _selectedSession = null;
                        _history = [];
                      });
                      if (_selectedCustomer != null) {
                        await _loadFlocks(_selectedCustomer!);
                        setState(() {});
                      }
                    },
                    activeThumbColor: AppTheme.accent,
                    inactiveThumbColor: Colors.white54,
                  ),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildDropdown<T>({
    required String label,
    required T? value,
    required List<T> items,
    required String Function(T) displayString,
    required ValueChanged<T?> onChanged,
  }) {
    return DropdownButtonFormField<T>(
      initialValue: items.contains(value) ? value : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: const TextStyle(color: Colors.white70, fontSize: 11),
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white30),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Colors.white),
        ),
        fillColor: Colors.white12,
        filled: true,
      ),
      dropdownColor: AppTheme.primary,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      iconEnabledColor: Colors.white70,
      hint: Text(label,
          style: const TextStyle(color: Colors.white54, fontSize: 12)),
      items: items
          .map((e) => DropdownMenuItem<T>(
                value: e,
                child: Text(
                  displayString(e),
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ))
          .toList(),
      onChanged: onChanged,
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.bar_chart_outlined,
              size: 72,
              color: AppTheme.textSecondary.withValues(alpha: 0.4)),
          const SizedBox(height: 16),
          Text(
            'Select a customer and flock\nto view audit insights',
            textAlign: TextAlign.center,
            style: TextStyle(color: AppTheme.textSecondary, fontSize: 15),
          ),
        ],
      ),
    );
  }

  Widget _buildDashboard(_AuditSnapshot snap) {
    return ListView(
      padding: const EdgeInsets.only(bottom: 100),
      children: [
        if (snap.hatcheryResults != null) ...[
          _sectionHeader('KPI Overview', Icons.analytics_outlined),
          _KpiSection(snapshot: snap, history: _history),
        ],
        if (snap.chickQuality != null) ...[
          _sectionHeader('Chick Quality', Icons.egg_outlined),
          _ChickQualitySection(snapshot: snap, history: _history),
        ],
        if (snap.eggBreakout != null) ...[
          _sectionHeader('Egg Breakout Analysis', Icons.search),
          _EggBreakoutSection(snapshot: snap),
        ],
        if (snap.chickQuality != null ||
            snap.setterMeasurements != null ||
            snap.hatcherMeasurements != null ||
            snap.vaccineStorage != null ||
            snap.eggStorage != null) ...[
          _sectionHeader('Environmental Conditions', Icons.thermostat_outlined),
          _EnvironmentSection(snapshot: snap),
        ],
        if (snap.setterMeasurements != null ||
            snap.hatcherMeasurements != null) ...[
          _sectionHeader('Temperature Grids', Icons.grid_on),
          _TempGridSection(snapshot: snap),
        ],
        if (snap.vaccineStorage != null || snap.eggStorage != null) ...[
          _sectionHeader('Vaccine & Egg Storage', Icons.inventory_2_outlined),
          _StorageSection(snapshot: snap),
        ],
        _sectionHeader('Problems & Recommendations', Icons.report_problem_outlined),
        _ProblemsSection(snapshot: snap),
      ],
    );
  }

  Widget _sectionHeader(String title, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Row(
        children: [
          Icon(icon, color: AppTheme.secondary, size: 20),
          const SizedBox(width: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: AppTheme.textPrimary,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Divider(
              color: AppTheme.secondary.withValues(alpha: 0.3),
              thickness: 1,
            ),
          ),
        ],
      ),
    );
  }

}

// ---------------------------------------------------------------------------
// Section 1: KPI Overview
// ---------------------------------------------------------------------------
class _KpiSection extends StatelessWidget {
  final _AuditSnapshot snapshot;
  final List<_AuditSnapshot> history;

  const _KpiSection({required this.snapshot, required this.history});

  static double? _computeHatchability(HatcheryResults hr) {
    final hatchers = hr.hatchers;
    final cap = hr.totalHatcherCapacity ?? 19200;
    if (cap == 0 || !hatchers.any((h) => h.hatched != null)) return null;
    final total = hatchers.fold<int>(0, (s, h) => s + (h.hatched ?? 0));
    return (total / cap) * 100;
  }

  static double? _computeFertility(HatcheryResults hr) {
    final fs = hr.hatchers
        .where((h) => h.fertilityPercent != null)
        .map((h) => h.fertilityPercent!)
        .toList();
    if (fs.isEmpty) return null;
    return fs.reduce((a, b) => a + b) / fs.length;
  }

  static double? _computeHof(HatcheryResults hr) {
    final h = _computeHatchability(hr);
    final f = _computeFertility(hr);
    if (h == null || f == null || f == 0) return null;
    return (h / f) * 100;
  }

  static double? _computeCulledPct(HatcheryResults hr) {
    final cap = hr.totalHatcherCapacity ?? 19200;
    final hatchers = hr.hatchers;
    if (cap == 0 || !hatchers.any((h) => h.culled != null)) return null;
    return (hatchers.fold<int>(0, (s, h) => s + (h.culled ?? 0)) / cap) * 100;
  }

  static double? _computeDeadPct(HatcheryResults hr) {
    final cap = hr.totalHatcherCapacity ?? 19200;
    final hatchers = hr.hatchers;
    if (cap == 0 || !hatchers.any((h) => h.dead != null)) return null;
    return (hatchers.fold<int>(0, (s, h) => s + (h.dead ?? 0)) / cap) * 100;
  }

  @override
  Widget build(BuildContext context) {
    final hr = snapshot.hatcheryResults!;
    final hatchability = _computeHatchability(hr);
    final fertility = _computeFertility(hr);
    final hof = _computeHof(hr);
    final culledPct = _computeCulledPct(hr);
    final deadPct = _computeDeadPct(hr);

    return Column(
      children: [
        if (hatchability != null)
          _KpiBarCard(
            title: 'Hatchability',
            actualValue: hatchability,
            standardValue: 91.5,
            unit: '%',
            history: history
                .where((s) => _computeHatchability(s.hatcheryResults!) != null)
                .where((s) => s.hatcheryResults != null)
                .map((s) => _TrendPoint(
                      age: s.session.flockAgeWeeks,
                      value: _computeHatchability(s.hatcheryResults!)!,
                    ))
                .toList(),
            stdTrend: _buildStdTrend(history, 91.5),
          ),
        if (fertility != null)
          _KpiBarCard(
            title: 'Fertility',
            actualValue: fertility,
            standardValue: 97.0,
            unit: '%',
            history: history
                .where((s) => s.hatcheryResults != null)
                .where((s) => _computeFertility(s.hatcheryResults!) != null)
                .map((s) => _TrendPoint(
                      age: s.session.flockAgeWeeks,
                      value: _computeFertility(s.hatcheryResults!)!,
                    ))
                .toList(),
            stdTrend: _buildStdTrend(history, 97.0),
          ),
        if (hof != null)
          _KpiBarCard(
            title: 'Hatch of Fertile (HOF)',
            actualValue: hof,
            standardValue: 94.0,
            unit: '%',
            history: history
                .where((s) => s.hatcheryResults != null)
                .where((s) => _computeHof(s.hatcheryResults!) != null)
                .map((s) => _TrendPoint(
                      age: s.session.flockAgeWeeks,
                      value: _computeHof(s.hatcheryResults!)!,
                    ))
                .toList(),
            stdTrend: _buildStdTrend(history, 94.0),
          ),
        if (culledPct != null || deadPct != null)
          _CulledDeadPieCard(
            culledPct: culledPct ?? 0,
            deadPct: deadPct ?? 0,
            hatchedPct: 100 - (culledPct ?? 0) - (deadPct ?? 0),
          ),
      ],
    );
  }

  List<_TrendPoint> _buildStdTrend(
          List<_AuditSnapshot> history, double std) =>
      history
          .map((s) => _TrendPoint(age: s.session.flockAgeWeeks, value: std))
          .toList();
}

class _TrendPoint {
  final double age;
  final double value;
  const _TrendPoint({required this.age, required this.value});
}

class _KpiBarCard extends StatelessWidget {
  final String title;
  final double actualValue;
  final double standardValue;
  final String unit;
  final List<_TrendPoint> history;
  final List<_TrendPoint> stdTrend;

  const _KpiBarCard({
    required this.title,
    required this.actualValue,
    required this.standardValue,
    required this.unit,
    required this.history,
    required this.stdTrend,
  });

  @override
  Widget build(BuildContext context) {
    final gap = actualValue - standardValue;
    final gapColor = gap >= 0 ? AppTheme.green : AppTheme.red;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: gapColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: gapColor.withValues(alpha: 0.4)),
                  ),
                  child: Text(
                    'Gap: ${gap >= 0 ? '+' : ''}${gap.toStringAsFixed(1)}$unit',
                    style: TextStyle(
                        color: gapColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 120,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.center,
                  maxY: 105,
                  minY: 75,
                  barGroups: [
                    BarChartGroupData(
                      x: 0,
                      barRods: [
                        BarChartRodData(
                          toY: standardValue,
                          color: AppTheme.green,
                          width: 32,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                    BarChartGroupData(
                      x: 1,
                      barRods: [
                        BarChartRodData(
                          toY: actualValue,
                          color: AppTheme.accent,
                          width: 32,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      ],
                    ),
                  ],
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 36,
                        interval: 5,
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                              fontSize: 10, color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          const labels = ['STD', 'Actual'];
                          return Text(
                            labels[v.toInt()],
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (v) => FlLine(
                      color: Colors.grey.withValues(alpha: 0.15),
                      strokeWidth: 1,
                    ),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final label = groupIndex == 0 ? 'STD' : 'Actual';
                        return BarTooltipItem(
                          '$label\n${rod.toY.toStringAsFixed(1)}$unit',
                          const TextStyle(color: Colors.white, fontSize: 12),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Row(
              children: [
                _legendDot(AppTheme.green,
                    'STD: ${standardValue.toStringAsFixed(1)}$unit'),
                const SizedBox(width: 16),
                _legendDot(AppTheme.accent,
                    'Actual: ${actualValue.toStringAsFixed(1)}$unit'),
              ],
            ),
            if (history.length > 1) ...[
              const SizedBox(height: 16),
              const Text(
                'Trend vs Standard',
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 8),
              SizedBox(
                height: 100,
                child: _buildTrendLine(history, stdTrend),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildTrendLine(
      List<_TrendPoint> actual, List<_TrendPoint> std) {
    if (actual.isEmpty) return const SizedBox.shrink();

    final ages = actual.map((p) => p.age).toList();
    final minAge = ages.reduce((a, b) => a < b ? a : b);
    final maxAge = ages.reduce((a, b) => a > b ? a : b);
    final allVals = [
      ...actual.map((p) => p.value),
      ...std.map((p) => p.value),
    ];
    final minY = (allVals.reduce((a, b) => a < b ? a : b) - 3)
        .clamp(0.0, 100.0);
    final maxY = (allVals.reduce((a, b) => a > b ? a : b) + 3)
        .clamp(0.0, 110.0);

    return LineChart(
      LineChartData(
        minX: minAge,
        maxX: maxAge == minAge ? minAge + 1 : maxAge,
        minY: minY,
        maxY: maxY,
        lineBarsData: [
          LineChartBarData(
            spots: actual.map((p) => FlSpot(p.age, p.value)).toList(),
            isCurved: true,
            color: AppTheme.accent,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(
              show: true,
              color: AppTheme.accent.withValues(alpha: 0.08),
            ),
          ),
          LineChartBarData(
            spots: std.map((p) => FlSpot(p.age, p.value)).toList(),
            isCurved: false,
            color: AppTheme.green,
            barWidth: 1.5,
            dashArray: [5, 4],
            dotData: const FlDotData(show: false),
          ),
        ],
        titlesData: FlTitlesData(
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 30,
              interval: (maxY - minY) / 2,
              getTitlesWidget: (v, _) => Text(
                v.toStringAsFixed(0),
                style: const TextStyle(
                    fontSize: 9, color: AppTheme.textSecondary),
              ),
            ),
          ),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: actual.length > 4 ? 5 : 2,
              getTitlesWidget: (v, _) => Text(
                '${v.toStringAsFixed(0)}w',
                style: const TextStyle(
                    fontSize: 9, color: AppTheme.textSecondary),
              ),
            ),
          ),
        ),
        gridData: FlGridData(
          show: true,
          getDrawingHorizontalLine: (_) => FlLine(
              color: Colors.grey.withValues(alpha: 0.12), strokeWidth: 1),
          drawVerticalLine: false,
        ),
        borderData: FlBorderData(show: false),
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (spots) => spots
                .map((s) => LineTooltipItem(
                      '${s.y.toStringAsFixed(1)}%\n${s.x.toStringAsFixed(0)}w',
                      const TextStyle(color: Colors.white, fontSize: 11),
                    ))
                .toList(),
          ),
        ),
      ),
    );
  }

  Widget _legendDot(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
            width: 10,
            height: 10,
            decoration:
                BoxDecoration(color: color, shape: BoxShape.circle)),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _CulledDeadPieCard extends StatelessWidget {
  final double culledPct;
  final double deadPct;
  final double hatchedPct;

  const _CulledDeadPieCard({
    required this.culledPct,
    required this.deadPct,
    required this.hatchedPct,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Culled % & Dead %',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 180,
              child: Row(
                children: [
                  Expanded(
                    child: PieChart(
                      PieChartData(
                        sectionsSpace: 2,
                        centerSpaceRadius: 40,
                        sections: [
                          PieChartSectionData(
                            value: hatchedPct.clamp(0, 100),
                            color: AppTheme.green,
                            title:
                                '${hatchedPct.toStringAsFixed(1)}%',
                            radius: 55,
                            titleStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          PieChartSectionData(
                            value: culledPct.clamp(0, 100),
                            color: AppTheme.amber,
                            title: '${culledPct.toStringAsFixed(1)}%',
                            radius: 55,
                            titleStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                          PieChartSectionData(
                            value: deadPct.clamp(0, 100),
                            color: AppTheme.red,
                            title: '${deadPct.toStringAsFixed(1)}%',
                            radius: 55,
                            titleStyle: const TextStyle(
                                fontSize: 11,
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _pieLegend(AppTheme.green,
                          'Placed  ${hatchedPct.toStringAsFixed(1)}%'),
                      const SizedBox(height: 8),
                      _pieLegend(AppTheme.amber,
                          'Culled  ${culledPct.toStringAsFixed(1)}%'),
                      const SizedBox(height: 8),
                      _pieLegend(AppTheme.red,
                          'Dead    ${deadPct.toStringAsFixed(1)}%'),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _pieLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 6),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textSecondary)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section 2: Chick Quality
// ---------------------------------------------------------------------------
class _ChickQualitySection extends StatelessWidget {
  final _AuditSnapshot snapshot;
  final List<_AuditSnapshot> history;

  const _ChickQualitySection(
      {required this.snapshot, required this.history});

  @override
  Widget build(BuildContext context) {
    final cq = snapshot.chickQuality!;
    return Column(
      children: [
        _PasgarCard(cq: cq),
        if (history.length > 1) _WeightTrendCard(history: history),
        if (cq.yfbmPairs.isNotEmpty) _YfbmCard(cq: cq),
      ],
    );
  }
}

class _PasgarCard extends StatelessWidget {
  final ChickQuality cq;
  const _PasgarCard({required this.cq});

  @override
  Widget build(BuildContext context) {
    if (cq.pasgarSampleSize == 0) return const SizedBox.shrink();

    final score = cq.pasgarScore;
    final scoreColor = score >= 9
        ? AppTheme.green
        : score >= 7
            ? AppTheme.amber
            : AppTheme.red;

    final items = <String, int>{
      'Reflexes': cq.reflexesDefects,
      'Beak': cq.beakDefects,
      'Navel': cq.navelDefects,
      'Belly': cq.bellyDefects,
      'Legs': cq.legsDefects,
    };

    final maxDefects = cq.pasgarSampleSize.toDouble();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Pasgar Score',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                SizedBox(
                  width: 130,
                  height: 130,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      PieChart(
                        PieChartData(
                          startDegreeOffset: -90,
                          sectionsSpace: 0,
                          centerSpaceRadius: 42,
                          sections: [
                            PieChartSectionData(
                              value: score,
                              color: scoreColor,
                              radius: 18,
                              showTitle: false,
                            ),
                            PieChartSectionData(
                              value: 10 - score,
                              color: Colors.grey.shade200,
                              radius: 18,
                              showTitle: false,
                            ),
                          ],
                        ),
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            score.toStringAsFixed(1),
                            style: TextStyle(
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              color: scoreColor,
                            ),
                          ),
                          Text('/ 10',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: AppTheme.textSecondary)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        'Sample: ${cq.pasgarSampleSize} chicks',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Total defects: ${cq.totalDefects}',
                        style: const TextStyle(
                            fontSize: 12,
                            color: AppTheme.textSecondary),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: scoreColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          score >= 9
                              ? 'Excellent'
                              : score >= 7
                                  ? 'Acceptable'
                                  : 'Poor',
                          style: TextStyle(
                              color: scoreColor,
                              fontWeight: FontWeight.bold,
                              fontSize: 13),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            SizedBox(
              height: 150,
              child: BarChart(
                BarChartData(
                  alignment: BarChartAlignment.spaceAround,
                  maxY: maxDefects.clamp(1, double.infinity),
                  minY: 0,
                  barGroups: items.entries
                      .toList()
                      .asMap()
                      .entries
                      .map((e) {
                        final idx = e.key;
                        final entry = e.value;
                        final defectColor = entry.value == 0
                            ? AppTheme.green
                            : entry.value <
                                    cq.pasgarSampleSize * 0.1
                                ? AppTheme.amber
                                : AppTheme.red;
                        return BarChartGroupData(
                          x: idx,
                          barRods: [
                            BarChartRodData(
                              toY: entry.value.toDouble(),
                              color: defectColor,
                              width: 22,
                              borderRadius: BorderRadius.circular(4),
                            ),
                          ],
                        );
                      })
                      .toList(),
                  titlesData: FlTitlesData(
                    leftTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        reservedSize: 28,
                        interval: (maxDefects / 4)
                            .ceilToDouble()
                            .clamp(1, double.infinity),
                        getTitlesWidget: (v, _) => Text(
                          v.toInt().toString(),
                          style: const TextStyle(
                              fontSize: 10,
                              color: AppTheme.textSecondary),
                        ),
                      ),
                    ),
                    rightTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    topTitles: const AxisTitles(
                        sideTitles: SideTitles(showTitles: false)),
                    bottomTitles: AxisTitles(
                      sideTitles: SideTitles(
                        showTitles: true,
                        getTitlesWidget: (v, _) {
                          final keys = items.keys.toList();
                          if (v.toInt() >= keys.length) {
                            return const SizedBox.shrink();
                          }
                          return Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              keys[v.toInt()],
                              style: const TextStyle(
                                  fontSize: 10,
                                  color: AppTheme.textSecondary),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                  gridData: FlGridData(
                    show: true,
                    getDrawingHorizontalLine: (_) => FlLine(
                        color: Colors.grey.withValues(alpha: 0.12),
                        strokeWidth: 1),
                    drawVerticalLine: false,
                  ),
                  borderData: FlBorderData(show: false),
                  barTouchData: BarTouchData(
                    touchTooltipData: BarTouchTooltipData(
                      getTooltipItem: (group, groupIndex, rod, rodIndex) {
                        final key = items.keys.toList()[groupIndex];
                        return BarTooltipItem(
                          '$key\n${rod.toY.toInt()} defects',
                          const TextStyle(
                              color: Colors.white, fontSize: 11),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
            if (cq.wingPercent != null) ...[
              const SizedBox(height: 12),
              _statRow(
                'Wing Feathering',
                '${cq.wingPercent!.toStringAsFixed(1)}%',
                cq.wingColor ?? 'grey',
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _statRow(String label, String value, String flag) {
    final color = flag == 'green'
        ? AppTheme.green
        : flag == 'amber'
            ? AppTheme.amber
            : AppTheme.red;
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(
                fontSize: 13, color: AppTheme.textSecondary)),
        Row(
          children: [
            Icon(
              flag == 'green'
                  ? Icons.check_circle
                  : flag == 'amber'
                      ? Icons.warning_amber
                      : Icons.cancel,
              color: color,
              size: 16,
            ),
            const SizedBox(width: 4),
            Text(value,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: color)),
          ],
        ),
      ],
    );
  }
}

class _WeightTrendCard extends StatelessWidget {
  final List<_AuditSnapshot> history;

  const _WeightTrendCard({required this.history});

  @override
  Widget build(BuildContext context) {
    final weightPoints = history
        .where((s) =>
            s.chickQuality != null && s.chickQuality!.weights.isNotEmpty)
        .map((s) => _TrendPoint(
              age: s.session.flockAgeWeeks,
              value: s.chickQuality!.avgWeight,
            ))
        .toList();

    final uniformityPoints = history
        .where((s) =>
            s.chickQuality != null && s.chickQuality!.weights.isNotEmpty)
        .map((s) => _TrendPoint(
              age: s.session.flockAgeWeeks,
              value: s.chickQuality!.uniformityPercent,
            ))
        .toList();

    if (weightPoints.isEmpty && uniformityPoints.isEmpty) {
      return const SizedBox.shrink();
    }

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Weight & Uniformity Trends',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            if (weightPoints.length > 1) ...[
              const Text('Avg Weight (g)',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              SizedBox(
                  height: 110,
                  child: _simpleLine(weightPoints, AppTheme.secondary)),
              const SizedBox(height: 16),
            ],
            if (uniformityPoints.length > 1) ...[
              const Text('Uniformity %',
                  style: TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary)),
              const SizedBox(height: 8),
              SizedBox(
                  height: 110,
                  child:
                      _simpleLine(uniformityPoints, AppTheme.green)),
            ],
          ],
        ),
      ),
    );
  }

  Widget _simpleLine(List<_TrendPoint> points, Color color) {
    if (points.isEmpty) return const SizedBox.shrink();
    final ages = points.map((p) => p.age).toList();
    final vals = points.map((p) => p.value).toList();
    final minX = ages.reduce((a, b) => a < b ? a : b);
    final maxX = ages.reduce((a, b) => a > b ? a : b);
    final minY = (vals.reduce((a, b) => a < b ? a : b) - 5)
        .clamp(0.0, 5000.0);
    final maxY = vals.reduce((a, b) => a > b ? a : b) + 5;

    return LineChart(LineChartData(
      minX: minX,
      maxX: maxX == minX ? minX + 1 : maxX,
      minY: minY,
      maxY: maxY,
      lineBarsData: [
        LineChartBarData(
          spots: points.map((p) => FlSpot(p.age, p.value)).toList(),
          isCurved: true,
          color: color,
          barWidth: 2,
          dotData: const FlDotData(show: true),
          belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.08)),
        ),
      ],
      titlesData: FlTitlesData(
        leftTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            reservedSize: 38,
            getTitlesWidget: (v, _) => Text(v.toStringAsFixed(0),
                style: const TextStyle(
                    fontSize: 9, color: AppTheme.textSecondary)),
          ),
        ),
        rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false)),
        topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false)),
        bottomTitles: AxisTitles(
          sideTitles: SideTitles(
            showTitles: true,
            getTitlesWidget: (v, _) => Text('${v.toStringAsFixed(0)}w',
                style: const TextStyle(
                    fontSize: 9, color: AppTheme.textSecondary)),
          ),
        ),
      ),
      gridData: FlGridData(
        show: true,
        getDrawingHorizontalLine: (_) => FlLine(
            color: Colors.grey.withValues(alpha: 0.12), strokeWidth: 1),
        drawVerticalLine: false,
      ),
      borderData: FlBorderData(show: false),
      lineTouchData: LineTouchData(
        touchTooltipData: LineTouchTooltipData(
          getTooltipItems: (spots) => spots
              .map((s) => LineTooltipItem(
                    '${s.y.toStringAsFixed(1)}\n${s.x.toStringAsFixed(0)}w',
                    const TextStyle(color: Colors.white, fontSize: 11),
                  ))
              .toList(),
        ),
      ),
    ));
  }
}

class _YfbmCard extends StatelessWidget {
  final ChickQuality cq;
  const _YfbmCard({required this.cq});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'YFBM (Yolk-Free Body Mass)',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: _statTile('Avg Yolk %',
                      '${cq.avgYolkPercent.toStringAsFixed(2)}%'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile('CV %',
                      '${cq.cvYolkPercent.toStringAsFixed(2)}%'),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _statTile('Samples', '${cq.yfbmPairs.length}'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _statTile(String label, String value) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: AppTheme.primary)),
          const SizedBox(height: 2),
          Text(label,
              style: const TextStyle(
                  fontSize: 11, color: AppTheme.textSecondary),
              textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 3: Egg Breakout
// ---------------------------------------------------------------------------
class _EggBreakoutSection extends StatelessWidget {
  final _AuditSnapshot snapshot;
  const _EggBreakoutSection({required this.snapshot});

  static const Map<String, double> _benchmarks = {
    'infertile': 3.5,
    'earlyDead24h': 0.5,
    'earlyDead48h': 0.5,
    'bloodRing': 0.3,
    'earlyDead': 1.5,
    'midBlackEye': 0.5,
    'feathers': 0.2,
    'turned': 0.1,
    'internalPip': 0.5,
    'lateDead': 1.5,
    'externalPip': 0.3,
    'exposedBrain': 0.1,
    'crossedBeak': 0.1,
    'contaminated': 0.5,
    'cracked': 0.5,
  };

  static const Map<String, String> _labels = {
    'infertile': 'Infertile',
    'earlyDead24h': 'Early Dead 24h',
    'earlyDead48h': 'Early Dead 48h',
    'bloodRing': 'Blood Ring',
    'earlyDead': 'Early Dead',
    'midBlackEye': 'Mid/Black Eye',
    'feathers': 'Feathers',
    'turned': 'Turned',
    'internalPip': 'Internal Pip',
    'lateDead': 'Late Dead',
    'externalPip': 'External Pip',
    'exposedBrain': 'Exposed Brain',
    'crossedBeak': 'Crossed Beak',
    'contaminated': 'Contaminated',
    'cracked': 'Cracked',
  };

  @override
  Widget build(BuildContext context) {
    final eb = snapshot.eggBreakout!;
    final eggsSet = eb.sampleSize ?? 0;
    if (eggsSet == 0) return const SizedBox.shrink();

    final categories = _benchmarks.keys.toList();
    final findings = categories.map((cat) {
      final total = eb.categoryTotal(cat);
      final pct = (total / eggsSet) * 100;
      final benchmark = _benchmarks[cat] ?? 1.0;
      final String severity;
      if (pct > benchmark * 2) {
        severity = 'High';
      } else if (pct > benchmark) {
        severity = 'Medium';
      } else {
        severity = 'OK';
      }
      return (
        category: cat,
        label: _labels[cat] ?? cat,
        total: total,
        pct: pct,
        benchmark: benchmark,
        severity: severity,
      );
    }).toList();

    findings.sort((a, b) {
      const order = {'High': 0, 'Medium': 1, 'OK': 2};
      return (order[a.severity] ?? 2).compareTo(order[b.severity] ?? 2);
    });

    final nonZero = findings.where((f) => f.total > 0).toList();

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Sample Size: $eggsSet',
                          style: const TextStyle(
                              fontSize: 12,
                              color: AppTheme.textSecondary)),
                      if (eb.eggBreakoutAgeDays != null)
                        Text(
                            'Breakout Age: ${eb.eggBreakoutAgeDays}d',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
            if (nonZero.isNotEmpty) ...[
              const SizedBox(height: 16),
              SizedBox(
                height: 200,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceAround,
                    maxY: nonZero
                            .map((f) => [f.pct, f.benchmark]
                                .reduce((a, b) => a > b ? a : b))
                            .reduce((a, b) => a > b ? a : b) *
                        1.3,
                    minY: 0,
                    barGroups: nonZero
                        .asMap()
                        .entries
                        .map((e) {
                          final idx = e.key;
                          final f = e.value;
                          return BarChartGroupData(
                            x: idx,
                            groupVertically: false,
                            barRods: [
                              BarChartRodData(
                                toY: f.benchmark,
                                color: AppTheme.green
                                    .withValues(alpha: 0.7),
                                width: 10,
                                borderRadius: BorderRadius.circular(2),
                              ),
                              BarChartRodData(
                                toY: f.pct,
                                color: f.severity == 'High'
                                    ? AppTheme.red
                                    : f.severity == 'Medium'
                                        ? AppTheme.amber
                                        : AppTheme.green,
                                width: 10,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ],
                          );
                        })
                        .toList(),
                    titlesData: FlTitlesData(
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          getTitlesWidget: (v, _) => Text(
                            '${v.toStringAsFixed(1)}%',
                            style: const TextStyle(
                                fontSize: 8,
                                color: AppTheme.textSecondary),
                          ),
                        ),
                      ),
                      rightTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      topTitles: const AxisTitles(
                          sideTitles: SideTitles(showTitles: false)),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, _) {
                            final idx = v.toInt();
                            if (idx >= nonZero.length) {
                              return const SizedBox.shrink();
                            }
                            final label = nonZero[idx].label;
                            return Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: RotatedBox(
                                quarterTurns: 1,
                                child: Text(
                                  label.length > 10
                                      ? '${label.substring(0, 10)}..'
                                      : label,
                                  style: const TextStyle(
                                      fontSize: 8,
                                      color: AppTheme.textSecondary),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    gridData: FlGridData(
                      show: true,
                      getDrawingHorizontalLine: (_) => FlLine(
                          color:
                              Colors.grey.withValues(alpha: 0.12),
                          strokeWidth: 1),
                      drawVerticalLine: false,
                    ),
                    borderData: FlBorderData(show: false),
                    barTouchData: BarTouchData(
                      touchTooltipData: BarTouchTooltipData(
                        getTooltipItem:
                            (group, groupIndex, rod, rodIndex) {
                          final f = nonZero[groupIndex];
                          final lbl =
                              rodIndex == 0 ? 'Benchmark' : 'Actual';
                          return BarTooltipItem(
                            '${f.label}\n$lbl: ${rod.toY.toStringAsFixed(2)}%',
                            const TextStyle(
                                color: Colors.white, fontSize: 10),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
              Row(
                children: [
                  _barLegend(
                      AppTheme.green.withValues(alpha: 0.7),
                      'Benchmark'),
                  const SizedBox(width: 12),
                  _barLegend(AppTheme.accent, 'Actual'),
                ],
              ),
              const SizedBox(height: 16),
              const Text('Findings',
                  style: TextStyle(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: AppTheme.textPrimary)),
              const SizedBox(height: 8),
              ...nonZero.map((f) => _FindingRow(finding: f)),
            ] else ...[
              const SizedBox(height: 16),
              const Center(
                child: Text('No abnormal findings recorded.',
                    style:
                        TextStyle(color: AppTheme.textSecondary)),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _barLegend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(2)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary)),
      ],
    );
  }
}

class _FindingRow extends StatelessWidget {
  final ({
    String category,
    String label,
    int total,
    double pct,
    double benchmark,
    String severity
  }) finding;

  const _FindingRow({required this.finding});

  @override
  Widget build(BuildContext context) {
    final color = finding.severity == 'High'
        ? AppTheme.red
        : finding.severity == 'Medium'
            ? AppTheme.amber
            : AppTheme.green;
    final icon = finding.severity == 'High'
        ? Icons.cancel
        : finding.severity == 'Medium'
            ? Icons.warning_amber
            : Icons.check_circle;

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 16),
          const SizedBox(width: 8),
          Expanded(
            child: Text(finding.label,
                style: const TextStyle(
                    fontSize: 13, color: AppTheme.textPrimary)),
          ),
          Text(
            '${finding.pct.toStringAsFixed(2)}%',
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.bold, color: color),
          ),
          const SizedBox(width: 6),
          Text(
            '(BM: ${finding.benchmark.toStringAsFixed(1)}%)',
            style: const TextStyle(
                fontSize: 11, color: AppTheme.textSecondary),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 4: Environmental Conditions
// ---------------------------------------------------------------------------
class _EnvironmentSection extends StatelessWidget {
  final _AuditSnapshot snapshot;
  const _EnvironmentSection({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          if (snapshot.chickQuality != null &&
              (snapshot.chickQuality!.temperature != null ||
                  snapshot.chickQuality!.humidity != null))
            _EnvCard(
              title: 'Chick Holding',
              icon: Icons.egg_outlined,
              temp: snapshot.chickQuality!.temperature,
              humidity: snapshot.chickQuality!.humidity,
              tempRange: (30.0, 33.0),
              humRange: (55.0, 65.0),
              extra: snapshot.chickQuality!.co2Level != null
                  ? 'CO₂: ${snapshot.chickQuality!.co2Level!.toStringAsFixed(0)} ppm'
                  : null,
            ),
          if (snapshot.setterMeasurements != null)
            _EnvCard(
              title: 'Setter',
              icon: Icons.device_thermostat,
              temp: snapshot.setterMeasurements!.temperature,
              humidity: snapshot.setterMeasurements!.humidity,
              tempRange: (37.5, 38.0),
              humRange: (53.0, 58.0),
            ),
          if (snapshot.hatcherMeasurements != null)
            _EnvCard(
              title: 'Hatcher',
              icon: Icons.heat_pump,
              temp: snapshot.hatcherMeasurements!.temperature,
              humidity: snapshot.hatcherMeasurements!.humidity,
              tempRange: (36.9, 37.5),
              humRange: (65.0, 75.0),
            ),
          if (snapshot.vaccineStorage != null)
            _EnvCard(
              title: 'Vaccine Room',
              icon: Icons.vaccines,
              temp: snapshot.vaccineStorage!.roomTemperature,
              humidity: snapshot.vaccineStorage!.roomHumidity,
              tempRange: (2.0, 8.0),
              humRange: (40.0, 60.0),
            ),
          if (snapshot.eggStorage != null)
            _EnvCard(
              title: 'Egg Storage',
              icon: Icons.store,
              temp: snapshot.eggStorage!.temperature,
              humidity: snapshot.eggStorage!.humidity,
              tempRange: (17.0, 19.0),
              humRange: (75.0, 85.0),
              extra: snapshot.eggStorage!.storageDays != null
                  ? 'Storage: ${snapshot.eggStorage!.storageDays}d'
                  : null,
            ),
        ],
      ),
    );
  }
}

class _EnvCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final double? temp;
  final double? humidity;
  final (double, double) tempRange;
  final (double, double) humRange;
  final String? extra;

  const _EnvCard({
    required this.title,
    required this.icon,
    required this.temp,
    required this.humidity,
    required this.tempRange,
    required this.humRange,
    this.extra,
  });

  @override
  Widget build(BuildContext context) {
    final tempOk =
        temp == null ? null : (temp! >= tempRange.$1 && temp! <= tempRange.$2);
    final humOk = humidity == null
        ? null
        : (humidity! >= humRange.$1 && humidity! <= humRange.$2);

    Color flagColor(bool? ok) => ok == null
        ? AppTheme.textSecondary
        : ok
            ? AppTheme.green
            : AppTheme.red;

    return Container(
      width: 150,
      margin: const EdgeInsets.only(right: 10, bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 16, color: AppTheme.secondary),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                      color: AppTheme.textPrimary),
                ),
              ),
            ],
          ),
          const Divider(height: 12),
          if (temp != null)
            _envRow(
              Icons.thermostat,
              '${temp!.toStringAsFixed(1)}°C',
              '${tempRange.$1.toStringAsFixed(1)}-${tempRange.$2.toStringAsFixed(1)}°C',
              flagColor(tempOk),
            ),
          if (humidity != null)
            _envRow(
              Icons.water_drop,
              '${humidity!.toStringAsFixed(1)}%',
              '${humRange.$1.toStringAsFixed(0)}-${humRange.$2.toStringAsFixed(0)}%',
              flagColor(humOk),
            ),
          if (extra != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text(extra!,
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary)),
            ),
        ],
      ),
    );
  }

  Widget _envRow(
      IconData icon, String value, String range, Color color) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Icon(icon, size: 13, color: color),
          const SizedBox(width: 4),
          Text(value,
              style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: color)),
          const Spacer(),
          Text(range,
              style: const TextStyle(
                  fontSize: 9, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 5: Temperature Grids
// ---------------------------------------------------------------------------
class _TempGridSection extends StatelessWidget {
  final _AuditSnapshot snapshot;
  const _TempGridSection({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (snapshot.setterMeasurements != null)
          _TempGridCard(
            title: 'Setter Eggshell Temps (°C)',
            measurements: snapshot.setterMeasurements!,
            isSetter: true,
          ),
        if (snapshot.hatcherMeasurements != null)
          _TempGridCard(
            title: 'Hatcher Chick Vent Temps (°C)',
            measurements: snapshot.hatcherMeasurements!,
            isSetter: false,
          ),
      ],
    );
  }
}

class _TempGridCard extends StatelessWidget {
  final String title;
  final dynamic measurements;
  final bool isSetter;

  const _TempGridCard({
    required this.title,
    required this.measurements,
    required this.isSetter,
  });

  (double, double) get _range => isSetter ? (37.5, 38.0) : (36.9, 37.5);

  Color _cellColor(double? value) {
    if (value == null) return Colors.grey.shade200;
    final (low, high) = _range;
    if (value < low - 1.0) return const Color(0xFF5DADE2);
    if (value < low - 0.3) return const Color(0xFF85C1E9);
    if (value >= low && value <= high) return AppTheme.green;
    if (value > high + 0.3) return const Color(0xFFE59866);
    return AppTheme.red;
  }

  @override
  Widget build(BuildContext context) {
    final cells = [
      [measurements.topFront, measurements.topMiddle, measurements.topBack],
      [measurements.midFront, measurements.midMiddle, measurements.midBack],
      [measurements.botFront, measurements.botMiddle, measurements.botBack],
    ];

    final avg = measurements.gridAverage as double?;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                        color: AppTheme.textPrimary),
                  ),
                ),
                if (avg != null)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _cellColor(avg).withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'Avg: ${avg.toStringAsFixed(2)}°C',
                      style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _cellColor(avg)),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                const SizedBox(width: 48),
                ...['Front', 'Middle', 'Back'].map((h) => Expanded(
                      child: Center(
                        child: Text(
                          h,
                          style: const TextStyle(
                              fontSize: 11,
                              color: AppTheme.textSecondary,
                              fontWeight: FontWeight.w500),
                        ),
                      ),
                    )),
              ],
            ),
            const SizedBox(height: 4),
            ...['Top', 'Mid', 'Bot'].asMap().entries.map((r) {
              final rowIdx = r.key;
              final rowLabel = r.value;
              return Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  children: [
                    SizedBox(
                      width: 48,
                      child: Text(
                        rowLabel,
                        style: const TextStyle(
                            fontSize: 11,
                            color: AppTheme.textSecondary,
                            fontWeight: FontWeight.w500),
                      ),
                    ),
                    ...cells[rowIdx].map((val) {
                      final dVal = val as double?;
                      return Expanded(
                        child: Container(
                          margin: const EdgeInsets.symmetric(horizontal: 2),
                          height: 44,
                          decoration: BoxDecoration(
                            color: _cellColor(dVal),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            dVal != null
                                ? dVal.toStringAsFixed(1)
                                : '--',
                            style: TextStyle(
                              color: dVal != null
                                  ? Colors.white
                                  : Colors.grey,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              );
            }),
            const SizedBox(height: 8),
            Wrap(
              spacing: 10,
              runSpacing: 4,
              children: [
                _legend(const Color(0xFF5DADE2), 'Very Cool'),
                _legend(AppTheme.green, 'Optimal'),
                _legend(const Color(0xFFE59866), 'Warm'),
                _legend(AppTheme.red, 'Hot'),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _legend(Color color, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
              color: color, borderRadius: BorderRadius.circular(3)),
        ),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 10, color: AppTheme.textSecondary)),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Section 6: Vaccine & Egg Storage
// ---------------------------------------------------------------------------
class _StorageSection extends StatelessWidget {
  final _AuditSnapshot snapshot;
  const _StorageSection({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        if (snapshot.vaccineStorage != null)
          _VaccineCard(vs: snapshot.vaccineStorage!),
        if (snapshot.eggStorage != null)
          _EggStorageCard(es: snapshot.eggStorage!),
      ],
    );
  }
}

class _VaccineCard extends StatelessWidget {
  final VaccineStorage vs;
  const _VaccineCard({required this.vs});

  @override
  Widget build(BuildContext context) {
    final vaccines = vs.fridgeVaccines;
    final hvts = vs.hvtContainers;

    final checks = [
      (label: 'Cold Chain Maintained', ok: vs.coldChainMaintained),
      (label: 'Expiry Dates Checked', ok: vs.expiryDatesChecked),
      (label: 'Dilution Protocol Followed', ok: vs.dilutionProtocolFollowed),
      (
        label: 'Vaccination Room Biosecure',
        ok: vs.vaccinationRoomBiosecure
      ),
    ];

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Vaccine Storage',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            if (vs.roomTemperature != null || vs.roomHumidity != null)
              Wrap(
                spacing: 16,
                children: [
                  if (vs.roomTemperature != null)
                    _chip(Icons.thermostat,
                        '${vs.roomTemperature!.toStringAsFixed(1)}°C'),
                  if (vs.roomHumidity != null)
                    _chip(Icons.water_drop,
                        '${vs.roomHumidity!.toStringAsFixed(1)}%'),
                ],
              ),
            const SizedBox(height: 12),
            ...checks.map((c) => Padding(
                  padding: const EdgeInsets.symmetric(vertical: 3),
                  child: Row(
                    children: [
                      Icon(
                        c.ok ? Icons.check_circle : Icons.cancel,
                        color: c.ok ? AppTheme.green : AppTheme.red,
                        size: 17,
                      ),
                      const SizedBox(width: 8),
                      Text(
                        c.label,
                        style: TextStyle(
                            fontSize: 13,
                            color: c.ok
                                ? AppTheme.textPrimary
                                : AppTheme.red),
                      ),
                    ],
                  ),
                )),
            if (vaccines.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'Fridge Vaccines (${vaccines.length})',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              ...vaccines.map((v) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.vaccines,
                            size: 14, color: AppTheme.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(v.name,
                              style: const TextStyle(
                                  fontSize: 12,
                                  color: AppTheme.textPrimary)),
                        ),
                        if (v.expiryDate != null)
                          Text(
                            'Exp: ${DateFormat('MM/yyyy').format(v.expiryDate!)}',
                            style: TextStyle(
                              fontSize: 11,
                              color: v.expiryDate!
                                      .isBefore(DateTime.now())
                                  ? AppTheme.red
                                  : AppTheme.textSecondary,
                            ),
                          ),
                      ],
                    ),
                  )),
            ],
            if (hvts.isNotEmpty) ...[
              const SizedBox(height: 12),
              Text(
                'HVT Containers (${hvts.length})',
                style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppTheme.textSecondary),
              ),
              const SizedBox(height: 6),
              ...hvts.map((h) => Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Row(
                      children: [
                        const Icon(Icons.ac_unit,
                            size: 14, color: AppTheme.secondary),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            h.id ?? 'Container',
                            style: const TextStyle(
                                fontSize: 12,
                                color: AppTheme.textPrimary),
                          ),
                        ),
                        if (h.storageTemp != null)
                          Text(
                            '${h.storageTemp!.toStringAsFixed(0)}°C',
                            style: const TextStyle(
                                fontSize: 11,
                                color: AppTheme.textSecondary),
                          ),
                      ],
                    ),
                  )),
            ],
          ],
        ),
      ),
    );
  }

  Widget _chip(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: AppTheme.secondary),
        const SizedBox(width: 4),
        Text(label,
            style: const TextStyle(
                fontSize: 12, color: AppTheme.textPrimary)),
      ],
    );
  }
}

class _EggStorageCard extends StatelessWidget {
  final EggStorage es;
  const _EggStorageCard({required this.es});

  @override
  Widget build(BuildContext context) {
    final tempOk = es.temperature == null
        ? null
        : (es.temperature! >= 17 && es.temperature! <= 19);
    final humOk = es.humidity == null
        ? null
        : (es.humidity! >= 75 && es.humidity! <= 85);

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Egg Storage',
              style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 14,
                  color: AppTheme.textPrimary),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 16,
              runSpacing: 8,
              children: [
                if (es.temperature != null)
                  _statChip(
                    'Temp',
                    '${es.temperature!.toStringAsFixed(1)}°C',
                    tempOk == true ? AppTheme.green : AppTheme.red,
                  ),
                if (es.humidity != null)
                  _statChip(
                    'Humidity',
                    '${es.humidity!.toStringAsFixed(1)}%',
                    humOk == true ? AppTheme.green : AppTheme.red,
                  ),
                if (es.eggshellTemperature != null)
                  _statChip(
                    'Shell Temp',
                    '${es.eggshellTemperature!.toStringAsFixed(1)}°C',
                    AppTheme.secondary,
                  ),
                if (es.storageDays != null)
                  _statChip(
                    'Storage Days',
                    '${es.storageDays}d',
                    (es.storageDays ?? 0) <= 7
                        ? AppTheme.green
                        : AppTheme.amber,
                  ),
              ],
            ),
            const SizedBox(height: 10),
            if (es.turningFrequency != null)
              _row('Turning Frequency', es.turningFrequency!),
            if (es.uvTrays != null) _row('UV Trays', es.uvTrays!),
            if (es.sanitizationMethod != null)
              _row('Sanitization', es.sanitizationMethod!),
            if (es.sanitizationAgent != null)
              _row('Agent', es.sanitizationAgent!),
          ],
        ),
      ),
    );
  }

  Widget _statChip(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(value,
              style: TextStyle(
                  fontWeight: FontWeight.bold, fontSize: 14, color: color)),
          Text(label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ),
    );
  }

  Widget _row(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        children: [
          Text('$label: ',
              style: const TextStyle(
                  fontSize: 12, color: AppTheme.textSecondary)),
          Text(value,
              style: const TextStyle(
                  fontSize: 12,
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section 6: Problems & Recommendations
// ---------------------------------------------------------------------------

/// Maps egg breakout category keys → condition names in egg_breakout_interpretations
const _kCategoryToCondition = <String, String>{
  'infertile': 'Infertile',
  'earlyDead24h': '24h Early Dead',
  'earlyDead48h': '48h Early Dead',
  'bloodRing': 'Blood Ring',
  'earlyDead': 'Early Dead',
  'midBlackEye': 'Mid Dead / Black Eye',
  'lateDead': 'Late Dead',
  'internalPip': 'Internal Pip',
  'externalPip': 'External Pip',
  'exposedBrain': 'Exposed Brain',
  'crossedBeak': 'Crossed Beak',
  'contaminated': 'Contaminated',
  'feathers': 'Feathers',
  'turned': 'Turned',
  'cracked': 'Cracked',
};

/// Benchmark thresholds (%) per category — exceed triggers a flag
const _kCategoryBenchmarks = <String, double>{
  'infertile': 3.5,
  'earlyDead24h': 0.5,
  'earlyDead48h': 0.5,
  'bloodRing': 0.3,
  'earlyDead': 1.5,
  'midBlackEye': 0.5,
  'lateDead': 1.5,
  'internalPip': 0.5,
  'externalPip': 0.3,
  'exposedBrain': 0.1,
  'crossedBeak': 0.1,
  'contaminated': 0.5,
  'feathers': 0.2,
  'turned': 0.1,
  'cracked': 0.5,
};

class _FlaggedCondition {
  final String conditionName;
  final String category;
  final String hatcheryCauses;
  final String farmCauses;
  final double pct;
  final double benchmark;

  const _FlaggedCondition({
    required this.conditionName,
    required this.category,
    required this.hatcheryCauses,
    required this.farmCauses,
    required this.pct,
    required this.benchmark,
  });
}

class _ProblemsSection extends StatefulWidget {
  final _AuditSnapshot snapshot;
  const _ProblemsSection({required this.snapshot});

  @override
  State<_ProblemsSection> createState() => _ProblemsSectionState();
}

class _ProblemsSectionState extends State<_ProblemsSection> {
  List<_FlaggedCondition> _flagged = [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  @override
  void didUpdateWidget(_ProblemsSection old) {
    super.didUpdateWidget(old);
    if (old.snapshot != widget.snapshot) _evaluate();
  }

  Future<void> _evaluate() async {
    setState(() => _loaded = false);

    final provider = context.read<AppProvider>();
    // Load all interpretations once
    final rows = await provider.db.getEggBreakoutInterpretations();
    final interpretationMap = <String, Map<String, dynamic>>{
      for (final r in rows) (r['condition'] as String): r,
    };

    final flagged = <_FlaggedCondition>[];

    // ── Egg breakout category flags ──────────────────────────────────────────
    final eb = widget.snapshot.eggBreakout;
    if (eb != null) {
      final total = eb.sampleSize ?? 0;
      if (total > 0) {
        for (final cat in _kCategoryBenchmarks.keys) {
          final count = eb.categoryTotal(cat);
          final pct = (count / total) * 100;
          final benchmark = _kCategoryBenchmarks[cat]!;
          if (pct > benchmark) {
            final conditionName = _kCategoryToCondition[cat] ?? cat;
            final interp = interpretationMap[conditionName];
            if (interp != null) {
              flagged.add(_FlaggedCondition(
                conditionName: conditionName,
                category: interp['category'] as String? ?? '',
                hatcheryCauses: interp['hatchery_causes'] as String? ?? '',
                farmCauses: interp['farm_causes'] as String? ?? '',
                pct: pct,
                benchmark: benchmark,
              ));
            }
          }
        }
      }
    }

    // ── Pasgar score flag ────────────────────────────────────────────────────
    final cq = widget.snapshot.chickQuality;
    if (cq != null && cq.pasgarSampleSize > 0 && cq.pasgarScore < 7) {
      flagged.add(_FlaggedCondition(
        conditionName: 'Poor Pasgar Score (${cq.pasgarScore.toStringAsFixed(1)}/10)',
        category: 'Chick Quality',
        hatcheryCauses:
            'Poor hatcher conditions. Incorrect pull time. High CO₂ levels. Incorrect temperature or humidity during hatch. Poor chick handling post-hatch.',
        farmCauses:
            'Breeder flock health issues. Nutritional deficiencies. Egg quality problems. Disease in breeder flock.',
        pct: cq.pasgarScore,
        benchmark: 7.0,
      ));
    }

    // Sort: most severe first (highest excess over benchmark)
    flagged.sort((a, b) {
      final excessA = a.pct - a.benchmark;
      final excessB = b.pct - b.benchmark;
      return excessB.compareTo(excessA);
    });

    if (mounted) {
      setState(() {
        _flagged = flagged;
        _loaded = true;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Center(child: CircularProgressIndicator()),
      );
    }

    if (_flagged.isEmpty) {
      return Card(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              const Icon(Icons.check_circle, color: AppTheme.green, size: 24),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'All parameters within normal range.',
                  style: TextStyle(
                    color: AppTheme.green,
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Column(
      children: _flagged.map((c) => _ProblemCard(condition: c)).toList(),
    );
  }
}

class _ProblemCard extends StatefulWidget {
  final _FlaggedCondition condition;
  const _ProblemCard({required this.condition});

  @override
  State<_ProblemCard> createState() => _ProblemCardState();
}

class _ProblemCardState extends State<_ProblemCard> {
  bool _hatcheryExpanded = false;
  bool _farmExpanded = false;

  Color get _categoryColor {
    switch (widget.condition.category) {
      case 'Embryo Mortality':
        return AppTheme.red;
      case 'Contamination':
        return Colors.purple;
      case 'Malformation':
        return AppTheme.amber;
      case 'Chick Quality':
        return AppTheme.secondary;
      case 'Hatch Timing & Uniformity':
        return Colors.blueGrey;
      default:
        return AppTheme.textSecondary;
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = widget.condition;
    final catColor = _categoryColor;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(color: AppTheme.red.withValues(alpha: 0.25)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Header ──────────────────────────────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Icon(Icons.warning_amber, color: AppTheme.amber, size: 18),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c.conditionName,
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14,
                      color: AppTheme.textPrimary,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: catColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    c.category,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: catColor),
                  ),
                ),
              ],
            ),
            if (c.category != 'Chick Quality') ...[
              const SizedBox(height: 6),
              Text(
                '${c.pct.toStringAsFixed(2)}% (benchmark: ${c.benchmark.toStringAsFixed(1)}%)',
                style: const TextStyle(
                    fontSize: 12, color: AppTheme.textSecondary),
              ),
            ],
            const SizedBox(height: 10),
            // ── Hatchery Causes ──────────────────────────────────────────────
            _collapsibleSection(
              title: 'Hatchery Causes',
              icon: Icons.factory_outlined,
              body: c.hatcheryCauses,
              expanded: _hatcheryExpanded,
              onTap: () =>
                  setState(() => _hatcheryExpanded = !_hatcheryExpanded),
            ),
            const SizedBox(height: 6),
            // ── Farm / Flock Causes ──────────────────────────────────────────
            _collapsibleSection(
              title: 'Farm / Flock Causes',
              icon: Icons.agriculture_outlined,
              body: c.farmCauses,
              expanded: _farmExpanded,
              onTap: () => setState(() => _farmExpanded = !_farmExpanded),
            ),
          ],
        ),
      ),
    );
  }

  Widget _collapsibleSection({
    required String title,
    required IconData icon,
    required String body,
    required bool expanded,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        decoration: BoxDecoration(
          color: AppTheme.background,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Row(
                children: [
                  Icon(icon, size: 15, color: AppTheme.secondary),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      title,
                      style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                          color: AppTheme.textPrimary),
                    ),
                  ),
                  Icon(
                    expanded
                        ? Icons.keyboard_arrow_up
                        : Icons.keyboard_arrow_down,
                    size: 16,
                    color: AppTheme.textSecondary,
                  ),
                ],
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
                child: Text(
                  body,
                  style: const TextStyle(
                      fontSize: 12, color: AppTheme.textSecondary, height: 1.5),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Extensions
// ---------------------------------------------------------------------------
extension _ListExt<T> on List<T> {
  T? firstWhereOrNull(bool Function(T) test) {
    for (final e in this) {
      if (test(e)) return e;
    }
    return null;
  }
}
