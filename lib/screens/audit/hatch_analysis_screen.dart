import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/hatchery_results.dart';
import '../../models/egg_breakout.dart';
import '../../models/chick_quality.dart';
import '../../utils/app_theme.dart';
import '../../widgets/ble_sensor_widget.dart';

// ─────────────────────────────────────────────────────────────────────────────
//  HATCH ANALYSIS SCREEN  (merged: Hatch Results + Egg Breakout + Chick Quality)
// ─────────────────────────────────────────────────────────────────────────────

class HatchAnalysisScreen extends StatefulWidget {
  const HatchAnalysisScreen({super.key});

  @override
  State<HatchAnalysisScreen> createState() => _HatchAnalysisScreenState();
}

class _HatchAnalysisScreenState extends State<HatchAnalysisScreen>
    with TickerProviderStateMixin {

  // ── Sector A: Session Info ────────────────────────────────────────────────
  final _eggStorageDaysCtrl = TextEditingController();

  // ── Sector B: Hatch Results ───────────────────────────────────────────────
  late TabController _hatcherTabCtrl;
  final List<_HatcherData> _hatchers = [];
  final _totalEggsSetCtrl = TextEditingController(text: '19200');

  // Benchmark data for Sector B (loaded async)
  double? _hatchBmkAge;
  double? _bmkHatchability;
  double? _bmkHof;
  double? _bmkFertility;

  // ── Sector C: Egg Breakout (multi-hatch) ─────────────────────────────────
  final List<_BreakoutHatch> _boHatches = [];
  int _selectedBoHatch = 0;

  // Benchmark cache: key="${breed}_${ageFloor}" → {param: value}
  final Map<String, Map<String, double?>> _bmkCache = {};

  // ── Sector D: Chick Quality ───────────────────────────────────────────────
  double? _temperature;
  double? _humidity;

  // Weight hatches — each holds 100 weight controllers
  final List<_WeightHatch> _weightHatches = [];
  int _selectedWeightHatch = 0;

  // YFBM per independent hatch
  final List<List<Map<String, TextEditingController>>> _yfbmHatchRows = [];
  int _selectedYfbmHatch = 0;

  // PASGAR per independent hatch
  final List<_PasgarHatch> _pasgarHatches = [];
  int _selectedPasgarHatch = 0;

  bool _isSaving = false;

  // ── Helpers ───────────────────────────────────────────────────────────────

  double get _flockAgeWeeks =>
      context.read<AppProvider>().currentFlock?.currentAgeWeeks ?? 0.0;

  String get _flockCode =>
      context.read<AppProvider>().currentFlock?.flockCode ?? '—';

  String get _flockBreed =>
      context.read<AppProvider>().currentFlock?.breed ?? '—';

  int get _totalEggsSet =>
      int.tryParse(_totalEggsSetCtrl.text) ?? 19200;

  // Weight stats — uses selected weight hatch
  List<double> get _weights {
    if (_weightHatches.isEmpty) return [];
    final idx = _selectedWeightHatch.clamp(0, _weightHatches.length - 1);
    return _weightHatches[idx].weightCtrls
        .map((c) => double.tryParse(c.text) ?? 0.0)
        .where((v) => v > 0)
        .toList();
  }

  double get _avgWeight {
    final ws = _weights;
    if (ws.isEmpty) return 0;
    return ws.reduce((a, b) => a + b) / ws.length;
  }

  double get _uniformity {
    final avg = _avgWeight;
    if (avg == 0) return 0;
    final ws = _weights;
    final lo = avg * 0.9, hi = avg * 1.1;
    return ws.where((w) => w >= lo && w <= hi).length / ws.length * 100;
  }

  double get _cv {
    final avg = _avgWeight;
    if (avg == 0) return 0;
    final ws = _weights;
    if (ws.length < 2) return 0;
    final v = ws.map((w) => (w - avg) * (w - avg)).reduce((a, b) => a + b) /
        ws.length;
    return math.sqrt(v) / avg * 100;
  }

  // ── Init ──────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _rebuildHatcherTabs();
    _addHatcher();
    _addBoHatch();
    _addWeightHatch();
    _addYfbmHatch();
    _addPasgarHatch();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  void _rebuildHatcherTabs() {
    _hatcherTabCtrl = TabController(
        length: _hatchers.isEmpty ? 1 : _hatchers.length, vsync: this);
  }

  void _addHatcher() {
    setState(() {
      _hatchers.add(_HatcherData());
      _hatcherTabCtrl.dispose();
      _rebuildHatcherTabs();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hatchers.isNotEmpty) {
          _hatcherTabCtrl.animateTo(_hatchers.length - 1);
        }
      });
    });
  }

  void _addBoHatch() {
    setState(() {
      final h = _BreakoutHatch();
      h.addTray();
      _boHatches.add(h);
      _selectedBoHatch = _boHatches.length - 1;
    });
  }

  void _addWeightHatch() {
    setState(() {
      _weightHatches.add(_WeightHatch());
      _selectedWeightHatch = _weightHatches.length - 1;
    });
  }

  void _addYfbmHatch() {
    setState(() {
      _yfbmHatchRows.add([]);
      _selectedYfbmHatch = _yfbmHatchRows.length - 1;
    });
  }

  void _addPasgarHatch() {
    setState(() {
      _pasgarHatches.add(_PasgarHatch());
      _selectedPasgarHatch = _pasgarHatches.length - 1;
    });
  }

  void _removeHatcher(int i) {
    if (_hatchers.length <= 1) return;
    setState(() {
      _hatchers[i].dispose();
      _hatchers.removeAt(i);
      _hatcherTabCtrl.dispose();
      _rebuildHatcherTabs();
      if (_hatcherTabCtrl.index >= _hatchers.length) {
        _hatcherTabCtrl.animateTo(_hatchers.length - 1);
      }
    });
  }

  void _removeBoHatch(int i) {
    if (_boHatches.length <= 1) return;
    setState(() {
      _boHatches[i].dispose();
      _boHatches.removeAt(i);
      if (_selectedBoHatch >= _boHatches.length) {
        _selectedBoHatch = _boHatches.length - 1;
      }
    });
  }

  void _removeWeightHatch(int i) {
    if (_weightHatches.length <= 1) return;
    setState(() {
      _weightHatches[i].dispose();
      _weightHatches.removeAt(i);
      if (_selectedWeightHatch >= _weightHatches.length) {
        _selectedWeightHatch = _weightHatches.length - 1;
      }
    });
  }

  void _removeYfbmHatch(int i) {
    if (_yfbmHatchRows.length <= 1) return;
    setState(() {
      final rows = _yfbmHatchRows.removeAt(i);
      for (final r in rows) { r['total']?.dispose(); r['yolk']?.dispose(); }
      if (_selectedYfbmHatch >= _yfbmHatchRows.length) {
        _selectedYfbmHatch = _yfbmHatchRows.length - 1;
      }
    });
  }

  void _removePasgarHatch(int i) {
    if (_pasgarHatches.length <= 1) return;
    setState(() {
      _pasgarHatches[i].dispose();
      _pasgarHatches.removeAt(i);
      if (_selectedPasgarHatch >= _pasgarHatches.length) {
        _selectedPasgarHatch = _pasgarHatches.length - 1;
      }
    });
  }

  void _loadExisting() {
    final p = context.read<AppProvider>();

    // Load hatchery results
    final hr = p.hatcheryResults;
    if (hr != null) {
      _eggStorageDaysCtrl.text = hr.eggStorageDays?.toString() ?? '';
      _totalEggsSetCtrl.text = (hr.totalHatcherCapacity ?? 19200).toString();
      if (hr.hatchers.isNotEmpty) {
        for (final h in _hatchers) { h.dispose(); }
        _hatchers.clear();
        for (final e in hr.hatchers) {
          _hatchers.add(_HatcherData.fromEntry(e));
        }
        _hatcherTabCtrl.dispose();
        _rebuildHatcherTabs();
      }
    }

    // Load egg breakout
    final eb = p.eggBreakout;
    if (eb != null) {
      if (eb.hatchesJson != null && eb.hatchesJson!.isNotEmpty) {
        // Load new multi-hatch format
        for (final bh in _boHatches) { bh.dispose(); }
        _boHatches.clear();
        for (final hatchMap in eb.hatches) {
          final bh = _BreakoutHatch();
          bh.incubatorIdCtrl.text = hatchMap['incubatorId'] as String? ?? '';
          bh.hatcherIdCtrl.text = hatchMap['hatcherId'] as String? ?? '';
          bh.sampleSizeCtrl.text = (hatchMap['sampleSize'] ?? '').toString();
          final traysRaw = hatchMap['trays'] as List? ?? [];
          for (final trayMap in traysRaw) {
            final t = _TrayState();
            t.breakoutDateCtrl.text =
                (trayMap['breakoutDate'] ?? 21).toString();
            t.trayIdCtrl.text = trayMap['trayId']?.toString() ?? '';
            t.position = trayMap['trayPosition'] as String? ?? 'Top';
            for (final k in kEggBreakoutCategories) {
              t.ctrls[k]?.text = (trayMap[k] ?? 0).toString();
            }
            bh.trays.add(t);
          }
          if (bh.trays.isEmpty) bh.addTray();
          _boHatches.add(bh);
        }
        if (_boHatches.isEmpty) _addBoHatch();
        _selectedBoHatch = 0;
      } else if (eb.trayData.isNotEmpty) {
        // Migrate old flat format into one hatch
        for (final bh in _boHatches) { bh.dispose(); }
        _boHatches.clear();
        final bh = _BreakoutHatch();
        bh.incubatorIdCtrl.text = eb.incubatorId ?? '';
        bh.hatcherIdCtrl.text = eb.hatcherId ?? '';
        bh.sampleSizeCtrl.text = eb.sampleSize?.toString() ?? '';
        for (final trayMap in eb.trayData) {
          final t = _TrayState();
          t.trayIdCtrl.text = trayMap['trayId']?.toString() ?? '';
          t.position = trayMap['trayPosition'] as String? ?? 'Top';
          for (final k in kEggBreakoutCategories) {
            t.ctrls[k]?.text = (trayMap[k] ?? 0).toString();
          }
          bh.trays.add(t);
        }
        if (bh.trays.isEmpty) bh.addTray();
        _boHatches.add(bh);
        _selectedBoHatch = 0;
      }
    }

    // Load chick quality
    final cq = p.chickQuality;
    if (cq != null) {
      _temperature = cq.temperature;
      _humidity = cq.humidity;

      // Load per-hatch weights
      if (cq.weightsHatchJson != null && cq.weightsHatchJson!.isNotEmpty) {
        for (final wh in _weightHatches) { wh.dispose(); }
        _weightHatches.clear();
        final hatchWeights = jsonDecode(cq.weightsHatchJson!) as List;
        for (final hw in hatchWeights) {
          final wh = _WeightHatch();
          final wList = (hw as List).cast<num>();
          for (int i = 0; i < wList.length && i < _WeightHatch.count; i++) {
            wh.weightCtrls[i].text = wList[i].toDouble().toStringAsFixed(1);
          }
          _weightHatches.add(wh);
        }
        if (_weightHatches.isEmpty) _weightHatches.add(_WeightHatch());
        _selectedWeightHatch = 0;
      } else if (cq.weights.isNotEmpty) {
        // Migrate flat weights into first hatch
        if (_weightHatches.isEmpty) _weightHatches.add(_WeightHatch());
        final wh = _weightHatches[0];
        for (int i = 0; i < cq.weights.length && i < _WeightHatch.count; i++) {
          wh.weightCtrls[i].text = cq.weights[i].toStringAsFixed(1);
        }
      }

      // Load per-hatch YFBM (independent)
      if (cq.yfbmHatchDataJson != null && cq.yfbmHatchDataJson!.isNotEmpty) {
        for (final rows in _yfbmHatchRows) {
          for (final r in rows) { r['total']?.dispose(); r['yolk']?.dispose(); }
        }
        _yfbmHatchRows.clear();
        final hatchYfbm = jsonDecode(cq.yfbmHatchDataJson!) as List;
        for (final hatchData in hatchYfbm) {
          final samples = (hatchData['samples'] as List?) ?? [];
          _yfbmHatchRows.add(samples.map<Map<String, TextEditingController>>((s) => {
            'total': TextEditingController(
                text: (s['total_weight'] as num?)?.toStringAsFixed(2) ?? ''),
            'yolk': TextEditingController(
                text: (s['yolk_weight'] as num?)?.toStringAsFixed(2) ?? ''),
          }).toList());
        }
        if (_yfbmHatchRows.isEmpty) _yfbmHatchRows.add([]);
        _selectedYfbmHatch = 0;
      } else if (cq.yfbmPairs.isNotEmpty) {
        // Migrate old flat YFBM into first hatch
        if (_yfbmHatchRows.isEmpty) _yfbmHatchRows.add([]);
        _yfbmHatchRows[0] = cq.yfbmPairs.map((pair) => {
          'total': TextEditingController(
              text: pair['total_weight']?.toStringAsFixed(2) ?? ''),
          'yolk': TextEditingController(
              text: pair['yolk_weight']?.toStringAsFixed(2) ?? ''),
        }).toList();
      }

      // Load per-hatch PASGAR (independent)
      if (cq.pasgarHatchDataJson != null && cq.pasgarHatchDataJson!.isNotEmpty) {
        for (final ph in _pasgarHatches) { ph.dispose(); }
        _pasgarHatches.clear();
        final hatchPasgar = jsonDecode(cq.pasgarHatchDataJson!) as List;
        for (final d in hatchPasgar) {
          final ph = _PasgarHatch();
          ph.sampleSizeCtrl.text = (d['sampleSize'] ?? 100).toString();
          ph.reflexesCtrl.text = (d['reflexes'] ?? 0).toString();
          ph.beakCtrl.text = (d['beak'] ?? 0).toString();
          ph.navelCtrl.text = (d['navel'] ?? 0).toString();
          ph.bellyCtrl.text = (d['belly'] ?? 0).toString();
          ph.legsCtrl.text = (d['legs'] ?? 0).toString();
          ph.featheredCtrl.text = (d['featheredCount'] ?? '').toString();
          _pasgarHatches.add(ph);
        }
        if (_pasgarHatches.isEmpty) _pasgarHatches.add(_PasgarHatch());
        _selectedPasgarHatch = 0;
      } else {
        // Migrate old flat PASGAR into first hatch
        if (_pasgarHatches.isEmpty) _pasgarHatches.add(_PasgarHatch());
        final ph = _pasgarHatches[0];
        ph.sampleSizeCtrl.text = cq.pasgarSampleSize.toString();
        ph.reflexesCtrl.text = cq.reflexesDefects.toString();
        ph.beakCtrl.text = cq.beakDefects.toString();
        ph.navelCtrl.text = cq.navelDefects.toString();
        ph.bellyCtrl.text = cq.bellyDefects.toString();
        ph.legsCtrl.text = cq.legsDefects.toString();
        ph.featheredCtrl.text = cq.featheredCount?.toString() ?? '';
      }
    }

    if (mounted) {
      setState(() {});
      _loadHatchBenchmarks();
    }
  }

  @override
  void dispose() {
    _hatcherTabCtrl.dispose();
    _eggStorageDaysCtrl.dispose();
    _totalEggsSetCtrl.dispose();
    for (final h in _hatchers) { h.dispose(); }
    for (final bh in _boHatches) { bh.dispose(); }
    for (final rows in _yfbmHatchRows) {
      for (final r in rows) { r['total']?.dispose(); r['yolk']?.dispose(); }
    }
    for (final ph in _pasgarHatches) { ph.dispose(); }
    for (final wh in _weightHatches) { wh.dispose(); }
    super.dispose();
  }

  // ── Benchmark loading ─────────────────────────────────────────────────────

  Future<void> _loadHatchBenchmarks() async {
    final p = context.read<AppProvider>();
    final breed = p.currentFlock?.breed ?? '';
    final eggStorageDays = int.tryParse(_eggStorageDaysCtrl.text) ?? 0;
    final bmkAge = _flockAgeWeeks - 3.0 + eggStorageDays / 7.0;
    if (!mounted) return;
    setState(() { _hatchBmkAge = bmkAge > 0 ? bmkAge : null; });
    if (breed.isEmpty) return;
    final db = p.db;
    final h = await db.getBenchmark(breed, bmkAge, 'Hatchability');
    final hof = await db.getBenchmark(breed, bmkAge, 'HOF');
    final f = await db.getBenchmark(breed, bmkAge, 'Fertility');
    if (mounted) setState(() { _bmkHatchability = h; _bmkHof = hof; _bmkFertility = f; });
  }

  Future<Map<String, double?>> _getBmkForBreakout(double bmkAge) async {
    final p = context.read<AppProvider>();
    final breed = p.currentFlock?.breed ?? '';
    final key = '${breed}_${bmkAge.floor()}';
    if (_bmkCache.containsKey(key)) return _bmkCache[key]!;
    final db = p.db;
    final infertile = await db.getBenchmark(breed, bmkAge, 'Infertile');
    final earlyDead = await db.getBenchmark(breed, bmkAge, 'EarlyDead');
    final lateDead = await db.getBenchmark(breed, bmkAge, 'LateDead');
    final result = {'Infertile': infertile, 'EarlyDead': earlyDead, 'LateDead': lateDead};
    _bmkCache[key] = result;
    return result;
  }

  double _bmkForCategory(String key, Map<String, double?> dbBmks) {
    const Map<String, double> fallback = {
      'infertile': 5.0, 'earlyDead24h': 0.5, 'earlyDead48h': 0.3,
      'bloodRing': 0.5, 'earlyDead': 1.2, 'midBlackEye': 0.5,
      'feathers': 0.3, 'turned': 0.5, 'internalPip': 0.5,
      'lateDead': 1.2, 'externalPip': 0.5, 'exposedBrain': 0.1,
      'crossedBeak': 0.1, 'contaminated': 0.3, 'cracked': 0.5,
    };
    if (key == 'infertile' && dbBmks['Infertile'] != null) { return dbBmks['Infertile']!; }
    if ({'earlyDead24h', 'earlyDead48h', 'bloodRing', 'earlyDead'}.contains(key) &&
        dbBmks['EarlyDead'] != null) { return dbBmks['EarlyDead']! / 4.0; }
    if ({'lateDead', 'internalPip', 'externalPip', 'midBlackEye'}.contains(key) &&
        dbBmks['LateDead'] != null) { return dbBmks['LateDead']! / 4.0; }
    return fallback[key] ?? 1.0;
  }

  // ── Save all ──────────────────────────────────────────────────────────────

  Future<void> _saveAll() async {
    final p = context.read<AppProvider>();
    final session = p.currentSession;
    if (session == null) return;

    setState(() => _isSaving = true);
    try {
      // 1. Hatchery Results
      final entries = _hatchers.map((h) => HatcherEntry(
            setterId: h.setterIdCtrl.text,
            hatcherId: h.hatcherIdCtrl.text,
            hatched: int.tryParse(h.hatchedCtrl.text),
            culled: int.tryParse(h.culledCtrl.text),
            dead: int.tryParse(h.deadCtrl.text),
            infertileCount: int.tryParse(h.infertileCtrl.text),
            fertilityPercent: double.tryParse(h.fertilityCtrl.text),
          )).toList();

      final existingHr = p.hatcheryResults;
      final hr = HatcheryResults(
        id: existingHr?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: p.currentCustomer?.id ?? session.customerId,
        flockId: p.currentFlock?.id ?? session.flockId,
        eggStorageDays: int.tryParse(_eggStorageDaysCtrl.text),
        totalHatcherCapacity: _totalEggsSet,
        isCompleted: true,
        createdAt: existingHr?.createdAt ?? DateTime.now(),
      );
      hr.hatchers = entries;
      await p.saveHatcheryResults(hr);

      // 2. Egg Breakout (new multi-hatch format)
      final hatchesData = _boHatches.map((bh) {
        final traysData = bh.trays.map((t) {
          final map = <String, dynamic>{
            'breakoutDate': int.tryParse(t.breakoutDateCtrl.text) ?? 21,
            'trayId': t.trayIdCtrl.text,
            'trayPosition': t.position,
          };
          for (final k in kEggBreakoutCategories) {
            map[k] = int.tryParse(t.ctrls[k]?.text ?? '0') ?? 0;
          }
          return map;
        }).toList();
        return {
          'incubatorId': bh.incubatorIdCtrl.text,
          'hatcherId': bh.hatcherIdCtrl.text,
          'sampleSize': int.tryParse(bh.sampleSizeCtrl.text) ?? 0,
          'trays': traysData,
        };
      }).toList();

      final existingEb = p.eggBreakout;
      final eb = EggBreakout(
        id: existingEb?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: session.customerId,
        flockId: session.flockId,
        eggStorageDays: int.tryParse(_eggStorageDaysCtrl.text),
        hatchesJson: jsonEncode(hatchesData),
        isCompleted: true,
        createdAt: existingEb?.createdAt ?? DateTime.now(),
      );
      await p.saveEggBreakout(eb);

      // 3. Chick Quality
      // Per-hatch weights
      final weightsHatchData = _weightHatches.map((wh) =>
        wh.weightCtrls.map((c) => double.tryParse(c.text) ?? 0.0).toList()
      ).toList();
      // Flat first-hatch weights for backward compat
      final flatWeights = _weightHatches.isEmpty ? <double>[] :
          _weightHatches[0].weightCtrls
              .map((c) => double.tryParse(c.text) ?? 0.0)
              .where((v) => v > 0).toList();

      // Per-hatch YFBM
      final yfbmHatchData = _yfbmHatchRows.asMap().entries.map((e) {
        final samples = e.value.map((row) => {
          'total_weight': double.tryParse(row['total']?.text ?? '') ?? 0.0,
          'yolk_weight': double.tryParse(row['yolk']?.text ?? '') ?? 0.0,
        }).toList();
        return {'hatchIdx': e.key, 'samples': samples};
      }).toList();

      // Per-hatch PASGAR
      final pasgarHatchData = _pasgarHatches.asMap().entries.map((e) => {
        'hatchIdx': e.key,
        'sampleSize': int.tryParse(e.value.sampleSizeCtrl.text) ?? 100,
        'reflexes': int.tryParse(e.value.reflexesCtrl.text) ?? 0,
        'beak': int.tryParse(e.value.beakCtrl.text) ?? 0,
        'navel': int.tryParse(e.value.navelCtrl.text) ?? 0,
        'belly': int.tryParse(e.value.bellyCtrl.text) ?? 0,
        'legs': int.tryParse(e.value.legsCtrl.text) ?? 0,
        'featheredCount': int.tryParse(e.value.featheredCtrl.text),
      }).toList();

      final existingCq = p.chickQuality;
      final cq = ChickQuality(
        id: existingCq?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: session.customerId,
        flockId: session.flockId,
        eggStorageDays: int.tryParse(_eggStorageDaysCtrl.text),
        temperature: _temperature,
        humidity: _humidity,
        sampleSize: _WeightHatch.count,
        weights: flatWeights,
        yfbmDataJson: '[]',
        yfbmHatchDataJson: jsonEncode(yfbmHatchData),
        weightsHatchJson: jsonEncode(weightsHatchData),
        pasgarHatchDataJson: jsonEncode(pasgarHatchData),
        isCompleted: true,
        createdAt: existingCq?.createdAt ?? DateTime.now(),
      );
      await p.saveChickQuality(cq);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hatch Analysis saved!'),
            backgroundColor: AppTheme.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Hatch Analysis')),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              children: [
                _buildSessionInfo(),
                const SizedBox(height: 12),
                _buildHatchResults(),
                const SizedBox(height: 12),
                _buildEggBreakout(),
                const SizedBox(height: 12),
                _buildChickQuality(),
                const SizedBox(height: 8),
              ],
            ),
          ),
          _buildSaveBar(),
        ],
      ),
    );
  }

  // ── Sector A: Session Info (no card, just info row) ───────────────────────

  Widget _buildSessionInfo() {
    return Row(
      children: [
        Expanded(child: _InfoChip(label: 'Flock', value: _flockCode)),
        const SizedBox(width: 8),
        Expanded(child: _InfoChip(label: 'Breed', value: _flockBreed)),
        const SizedBox(width: 8),
        Expanded(
          child: _InfoChip(
              label: 'Age',
              value: '${_flockAgeWeeks.toStringAsFixed(1)} wks'),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _EditableInfoChip(
            label: 'Egg Storage Days',
            controller: _eggStorageDaysCtrl,
            onChanged: (_) {
              setState(() {});
              _loadHatchBenchmarks();
            },
          ),
        ),
      ],
    );
  }

  // ── Sector B: Hatch Results ───────────────────────────────────────────────

  Widget _buildHatchResults() {
    return _SectionCard(
      title: 'Hatch Results',
      icon: Icons.analytics_outlined,
      child: Column(
        children: [
          _buildHatchSelectorBar(
            count: _hatchers.length,
            selected: _hatcherTabCtrl.index,
            onSelect: (i) => setState(() { _hatcherTabCtrl.animateTo(i); }),
            onAdd: _addHatcher,
            onRemove: _removeHatcher,
          ),
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (context, setInner) {
              final idx = _hatcherTabCtrl.index.clamp(0, _hatchers.length - 1);
              final h = _hatchers[idx];
              final cap = _totalEggsSet;
              final hatched = int.tryParse(h.hatchedCtrl.text);
              final fert = double.tryParse(h.fertilityCtrl.text);
              final hatchPct =
                  (hatched != null && cap > 0) ? hatched / cap * 100 : null;
              final hofPct = (hatchPct != null && fert != null && fert > 0)
                  ? hatchPct / fert * 100
                  : null;

              // Dynamic benchmark strings
              final bmkH = _bmkHatchability != null
                  ? '≥ ${_bmkHatchability!.toStringAsFixed(1)}%'
                  : '≥ 85%';
              final bmkHof = _bmkHof != null
                  ? '≥ ${_bmkHof!.toStringAsFixed(1)}%'
                  : '≥ 90%';
              final bmkF = _bmkFertility != null
                  ? '≥ ${_bmkFertility!.toStringAsFixed(1)}%'
                  : '≥ 94%';
              final bmkHThresh = _bmkHatchability ?? 85.0;
              final bmkHofThresh = _bmkHof ?? 90.0;
              final bmkFThresh = _bmkFertility ?? 94.0;

              return Column(
                children: [
                  Row(children: [
                    Expanded(child: _inputField(h.setterIdCtrl, 'Setter ID')),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField(h.hatcherIdCtrl, 'Hatcher ID',
                        onChanged: (_) => setInner(() {}))),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(
                      child: _inputField(_totalEggsSetCtrl, 'Total Eggs Set',
                          isNumber: true,
                          onChanged: (_) { setInner(() {}); setState(() {}); }),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _inputField(h.hatchedCtrl, 'Hatched',
                          isNumber: true,
                          onChanged: (_) { setInner(() {}); setState(() {}); }),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _inputField(h.culledCtrl, 'Culled', isNumber: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField(h.deadCtrl, 'Dead', isNumber: true)),
                  ]),
                  const SizedBox(height: 8),
                  Row(children: [
                    Expanded(child: _inputField(h.infertileCtrl, 'Infertile Count', isNumber: true)),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField(h.fertilityCtrl, 'Fertility %',
                        isDecimal: true, onChanged: (_) => setInner(() {}))),
                  ]),
                  const SizedBox(height: 10),
                  // Benchmark Age chip
                  if (_hatchBmkAge != null)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: _BmkAgeChip(
                          ageWeeks: _hatchBmkAge!, breed: _flockBreed),
                    ),
                  const SizedBox(height: 10),
                  // KPI chips
                  Row(children: [
                    Expanded(child: _KpiChip(
                      label: 'Hatchability',
                      value: hatchPct != null ? '${hatchPct.toStringAsFixed(1)}%' : '—',
                      benchmark: bmkH,
                      color: hatchPct == null ? AppTheme.textSecondary
                          : hatchPct >= bmkHThresh ? AppTheme.green : AppTheme.red,
                    )),
                    const SizedBox(width: 6),
                    Expanded(child: _KpiChip(
                      label: 'HOF',
                      value: hofPct != null ? '${hofPct.toStringAsFixed(1)}%' : '—',
                      benchmark: bmkHof,
                      color: hofPct == null ? AppTheme.textSecondary
                          : hofPct >= bmkHofThresh ? AppTheme.green : AppTheme.red,
                    )),
                    const SizedBox(width: 6),
                    Expanded(child: _KpiChip(
                      label: 'Fertility',
                      value: fert != null ? '${fert.toStringAsFixed(1)}%' : '—',
                      benchmark: bmkF,
                      color: fert == null ? AppTheme.textSecondary
                          : fert >= bmkFThresh ? AppTheme.green : AppTheme.red,
                    )),
                  ]),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  // ── Sector C: Egg Breakout (multi-hatch) ─────────────────────────────────

  Widget _buildEggBreakout() {
    return _SectionCard(
      title: 'Egg Breakout Analysis',
      icon: Icons.biotech_outlined,
      child: Column(
        children: [
          _buildHatchSelectorBar(
            count: _boHatches.length,
            selected: _selectedBoHatch,
            onSelect: (i) => setState(() { _selectedBoHatch = i; }),
            onAdd: _addBoHatch,
            onRemove: _removeBoHatch,
          ),
          const SizedBox(height: 12),
          StatefulBuilder(
            builder: (ctx, setInner) {
              final hIdx = _selectedBoHatch.clamp(0, _boHatches.length - 1);
              final bh = _boHatches[hIdx];
              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Main-hatch level fields
                  Row(children: [
                    Expanded(child: _inputField(bh.incubatorIdCtrl, 'Incubator ID')),
                    const SizedBox(width: 8),
                    Expanded(child: _inputField(bh.hatcherIdCtrl, 'Hatcher ID',
                        onChanged: (_) => setInner(() {}))),
                  ]),
                  const SizedBox(height: 8),
                  _inputField(bh.sampleSizeCtrl, 'Sample Size', isNumber: true),
                  const SizedBox(height: 12),

                  // Tray selector + add tray
                  Row(
                    children: [
                      Expanded(
                        child: bh.trays.length > 1
                            ? SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: Row(
                                  children: List.generate(bh.trays.length, (ti) {
                                    final isSel = ti == bh.selectedTray;
                                    return Padding(
                                      padding: const EdgeInsets.only(right: 6),
                                      child: GestureDetector(
                                        onTap: () => setState(() { bh.selectedTray = ti; }),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                                          decoration: BoxDecoration(
                                            color: isSel ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.08),
                                            borderRadius: BorderRadius.circular(16),
                                            border: Border.all(
                                              color: isSel ? AppTheme.primary : AppTheme.primary.withValues(alpha: 0.2),
                                            ),
                                          ),
                                          child: Text('T${ti + 1}',
                                            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500,
                                              color: isSel ? Colors.white : AppTheme.primary)),
                                        ),
                                      ),
                                    );
                                  }),
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      TextButton.icon(
                        onPressed: () => setState(() { bh.addTray(); bh.selectedTray = bh.trays.length - 1; }),
                        icon: const Icon(Icons.add, size: 14, color: AppTheme.primary),
                        label: const Text('Add Tray', style: TextStyle(fontSize: 11, color: AppTheme.primary)),
                        style: TextButton.styleFrom(padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Per-tray form
                  Builder(builder: (ctx) {
                    final tIdx = bh.selectedTray.clamp(0, bh.trays.length - 1);
                    final t = bh.trays[tIdx];
                    final sampleSize = int.tryParse(bh.sampleSizeCtrl.text) ?? 100;

                    return StatefulBuilder(builder: (ctx2, setTray) {
                      // Compute breakout bmk age for this tray
                      final breakoutDays = int.tryParse(t.breakoutDateCtrl.text) ?? 21;
                      final eggStorageDays = int.tryParse(_eggStorageDaysCtrl.text) ?? 0;
                      final trayBmkAge = _flockAgeWeeks - breakoutDays / 7.0 + eggStorageDays / 7.0;

                      return FutureBuilder<Map<String, double?>>(
                        future: trayBmkAge > 0 ? _getBmkForBreakout(trayBmkAge) : Future.value({}),
                        builder: (ctx3, snap) {
                          final dbBmks = snap.data ?? {};

                          // Count severities
                          int high = 0, med = 0, ok = 0;
                          for (final key in kEggBreakoutCategories) {
                            final count = int.tryParse(t.ctrls[key]?.text ?? '0') ?? 0;
                            final pct = sampleSize > 0 ? count / sampleSize * 100 : 0.0;
                            final bmk = _bmkForCategory(key, dbBmks);
                            final delta = pct - bmk;
                            if (delta > bmk * 1.5) { high++; }
                            else if (delta > bmk * 0.5) { med++; }
                            else { ok++; }
                          }

                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [
                                Expanded(
                                  child: TextField(
                                    controller: t.trayIdCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Tray ID', isDense: true),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButtonFormField<String>(
                                    initialValue: t.position,
                                    decoration: const InputDecoration(labelText: 'Position', isDense: true),
                                    items: kTrayPositions.map((p) =>
                                        DropdownMenuItem(value: p, child: Text(p))).toList(),
                                    onChanged: (v) { if (v != null) setState(() => t.position = v); },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                SizedBox(
                                  width: 70,
                                  child: TextField(
                                    controller: t.breakoutDateCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(labelText: 'Brkout d', isDense: true),
                                    onChanged: (_) => setTray(() {}),
                                  ),
                                ),
                              ]),
                              const SizedBox(height: 10),
                              // Benchmark age
                              if (trayBmkAge > 0)
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 8),
                                  child: _BmkAgeChip(ageWeeks: trayBmkAge, breed: _flockBreed),
                                ),
                              // Severity chips
                              Row(children: [
                                Expanded(child: _SevChip(label: 'High', count: high, color: AppTheme.red)),
                                const SizedBox(width: 6),
                                Expanded(child: _SevChip(label: 'Medium', count: med, color: AppTheme.amber)),
                                const SizedBox(width: 6),
                                Expanded(child: _SevChip(label: 'Within Bmk', count: ok, color: AppTheme.green)),
                              ]),
                              const SizedBox(height: 12),
                              _buildBreakoutTable(t, sampleSize, dbBmks, setTray),
                            ],
                          );
                        },
                      );
                    });
                  }),
                ],
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildBreakoutTable(
      _TrayState t, int sampleSize, Map<String, double?> dbBmks, StateSetter setInner) {
    return Column(
      children: [
        // Column headers
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          child: Row(children: [
            const Expanded(flex: 3, child: SizedBox()),
            const SizedBox(width: 56, child: Text('Count',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.textSecondary))),
            const SizedBox(width: 6),
            const SizedBox(width: 38, child: Text('%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.textSecondary))),
            const SizedBox(width: 6),
            const SizedBox(width: 44, child: Text('BMK%',
              textAlign: TextAlign.right,
              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w600, color: AppTheme.textSecondary))),
            const SizedBox(width: 6),
            const SizedBox(width: 34),
          ]),
        ),
        ...kEggBreakoutCategories.asMap().entries.map((entry) {
        final ci = entry.key;
        final catKey = kEggBreakoutCategories[ci];
        final label = kEggBreakoutCategoryLabels[catKey] ?? catKey;
        final ctrl = t.ctrls[catKey]!;
        final count = int.tryParse(ctrl.text) ?? 0;
        final pct = sampleSize > 0 ? count / sampleSize * 100 : 0.0;
        final bmk = _bmkForCategory(catKey, dbBmks);
        final delta = pct - bmk;

        Color statusColor;
        String statusLabel;
        if (delta > bmk * 1.5) {
          statusColor = AppTheme.red; statusLabel = 'High';
        } else if (delta > bmk * 0.5) {
          statusColor = AppTheme.amber; statusLabel = 'Med';
        } else {
          statusColor = AppTheme.green; statusLabel = 'OK';
        }
        final isOver = delta > bmk * 0.5;

        return Container(
          decoration: BoxDecoration(
            color: isOver ? statusColor.withValues(alpha: 0.06) : Colors.transparent,
            border: Border(
              bottom: BorderSide(color: Colors.grey.shade100, width: 1),
              left: isOver ? BorderSide(color: statusColor, width: 3) : BorderSide.none,
            ),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: Text(label,
                style: TextStyle(fontSize: 12,
                  color: isOver ? AppTheme.textPrimary : AppTheme.textSecondary,
                  fontWeight: isOver ? FontWeight.w500 : FontWeight.normal)),
            ),
            SizedBox(
              width: 56,
              child: TextField(
                controller: ctrl,
                keyboardType: TextInputType.number,
                textAlign: TextAlign.center,
                textInputAction: ci < kEggBreakoutCategories.length - 1
                    ? TextInputAction.next : TextInputAction.done,
                style: const TextStyle(fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
                  filled: true, fillColor: Colors.white,
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(6),
                      borderSide: BorderSide(color: Colors.grey.shade300)),
                ),
                onChanged: (v) { setInner(() {}); },
              ),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 38,
              child: Text('${pct.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: TextStyle(fontSize: 11,
                  color: isOver ? statusColor : AppTheme.textSecondary,
                  fontWeight: isOver ? FontWeight.w600 : FontWeight.normal)),
            ),
            const SizedBox(width: 6),
            SizedBox(
              width: 44,
              child: Text('${bmk.toStringAsFixed(1)}%',
                textAlign: TextAlign.right,
                style: const TextStyle(
                  fontSize: 10,
                  color: AppTheme.textSecondary,
                )),
            ),
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(statusLabel,
                style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: statusColor)),
            ),
          ]),
        );
        }),
      ],
    );
  }

  // ── Sector D: Chick Quality ───────────────────────────────────────────────

  Widget _buildChickQuality() {
    return _SectionCard(
      title: 'Chick Quality',
      icon: Icons.egg_alt_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _SubSectionLabel(label: 'Environmental Conditions'),
          BleSensorWidget(
            temperature: _temperature,
            humidity: _humidity,
            onReading: (t, h) => setState(() { _temperature = t; _humidity = h; }),
          ),
          const SizedBox(height: 16),
          _SubSectionLabel(label: 'Weight Uniformity (100 chicks)'),
          _buildWeightSection(),
          const SizedBox(height: 16),
          _buildYfbmSection(),
          const SizedBox(height: 16),
          _buildPasgarSection(),
        ],
      ),
    );
  }

  Widget _buildWeightSection() {
    final avg = _avgWeight;
    final uni = _uniformity;
    final cv = _cv;
    final hasData = avg > 0;
    final whIdx = _selectedWeightHatch.clamp(0, _weightHatches.length - 1);
    final currentWh = _weightHatches.isEmpty ? null : _weightHatches[whIdx];
    final filled = currentWh?.weightCtrls.where((c) => c.text.trim().isNotEmpty).length ?? 0;

    return Column(children: [
      _buildHatchSelectorBar(
        count: _weightHatches.length,
        selected: _selectedWeightHatch,
        onSelect: (i) => setState(() { _selectedWeightHatch = i; }),
        onAdd: _addWeightHatch,
        onRemove: _removeWeightHatch,
      ),
      const SizedBox(height: 8),
      Row(children: [
        Expanded(child: _KpiChip(
          label: 'Avg Weight',
          value: hasData ? '${avg.toStringAsFixed(1)} g' : '—',
          color: hasData ? AppTheme.primary : AppTheme.textSecondary,
        )),
        const SizedBox(width: 6),
        Expanded(child: _KpiChip(
          label: 'Uniformity',
          value: hasData ? '${uni.toStringAsFixed(1)}%' : '—',
          benchmark: '≥ 85%',
          color: !hasData ? AppTheme.textSecondary
              : uni >= 85 ? AppTheme.green
              : uni >= 75 ? AppTheme.amber : AppTheme.red,
        )),
        const SizedBox(width: 6),
        Expanded(child: _KpiChip(
          label: 'C.V.',
          value: hasData ? '${cv.toStringAsFixed(1)}%' : '—',
          benchmark: '≤ 8%',
          color: !hasData ? AppTheme.textSecondary
              : cv <= 8 ? AppTheme.green
              : cv <= 12 ? AppTheme.amber : AppTheme.red,
        )),
      ]),
      const SizedBox(height: 10),
      if (currentWh != null)
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _showWeightsSheet(currentWh),
            icon: Icon(filled > 0 ? Icons.edit_outlined : Icons.add, size: 16),
            label: Text(filled > 0 ? 'Edit Weights ($filled/100)' : 'Enter Weights',
                style: const TextStyle(fontSize: 13)),
            style: OutlinedButton.styleFrom(
              foregroundColor: filled > 0 ? AppTheme.green : AppTheme.primary,
              side: BorderSide(color: (filled > 0 ? AppTheme.green : AppTheme.primary).withValues(alpha: 0.5)),
              padding: const EdgeInsets.symmetric(vertical: 12),
            ),
          ),
        ),
    ]);
  }

  void _showWeightsSheet(_WeightHatch wh) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSS) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollCtrl) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Column(children: [
                  Center(child: Container(
                    width: 36, height: 4,
                    decoration: BoxDecoration(color: Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2)),
                  )),
                  const SizedBox(height: 14),
                  Row(children: [
                    const Text('Chick Weights (100)',
                        style: TextStyle(fontSize: 17, fontWeight: FontWeight.w700)),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.close),
                      onPressed: () => Navigator.pop(ctx),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ]),
                  const Divider(height: 20),
                ]),
              ),
              Expanded(
                child: ListView(
                  controller: scrollCtrl,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(child: _weightColumn(wh, 0, 50, onChanged: () => setSS(() {}))),
                        const SizedBox(width: 8),
                        Expanded(child: _weightColumn(wh, 50, 100, onChanged: () => setSS(() {}))),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, 8, 24, MediaQuery.of(ctx).viewInsets.bottom + 16),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => Navigator.pop(ctx),
                    child: const Text('Done'),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ).then((_) { if (mounted) setState(() {}); });
  }

  Widget _weightColumn(_WeightHatch wh, int start, int end, {VoidCallback? onChanged}) {
    return Column(
      children: List.generate(end - start, (i) {
        final idx = start + i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(children: [
            SizedBox(
              width: 28,
              child: Text('${idx + 1}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
            ),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                controller: wh.weightCtrls[idx],
                focusNode: wh.weightFocusNodes[idx],
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                textAlign: TextAlign.center,
                textInputAction: idx < _WeightHatch.count - 1 ? TextInputAction.next : TextInputAction.done,
                style: const TextStyle(fontSize: 12),
                decoration: const InputDecoration(
                  isDense: true,
                  contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                  hintText: '—', hintStyle: TextStyle(fontSize: 11),
                ),
                onChanged: (_) { setState(() {}); onChanged?.call(); },
                onSubmitted: (_) {
                  if (idx < _WeightHatch.count - 1) wh.weightFocusNodes[idx + 1].requestFocus();
                },
              ),
            ),
          ]),
        );
      }),
    );
  }

  // ── YFBM per-hatch ────────────────────────────────────────────────────────

  Widget _buildYfbmSection() {
    return _SectionCard(
      title: 'YFBM (Yolk-Free Body Mass)',
      icon: Icons.science_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHatchSelectorBar(
            count: _yfbmHatchRows.length,
            selected: _selectedYfbmHatch,
            onSelect: (i) => setState(() { _selectedYfbmHatch = i; }),
            onAdd: _addYfbmHatch,
            onRemove: _removeYfbmHatch,
          ),
          const SizedBox(height: 12),
          StatefulBuilder(builder: (ctx, setInner) {
            final hIdx = _selectedYfbmHatch.clamp(0, _yfbmHatchRows.length - 1);
            while (_yfbmHatchRows.length <= hIdx) { _yfbmHatchRows.add([]); }
            final rows = _yfbmHatchRows[hIdx];

            // Pooled AVG: sum(yolks)/sum(totals)*100
            double sumTotals = 0, sumYolks = 0;
            final pcts = <double>[];
            for (final row in rows) {
              final tot = double.tryParse(row['total']?.text ?? '') ?? 0;
              final yolk = double.tryParse(row['yolk']?.text ?? '') ?? 0;
              if (tot > 0) {
                sumTotals += tot;
                sumYolks += yolk;
                pcts.add(yolk / tot * 100);
              }
            }
            final pooledAvg = sumTotals > 0 ? sumYolks / sumTotals * 100 : null;
            // C.V. of individual %
            double? cvPct;
            if (pcts.length >= 2) {
              final avg = pcts.reduce((a, b) => a + b) / pcts.length;
              if (avg > 0) {
                final variance = pcts.map((v) => (v - avg) * (v - avg)).reduce((a, b) => a + b) / (pcts.length - 1);
                cvPct = math.sqrt(variance) / avg * 100;
              }
            }

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // KPI row
                if (pooledAvg != null || cvPct != null) ...[
                  Row(children: [
                    if (pooledAvg != null)
                      Expanded(child: _KpiChip(
                        label: 'Avg Yolk %',
                        value: '${pooledAvg.toStringAsFixed(1)}%',
                        color: AppTheme.primary,
                      )),
                    if (pooledAvg != null && cvPct != null) const SizedBox(width: 6),
                    if (cvPct != null)
                      Expanded(child: _KpiChip(
                        label: 'C.V.',
                        value: '${cvPct.toStringAsFixed(1)}%',
                        color: cvPct <= 10 ? AppTheme.green : cvPct <= 15 ? AppTheme.amber : AppTheme.red,
                      )),
                  ]),
                  const SizedBox(height: 10),
                ],
                if (rows.isEmpty)
                  const Text('No samples added yet.',
                      style: TextStyle(color: AppTheme.textSecondary, fontSize: 12)),
                ...rows.asMap().entries.map((entry) {
                  final i = entry.key;
                  final row = entry.value;
                  final tot = double.tryParse(row['total']?.text ?? '') ?? 0;
                  final yolk = double.tryParse(row['yolk']?.text ?? '') ?? 0;
                  final samplePct = tot > 0 ? yolk / tot * 100 : null;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Container(
                        width: 24, height: 24, alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppTheme.primary.withValues(alpha: 0.1),
                          shape: BoxShape.circle,
                        ),
                        child: Text('${i + 1}',
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold,
                              color: AppTheme.primary)),
                      ),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: row['total'],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Total (g)', isDense: true),
                        onChanged: (_) => setInner(() {}),
                      )),
                      const SizedBox(width: 8),
                      Expanded(child: TextField(
                        controller: row['yolk'],
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        decoration: const InputDecoration(labelText: 'Yolk (g)', isDense: true),
                        onChanged: (_) => setInner(() {}),
                      )),
                      const SizedBox(width: 8),
                      if (samplePct != null)
                        Text('${samplePct.toStringAsFixed(1)}%',
                          style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600,
                              color: AppTheme.primary)),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline, color: AppTheme.red, size: 18),
                        onPressed: () => setInner(() {
                          final r = rows.removeAt(i);
                          r['total']?.dispose(); r['yolk']?.dispose();
                        }),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                      ),
                    ]),
                  );
                }),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: () => setInner(() {
                    rows.add({
                      'total': TextEditingController(),
                      'yolk': TextEditingController(),
                    });
                  }),
                  icon: const Icon(Icons.add, size: 16),
                  label: const Text('Add Sample', style: TextStyle(fontSize: 13)),
                  style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8)),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── PASGAR + Wing Feathering per-hatch ────────────────────────────────────

  Widget _buildPasgarSection() {
    return _SectionCard(
      title: 'Pasgar Score & Wing Feathering',
      icon: Icons.checklist_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHatchSelectorBar(
            count: _pasgarHatches.length,
            selected: _selectedPasgarHatch,
            onSelect: (i) => setState(() { _selectedPasgarHatch = i; }),
            onAdd: _addPasgarHatch,
            onRemove: _removePasgarHatch,
          ),
          const SizedBox(height: 12),
          StatefulBuilder(builder: (ctx, setInner) {
            final hIdx = _selectedPasgarHatch.clamp(0, _pasgarHatches.length - 1);
            while (_pasgarHatches.length <= hIdx) { _pasgarHatches.add(_PasgarHatch()); }
            final ph = _pasgarHatches[hIdx];
            final sampleSize = int.tryParse(ph.sampleSizeCtrl.text) ?? 100;
            final total = ph.total;
            final max = sampleSize * 10;
            final score = max > 0 ? (max - total) / max * 10 : 0.0;
            final scoreColor = score >= 9 ? AppTheme.green : score >= 7 ? AppTheme.amber : AppTheme.red;

            // Defect items with % and acceptance
            final defects = [
              ('Reflexes', ph.reflexesCtrl),
              ('Beak', ph.beakCtrl),
              ('Navel', ph.navelCtrl),
              ('Belly', ph.bellyCtrl),
              ('Legs', ph.legsCtrl),
            ];

            // Wing feathering
            final feathered = int.tryParse(ph.featheredCtrl.text);
            final wingPct = (feathered != null && sampleSize > 0)
                ? feathered / sampleSize * 100 : null;
            final wingColor = wingPct == null ? AppTheme.textSecondary
                : wingPct >= 85 ? AppTheme.green : wingPct >= 70 ? AppTheme.amber : AppTheme.red;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [
                  const Text('Sample Size:',
                      style: TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  const SizedBox(width: 10),
                  SizedBox(
                    width: 80,
                    child: TextField(
                      controller: ph.sampleSizeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(isDense: true),
                      onChanged: (_) => setInner(() {}),
                    ),
                  ),
                  const Spacer(),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: scoreColor.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: scoreColor.withValues(alpha: 0.4)),
                    ),
                    child: Column(children: [
                      Text(score.toStringAsFixed(2),
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: scoreColor)),
                      Text('/ 10', style: TextStyle(fontSize: 10, color: scoreColor)),
                    ]),
                  ),
                ]),
                const SizedBox(height: 12),

                // Defect rows with % and acceptance
                ...defects.map((item) {
                  final count = int.tryParse(item.$2.text) ?? 0;
                  final pct = sampleSize > 0 ? count / sampleSize * 100 : 0.0;
                  final accepted = pct <= 20.0;
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(children: [
                      Expanded(flex: 3, child: Text(item.$1,
                          style: const TextStyle(fontSize: 14, color: AppTheme.textPrimary))),
                      Expanded(flex: 2, child: TextField(
                        controller: item.$2,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(isDense: true, hintText: '0'),
                        onChanged: (_) => setInner(() {}),
                      )),
                      const SizedBox(width: 8),
                      SizedBox(
                        width: 44,
                        child: Text('${pct.toStringAsFixed(1)}%',
                          textAlign: TextAlign.right,
                          style: TextStyle(fontSize: 12,
                            color: accepted ? AppTheme.textSecondary : AppTheme.red,
                            fontWeight: accepted ? FontWeight.normal : FontWeight.w600)),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: (accepted ? AppTheme.green : AppTheme.red).withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(accepted ? 'OK' : '!',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
                            color: accepted ? AppTheme.green : AppTheme.red)),
                      ),
                    ]),
                  );
                }),

                const Divider(height: 20),
                _SubSectionLabel(label: 'Wing Feathering'),
                Row(children: [
                  Expanded(child: TextField(
                    controller: ph.featheredCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Feathered Count', isDense: true),
                    onChanged: (_) => setInner(() {}),
                  )),
                  const SizedBox(width: 12),
                  Text('/ $sampleSize',
                      style: const TextStyle(fontSize: 13, color: AppTheme.textSecondary)),
                  if (wingPct != null) ...[
                    const SizedBox(width: 12),
                    _KpiChip(
                      label: 'Wing %',
                      value: '${wingPct.toStringAsFixed(1)}%',
                      benchmark: '≥ 85%',
                      color: wingColor,
                    ),
                  ],
                ]),
              ],
            );
          }),
        ],
      ),
    );
  }

  // ── Save bar ──────────────────────────────────────────────────────────────

  Widget _buildSaveBar() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 24),
      decoration: BoxDecoration(
        color: Colors.white,
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: SizedBox(
        width: double.infinity,
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _saveAll,
          icon: _isSaving
              ? const SizedBox(width: 18, height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Icon(Icons.check_circle_outline),
          label: const Text('Save Hatch Analysis'),
          style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 16)),
        ),
      ),
    );
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  /// Always-visible hatch selector bar: h1 h2 … circles + outlined + button.
  /// Red × badge appears on every circle when count > 1; last hatch is protected.
  Widget _buildHatchSelectorBar({
    required int count,
    required int selected,
    required ValueChanged<int> onSelect,
    required VoidCallback onAdd,
    required ValueChanged<int> onRemove,
  }) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          ...List.generate(count, (i) {
            final isSel = i == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => onSelect(i),
                    child: Container(
                      width: 36, height: 36,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: isSel ? AppTheme.primary : Colors.transparent,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: AppTheme.primary,
                          width: isSel ? 0 : 1.5,
                        ),
                      ),
                      child: Text('h${i + 1}',
                        style: TextStyle(
                          fontSize: 12, fontWeight: FontWeight.w600,
                          color: isSel ? Colors.white : AppTheme.primary,
                        )),
                    ),
                  ),
                  if (count > 1)
                    Positioned(
                      top: -4, right: -4,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          width: 16, height: 16,
                          alignment: Alignment.center,
                          decoration: const BoxDecoration(
                            color: Color(0xFFE53935),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.close, size: 10, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          // + button
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 36, height: 36,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(color: AppTheme.primary, width: 1.5),
              ),
              child: const Icon(Icons.add, size: 18, color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }


  Widget _inputField(
    TextEditingController ctrl,
    String label, {
    bool isNumber = false,
    bool isDecimal = false,
    ValueChanged<String>? onChanged,
  }) {
    return TextField(
      controller: ctrl,
      keyboardType: isDecimal
          ? const TextInputType.numberWithOptions(decimal: true)
          : isNumber ? TextInputType.number : TextInputType.text,
      decoration: InputDecoration(labelText: label, isDense: true),
      onChanged: onChanged,
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Reusable small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _SectionCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Widget child;

  const _SectionCard({
    required this.title,
    required this.icon,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade200),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 6, offset: const Offset(0, 2),
          )
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: AppTheme.primary.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
              border: Border(bottom: BorderSide(color: Colors.grey.shade100)),
            ),
            child: Row(children: [
              Icon(icon, size: 18, color: AppTheme.primary),
              const SizedBox(width: 8),
              Text(title, style: const TextStyle(
                fontSize: 14, fontWeight: FontWeight.w700, color: AppTheme.textPrimary)),
            ]),
          ),
          Padding(padding: const EdgeInsets.all(16), child: child),
        ],
      ),
    );
  }
}

class _SubSectionLabel extends StatelessWidget {
  final String label;
  const _SubSectionLabel({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Text(label.toUpperCase(),
        style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w700,
            letterSpacing: 0.8, color: AppTheme.textSecondary)),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        const SizedBox(height: 2),
        Text(value,
            style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
                color: AppTheme.textPrimary),
            overflow: TextOverflow.ellipsis),
      ]),
    );
  }
}

/// An editable chip that looks like _InfoChip but has a text field.
class _EditableInfoChip extends StatelessWidget {
  final String label;
  final TextEditingController controller;
  final ValueChanged<String>? onChanged;

  const _EditableInfoChip({
    required this.label,
    required this.controller,
    this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label, style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        const SizedBox(height: 2),
        TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary),
          decoration: const InputDecoration(
            isDense: true,
            contentPadding: EdgeInsets.zero,
            border: InputBorder.none,
            enabledBorder: InputBorder.none,
            focusedBorder: UnderlineInputBorder(),
          ),
          onChanged: onChanged,
        ),
      ]),
    );
  }
}

class _KpiChip extends StatelessWidget {
  final String label;
  final String value;
  final String? benchmark;
  final Color color;

  const _KpiChip({
    required this.label,
    required this.value,
    this.benchmark,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Column(children: [
        Text(value,
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary),
            textAlign: TextAlign.center),
        if (benchmark != null) ...[
          const SizedBox(height: 1),
          Text(benchmark!,
              style: TextStyle(fontSize: 9, color: color.withValues(alpha: 0.7)),
              textAlign: TextAlign.center),
        ],
      ]),
    );
  }
}

class _SevChip extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SevChip({required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color.withValues(alpha: 0.25)),
      ),
      child: Column(children: [
        Text('$count',
            style: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, color: color)),
        Text(label,
            style: TextStyle(fontSize: 10, color: color), textAlign: TextAlign.center),
      ]),
    );
  }
}

/// Shows the calculated benchmark age and breed.
class _BmkAgeChip extends StatelessWidget {
  final double ageWeeks;
  final String breed;
  const _BmkAgeChip({required this.ageWeeks, required this.breed});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: AppTheme.primary.withValues(alpha: 0.07),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: AppTheme.primary.withValues(alpha: 0.2)),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        const Icon(Icons.schedule, size: 12, color: AppTheme.primary),
        const SizedBox(width: 4),
        Text('Bmk Age: ${ageWeeks.toStringAsFixed(1)} wks',
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: AppTheme.primary)),
        if (breed.isNotEmpty && breed != '—') ...[
          const SizedBox(width: 6),
          Text('· $breed',
            style: const TextStyle(fontSize: 10, color: AppTheme.textSecondary)),
        ],
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Per-hatcher state holder (Sector B)
// ─────────────────────────────────────────────────────────────────────────────

class _HatcherData {
  final setterIdCtrl = TextEditingController();
  final hatcherIdCtrl = TextEditingController();
  final hatchedCtrl = TextEditingController();
  final culledCtrl = TextEditingController();
  final deadCtrl = TextEditingController();
  final infertileCtrl = TextEditingController();
  final fertilityCtrl = TextEditingController();

  _HatcherData();

  factory _HatcherData.fromEntry(HatcherEntry e) {
    final h = _HatcherData();
    h.setterIdCtrl.text = e.setterId;
    h.hatcherIdCtrl.text = e.hatcherId;
    h.hatchedCtrl.text = e.hatched?.toString() ?? '';
    h.culledCtrl.text = e.culled?.toString() ?? '';
    h.deadCtrl.text = e.dead?.toString() ?? '';
    h.infertileCtrl.text = e.infertileCount?.toString() ?? '';
    h.fertilityCtrl.text = e.fertilityPercent?.toString() ?? '';
    return h;
  }

  void dispose() {
    setterIdCtrl.dispose();
    hatcherIdCtrl.dispose();
    hatchedCtrl.dispose();
    culledCtrl.dispose();
    deadCtrl.dispose();
    infertileCtrl.dispose();
    fertilityCtrl.dispose();
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  Egg Breakout state holders (Sector C)
// ─────────────────────────────────────────────────────────────────────────────

class _BreakoutHatch {
  final incubatorIdCtrl = TextEditingController();
  final hatcherIdCtrl = TextEditingController();
  final sampleSizeCtrl = TextEditingController();
  final List<_TrayState> trays = [];
  int selectedTray = 0;

  void addTray() {
    final n = trays.length + 1;
    final t = _TrayState();
    t.trayIdCtrl.text = '$n';
    trays.add(t);
  }

  void dispose() {
    incubatorIdCtrl.dispose();
    hatcherIdCtrl.dispose();
    sampleSizeCtrl.dispose();
    for (final t in trays) { t.dispose(); }
  }
}

class _TrayState {
  final breakoutDateCtrl = TextEditingController(text: '21');
  final trayIdCtrl = TextEditingController();
  String position = 'Top';
  final Map<String, TextEditingController> ctrls;

  _TrayState()
      : ctrls = {
          for (final k in kEggBreakoutCategories) k: TextEditingController(text: '0'),
        };

  void dispose() {
    breakoutDateCtrl.dispose();
    trayIdCtrl.dispose();
    for (final c in ctrls.values) { c.dispose(); }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
//  PASGAR state holder per hatch (Sector D)
// ─────────────────────────────────────────────────────────────────────────────

// ─────────────────────────────────────────────────────────────────────────────
//  Weight state holder per hatch (100 chick weights)
// ─────────────────────────────────────────────────────────────────────────────

class _WeightHatch {
  static const int count = 100;
  final List<TextEditingController> weightCtrls =
      List.generate(count, (_) => TextEditingController());
  final List<FocusNode> weightFocusNodes =
      List.generate(count, (_) => FocusNode());

  void dispose() {
    for (final c in weightCtrls) { c.dispose(); }
    for (final f in weightFocusNodes) { f.dispose(); }
  }
}

class _PasgarHatch {
  final sampleSizeCtrl = TextEditingController(text: '100');
  final reflexesCtrl = TextEditingController(text: '0');
  final beakCtrl = TextEditingController(text: '0');
  final navelCtrl = TextEditingController(text: '0');
  final bellyCtrl = TextEditingController(text: '0');
  final legsCtrl = TextEditingController(text: '0');
  final featheredCtrl = TextEditingController();

  int get total =>
      (int.tryParse(reflexesCtrl.text) ?? 0) +
      (int.tryParse(beakCtrl.text) ?? 0) +
      (int.tryParse(navelCtrl.text) ?? 0) +
      (int.tryParse(bellyCtrl.text) ?? 0) +
      (int.tryParse(legsCtrl.text) ?? 0);

  void dispose() {
    sampleSizeCtrl.dispose();
    reflexesCtrl.dispose();
    beakCtrl.dispose();
    navelCtrl.dispose();
    bellyCtrl.dispose();
    legsCtrl.dispose();
    featheredCtrl.dispose();
  }
}
