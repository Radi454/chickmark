import 'dart:convert';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/chick_quality.dart';
import '../../utils/app_theme.dart';
import '../../widgets/section_card.dart';
import '../../widgets/ble_sensor_widget.dart';

class ChickQualityScreen extends StatefulWidget {
  const ChickQualityScreen({super.key});

  @override
  State<ChickQualityScreen> createState() => _ChickQualityScreenState();
}

class _ChickQualityScreenState extends State<ChickQualityScreen> {
  // ── Top section ────────────────────────────────────────────────────────────
  final _eggStorageDaysCtrl = TextEditingController();

  // ── Section A ──────────────────────────────────────────────────────────────
  double? _temperature;
  double? _humidity;

  // ── Section B — per-hatch weights ─────────────────────────────────────────
  static const int _kWeightCount = 100;
  int _weightSelectedHatch = 0;
  late List<List<TextEditingController>> _weightHatches;
  late List<List<FocusNode>> _weightFocusHatches;

  // ── Section C — per-hatch YFBM ────────────────────────────────────────────
  int _yfbmSelectedHatch = 0;
  List<List<Map<String, TextEditingController>>> _yfbmHatches = [[]];

  // ── Sections D + E — per-hatch Pasgar & Wing ──────────────────────────────
  int _pasgarSelectedHatch = 0;
  late List<Map<String, TextEditingController>> _pasgarHatches;

  bool _isSaving = false;

  // ── Computed helpers ───────────────────────────────────────────────────────

  double get _currentFlockAgeWeeks {
    final provider = context.read<AppProvider>();
    return provider.currentFlock?.currentAgeWeeks ?? 0.0;
  }

  String get _flockId {
    final provider = context.read<AppProvider>();
    return provider.currentFlock?.flockCode ?? '';
  }

  List<TextEditingController> get _currentWeightCtrls =>
      _weightHatches.isNotEmpty ? _weightHatches[_weightSelectedHatch] : [];

  List<FocusNode> get _currentWeightFocusNodes =>
      _weightFocusHatches.isNotEmpty
          ? _weightFocusHatches[_weightSelectedHatch]
          : [];

  List<double> get _enteredWeights => _currentWeightCtrls
      .map((c) => double.tryParse(c.text) ?? 0.0)
      .where((v) => v > 0)
      .toList();

  double get _avgWeight {
    final ws = _enteredWeights;
    if (ws.isEmpty) return 0;
    return ws.reduce((a, b) => a + b) / ws.length;
  }

  double get _uniformityPercent {
    final avg = _avgWeight;
    if (avg == 0) return 0;
    final ws = _enteredWeights;
    final lower = avg * 0.9;
    final upper = avg * 1.1;
    return ws.where((w) => w >= lower && w <= upper).length / ws.length * 100;
  }

  double get _cvPercent {
    final avg = _avgWeight;
    if (avg == 0) return 0;
    final ws = _enteredWeights;
    if (ws.length < 2) return 0;
    final variance =
        ws.map((w) => (w - avg) * (w - avg)).reduce((a, b) => a + b) /
            ws.length;
    return math.sqrt(variance) / avg * 100;
  }

  // ── Factories ──────────────────────────────────────────────────────────────

  Map<String, TextEditingController> _newPasgarHatch() => {
        'sample': TextEditingController(text: '100'),
        'reflexes': TextEditingController(text: '0'),
        'beak': TextEditingController(text: '0'),
        'navel': TextEditingController(text: '0'),
        'belly': TextEditingController(text: '0'),
        'legs': TextEditingController(text: '0'),
        'feathered': TextEditingController(),
        'wingSample': TextEditingController(),
      };

  // ── Lifecycle ──────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _weightHatches = [
      List.generate(_kWeightCount, (_) => TextEditingController())
    ];
    _weightFocusHatches = [
      List.generate(_kWeightCount, (_) => FocusNode())
    ];
    _pasgarHatches = [_newPasgarHatch()];
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  void _loadExisting() {
    final provider = context.read<AppProvider>();
    final cq = provider.chickQuality;
    if (cq == null) return;

    setState(() {
      _eggStorageDaysCtrl.text = cq.eggStorageDays?.toString() ?? '';
      _temperature = cq.temperature;
      _humidity = cq.humidity;

      // ── Section B — Weights ──────────────────────────────────────────────
      if (cq.weightsHatchJson != null && cq.weightsHatchJson!.isNotEmpty) {
        final hatchList = jsonDecode(cq.weightsHatchJson!) as List;
        _disposeWeightHatches();
        _weightHatches = hatchList.map<List<TextEditingController>>((h) {
          final raw = h as List;
          final ctrls =
              List.generate(_kWeightCount, (_) => TextEditingController());
          for (int i = 0; i < raw.length && i < _kWeightCount; i++) {
            final v = (raw[i] as num).toDouble();
            if (v > 0) ctrls[i].text = v.toStringAsFixed(1);
          }
          return ctrls;
        }).toList();
        _weightFocusHatches = List.generate(
          _weightHatches.length,
          (_) => List.generate(_kWeightCount, (_) => FocusNode()),
        );
      } else {
        for (int i = 0; i < cq.weights.length && i < _kWeightCount; i++) {
          _weightHatches[0][i].text = cq.weights[i].toStringAsFixed(1);
        }
      }

      // ── Section C — YFBM ────────────────────────────────────────────────
      _disposeYfbmHatches();
      if (cq.yfbmHatchDataJson != null && cq.yfbmHatchDataJson!.isNotEmpty) {
        final hatchList = jsonDecode(cq.yfbmHatchDataJson!) as List;
        _yfbmHatches =
            hatchList.map<List<Map<String, TextEditingController>>>((h) {
          final samples = (h['samples'] as List);
          return samples.map<Map<String, TextEditingController>>((s) => {
                'total': TextEditingController(
                    text: (s['total_weight'] as num).toStringAsFixed(2)),
                'yolk': TextEditingController(
                    text: (s['yolk_weight'] as num).toStringAsFixed(2)),
              }).toList();
        }).toList();
      } else {
        _yfbmHatches = [[]];
        for (final pair in cq.yfbmPairs) {
          _yfbmHatches[0].add({
            'total': TextEditingController(
                text: pair['total_weight']?.toStringAsFixed(2) ?? ''),
            'yolk': TextEditingController(
                text: pair['yolk_weight']?.toStringAsFixed(2) ?? ''),
          });
        }
      }
      if (_yfbmHatches.isEmpty) _yfbmHatches = [[]];

      // ── Sections D + E — Pasgar ─────────────────────────────────────────
      _disposePasgarHatches();
      if (cq.pasgarHatchDataJson != null &&
          cq.pasgarHatchDataJson!.isNotEmpty) {
        final hatchList = jsonDecode(cq.pasgarHatchDataJson!) as List;
        _pasgarHatches = hatchList.map<Map<String, TextEditingController>>((h) => {
              'sample': TextEditingController(
                  text: (h['sampleSize'] ?? 100).toString()),
              'reflexes': TextEditingController(
                  text: (h['reflexes'] ?? 0).toString()),
              'beak':
                  TextEditingController(text: (h['beak'] ?? 0).toString()),
              'navel':
                  TextEditingController(text: (h['navel'] ?? 0).toString()),
              'belly':
                  TextEditingController(text: (h['belly'] ?? 0).toString()),
              'legs':
                  TextEditingController(text: (h['legs'] ?? 0).toString()),
              'feathered': TextEditingController(
                  text: h['featheredCount']?.toString() ?? ''),
              'wingSample': TextEditingController(
                  text: h['wingSampleSize']?.toString() ?? ''),
            }).toList();
      } else {
        _pasgarHatches = [_newPasgarHatch()];
        _pasgarHatches[0]['sample']!.text = cq.pasgarSampleSize.toString();
        _pasgarHatches[0]['reflexes']!.text = cq.reflexesDefects.toString();
        _pasgarHatches[0]['beak']!.text = cq.beakDefects.toString();
        _pasgarHatches[0]['navel']!.text = cq.navelDefects.toString();
        _pasgarHatches[0]['belly']!.text = cq.bellyDefects.toString();
        _pasgarHatches[0]['legs']!.text = cq.legsDefects.toString();
        _pasgarHatches[0]['feathered']!.text =
            cq.featheredCount?.toString() ?? '';
      }
      if (_pasgarHatches.isEmpty) _pasgarHatches = [_newPasgarHatch()];

      // Clamp selected indices
      _weightSelectedHatch = 0;
      _yfbmSelectedHatch = 0;
      _pasgarSelectedHatch = 0;
    });
  }

  void _disposeWeightHatches() {
    for (final hatch in _weightHatches) {
      for (final c in hatch) { c.dispose(); }
    }
    for (final hatch in _weightFocusHatches) {
      for (final f in hatch) { f.dispose(); }
    }
  }

  void _disposeYfbmHatches() {
    for (final hatch in _yfbmHatches) {
      for (final row in hatch) {
        row['total']?.dispose();
        row['yolk']?.dispose();
      }
    }
  }

  void _disposePasgarHatches() {
    for (final hatch in _pasgarHatches) {
      for (final c in hatch.values) { c.dispose(); }
    }
  }

  @override
  void dispose() {
    _eggStorageDaysCtrl.dispose();
    _disposeWeightHatches();
    _disposeYfbmHatches();
    _disposePasgarHatches();
    super.dispose();
  }

  // ── Hatch management ───────────────────────────────────────────────────────

  void _addWeightHatch() {
    setState(() {
      _weightHatches
          .add(List.generate(_kWeightCount, (_) => TextEditingController()));
      _weightFocusHatches
          .add(List.generate(_kWeightCount, (_) => FocusNode()));
      _weightSelectedHatch = _weightHatches.length - 1;
    });
  }

  void _removeWeightHatch(int index) {
    if (_weightHatches.length <= 1) return;
    setState(() {
      for (final c in _weightHatches[index]) { c.dispose(); }
      for (final f in _weightFocusHatches[index]) { f.dispose(); }
      _weightHatches.removeAt(index);
      _weightFocusHatches.removeAt(index);
      if (_weightSelectedHatch >= _weightHatches.length) {
        _weightSelectedHatch = _weightHatches.length - 1;
      }
    });
  }

  void _addYfbmHatch() {
    setState(() {
      _yfbmHatches.add([]);
      _yfbmSelectedHatch = _yfbmHatches.length - 1;
    });
  }

  void _removeYfbmHatch(int index) {
    if (_yfbmHatches.length <= 1) return;
    setState(() {
      for (final row in _yfbmHatches[index]) {
        row['total']?.dispose();
        row['yolk']?.dispose();
      }
      _yfbmHatches.removeAt(index);
      if (_yfbmSelectedHatch >= _yfbmHatches.length) {
        _yfbmSelectedHatch = _yfbmHatches.length - 1;
      }
    });
  }

  void _addPasgarHatch() {
    setState(() {
      _pasgarHatches.add(_newPasgarHatch());
      _pasgarSelectedHatch = _pasgarHatches.length - 1;
    });
  }

  void _removePasgarHatch(int index) {
    if (_pasgarHatches.length <= 1) return;
    setState(() {
      for (final c in _pasgarHatches[index].values) { c.dispose(); }
      _pasgarHatches.removeAt(index);
      if (_pasgarSelectedHatch >= _pasgarHatches.length) {
        _pasgarSelectedHatch = _pasgarHatches.length - 1;
      }
    });
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final provider = context.read<AppProvider>();
    final session = provider.currentSession;
    if (session == null) return;

    setState(() => _isSaving = true);
    try {
      // Build per-hatch weights data
      final weightsHatchData = _weightHatches
          .map((hatch) =>
              hatch.map((c) => double.tryParse(c.text) ?? 0.0).toList())
          .toList();

      // Build per-hatch YFBM data
      final yfbmHatchData = _yfbmHatches.asMap().entries.map((e) => {
            'hatchIdx': e.key,
            'samples': e.value
                .map((row) => {
                      'total_weight':
                          double.tryParse(row['total']?.text ?? '') ?? 0.0,
                      'yolk_weight':
                          double.tryParse(row['yolk']?.text ?? '') ?? 0.0,
                    })
                .toList(),
          }).toList();

      // Build per-hatch Pasgar data
      final pasgarHatchData = _pasgarHatches.asMap().entries.map((e) => {
            'hatchIdx': e.key,
            'sampleSize':
                int.tryParse(e.value['sample']?.text ?? '') ?? 100,
            'reflexes':
                int.tryParse(e.value['reflexes']?.text ?? '') ?? 0,
            'beak': int.tryParse(e.value['beak']?.text ?? '') ?? 0,
            'navel': int.tryParse(e.value['navel']?.text ?? '') ?? 0,
            'belly': int.tryParse(e.value['belly']?.text ?? '') ?? 0,
            'legs': int.tryParse(e.value['legs']?.text ?? '') ?? 0,
            'featheredCount':
                int.tryParse(e.value['feathered']?.text ?? ''),
            'wingSampleSize':
                int.tryParse(e.value['wingSample']?.text ?? ''),
          }).toList();

      // Hatch 0 for backward-compatible single-value fields
      final h0 = _pasgarHatches[0];
      final weights0 =
          weightsHatchData[0].where((v) => v > 0).toList();

      final existing = provider.chickQuality;
      final cq = ChickQuality(
        id: existing?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: session.customerId,
        flockId: session.flockId,
        eggStorageDays: int.tryParse(_eggStorageDaysCtrl.text),
        temperature: _temperature,
        humidity: _humidity,
        sampleSize: _kWeightCount,
        weights: weights0,
        weightsHatchJson: jsonEncode(weightsHatchData),
        yfbmDataJson: jsonEncode(
            yfbmHatchData.isNotEmpty ? yfbmHatchData[0]['samples'] : []),
        yfbmHatchDataJson: jsonEncode(yfbmHatchData),
        pasgarSampleSize:
            int.tryParse(h0['sample']?.text ?? '') ?? 0,
        reflexesDefects:
            int.tryParse(h0['reflexes']?.text ?? '') ?? 0,
        beakDefects: int.tryParse(h0['beak']?.text ?? '') ?? 0,
        navelDefects: int.tryParse(h0['navel']?.text ?? '') ?? 0,
        bellyDefects: int.tryParse(h0['belly']?.text ?? '') ?? 0,
        legsDefects: int.tryParse(h0['legs']?.text ?? '') ?? 0,
        pasgarHatchDataJson: jsonEncode(pasgarHatchData),
        featheredCount: int.tryParse(h0['feathered']?.text ?? ''),
        isCompleted: true,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );

      await provider.saveChickQuality(cq);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Chick Quality saved and marked complete!'),
            backgroundColor: AppTheme.green,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Hatch Selector Widget ──────────────────────────────────────────────────

  Widget _hatchSelector({
    required int count,
    required int selected,
    required void Function(int) onSelect,
    required VoidCallback onAdd,
    required void Function(int) onRemove,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        children: [
          ...List.generate(count, (i) {
            final isSelected = i == selected;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  GestureDetector(
                    onTap: () => onSelect(i),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 180),
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: isSelected
                            ? AppTheme.primary
                            : AppTheme.background,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: isSelected
                              ? AppTheme.primary
                              : AppTheme.primary.withValues(alpha: 0.35),
                          width: 1.5,
                        ),
                      ),
                      child: Center(
                        child: Text(
                          'h${i + 1}',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: isSelected
                                ? Colors.white
                                : AppTheme.primary,
                          ),
                        ),
                      ),
                    ),
                  ),
                  if (count > 1)
                    Positioned(
                      top: -5,
                      right: -5,
                      child: GestureDetector(
                        onTap: () => onRemove(i),
                        child: Container(
                          width: 17,
                          height: 17,
                          decoration: BoxDecoration(
                            color: AppTheme.red,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: Colors.white, width: 1.5),
                          ),
                          child: const Icon(Icons.close,
                              size: 9, color: Colors.white),
                        ),
                      ),
                    ),
                ],
              ),
            );
          }),
          GestureDetector(
            onTap: onAdd,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: Colors.transparent,
                shape: BoxShape.circle,
                border: Border.all(
                  color: AppTheme.primary.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child:
                  const Icon(Icons.add, size: 18, color: AppTheme.primary),
            ),
          ),
        ],
      ),
    );
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final flockAgeWeeks = _currentFlockAgeWeeks;

    return Scaffold(
      appBar: AppBar(title: const Text('Chick Quality')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          children: [
            // ── Top section ────────────────────────────────────────────────
            SectionCard(
              title: 'Session Info',
              icon: Icons.info_outline,
              child: Column(
                children: [
                  _readOnlyField('Flock ID', _flockId),
                  _readOnlyField(
                    'Current Flock Age (Weeks)',
                    flockAgeWeeks.toStringAsFixed(1),
                  ),
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: TextField(
                      controller: _eggStorageDaysCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                          labelText: 'Egg Storage Days'),
                    ),
                  ),
                ],
              ),
            ),
            _buildSectionA(),
            _buildSectionB(),
            _buildSectionC(),
            _buildSectionD(),
            const SizedBox(height: 16),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _isSaving ? null : _save,
                  icon: _isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : const Icon(Icons.check_circle_outline),
                  label: const Text('Submit / Save'),
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          filled: true,
          fillColor: AppTheme.background,
        ),
        child: Text(
          value,
          style: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: AppTheme.textPrimary),
        ),
      ),
    );
  }

  // ── Section A ──────────────────────────────────────────────────────────────

  Widget _buildSectionA() {
    return SectionCard(
      title: 'A — Environmental Conditions',
      icon: Icons.air,
      child: BleSensorWidget(
        temperature: _temperature,
        humidity: _humidity,
        onReading: (t, h) => setState(() {
          _temperature = t;
          _humidity = h;
        }),
      ),
    );
  }

  // ── Section B ──────────────────────────────────────────────────────────────

  Widget _buildSectionB() {
    final avg = _avgWeight;
    final uni = _uniformityPercent;
    final cv = _cvPercent;
    final hasData = avg > 0;
    final filled =
        _currentWeightCtrls.where((c) => c.text.trim().isNotEmpty).length;

    return SectionCard(
      title: 'B — Weight Uniformity (100 chicks)',
      icon: Icons.monitor_weight_outlined,
      child: Column(
        children: [
          _hatchSelector(
            count: _weightHatches.length,
            selected: _weightSelectedHatch,
            onSelect: (i) => setState(() => _weightSelectedHatch = i),
            onAdd: _addWeightHatch,
            onRemove: _removeWeightHatch,
          ),
          Row(
            children: [
              _resultChip(
                label: 'Avg Weight',
                value: hasData ? '${avg.toStringAsFixed(1)} g' : '—',
                color: hasData ? AppTheme.primary : Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              _resultChip(
                label: 'Uniformity',
                value: hasData ? '${uni.toStringAsFixed(1)}%' : '—',
                color: hasData
                    ? (uni >= 85
                        ? AppTheme.green
                        : uni >= 75
                            ? AppTheme.amber
                            : AppTheme.red)
                    : Colors.grey.shade400,
              ),
              const SizedBox(width: 8),
              _resultChip(
                label: 'C.V.',
                value: hasData ? '${cv.toStringAsFixed(1)}%' : '—',
                color: hasData
                    ? (cv <= 8
                        ? AppTheme.green
                        : cv <= 12
                            ? AppTheme.amber
                            : AppTheme.red)
                    : Colors.grey.shade400,
              ),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: _showWeightsSheet,
              icon: Icon(
                filled > 0 ? Icons.edit_outlined : Icons.add,
                size: 18,
              ),
              label: Text(
                filled > 0
                    ? 'Edit Weights ($filled/100 entered)'
                    : 'Add Weights',
              ),
              style: OutlinedButton.styleFrom(
                foregroundColor:
                    filled > 0 ? AppTheme.green : AppTheme.primary,
                side: BorderSide(
                  color: filled > 0
                      ? AppTheme.green.withValues(alpha: 0.6)
                      : AppTheme.primary.withValues(alpha: 0.4),
                ),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showWeightsSheet() {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.85,
          minChildSize: 0.5,
          maxChildSize: 0.95,
          builder: (ctx, scrollController) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 0),
                child: Column(
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        decoration: BoxDecoration(
                          color: Colors.grey.shade300,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color:
                                AppTheme.primary.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: const Icon(
                              Icons.monitor_weight_outlined,
                              color: AppTheme.primary,
                              size: 20),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          'Chick Weights — h${_weightSelectedHatch + 1}',
                          style: const TextStyle(
                              fontSize: 17,
                              fontWeight: FontWeight.w700),
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => Navigator.pop(ctx),
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                  ],
                ),
              ),
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                            child: _weightColumn(0, 50,
                                onChanged: () =>
                                    setSheetState(() {}))),
                        const SizedBox(width: 8),
                        Expanded(
                            child: _weightColumn(50, 100,
                                onChanged: () =>
                                    setSheetState(() {}))),
                      ],
                    ),
                  ],
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(
                    24,
                    8,
                    24,
                    MediaQuery.of(ctx).viewInsets.bottom + 16),
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
    ).then((_) {
      if (mounted) setState(() {});
    });
  }

  Widget _resultChip({
    required String label,
    required String value,
    required Color color,
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: color),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: const TextStyle(
                  fontSize: 10, color: AppTheme.textSecondary),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _weightColumn(int start, int end, {VoidCallback? onChanged}) {
    final ctrls = _currentWeightCtrls;
    final focusNodes = _currentWeightFocusNodes;
    return Column(
      children: List.generate(end - start, (i) {
        final idx = start + i;
        return Padding(
          padding: const EdgeInsets.only(bottom: 4),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: Text(
                  '${idx + 1}',
                  textAlign: TextAlign.right,
                  style: const TextStyle(
                      fontSize: 10, color: AppTheme.textSecondary),
                ),
              ),
              const SizedBox(width: 4),
              Expanded(
                child: TextField(
                  controller: ctrls[idx],
                  focusNode: focusNodes[idx],
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  textAlign: TextAlign.center,
                  textInputAction: idx < _kWeightCount - 1
                      ? TextInputAction.next
                      : TextInputAction.done,
                  style: const TextStyle(fontSize: 12),
                  decoration: const InputDecoration(
                    isDense: true,
                    contentPadding:
                        EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                    hintText: '—',
                    hintStyle: TextStyle(fontSize: 11),
                  ),
                  onChanged: (_) {
                    setState(() {});
                    onChanged?.call();
                  },
                  onSubmitted: (_) {
                    if (idx < _kWeightCount - 1) {
                      focusNodes[idx + 1].requestFocus();
                    }
                  },
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  // ── Section C ──────────────────────────────────────────────────────────────

  Widget _buildSectionC() {
    final currentRows = _yfbmHatches[_yfbmSelectedHatch];
    return SectionCard(
      title: 'C — YFBM (Yolk-Free Body Mass)',
      icon: Icons.science_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hatchSelector(
            count: _yfbmHatches.length,
            selected: _yfbmSelectedHatch,
            onSelect: (i) => setState(() => _yfbmSelectedHatch = i),
            onAdd: _addYfbmHatch,
            onRemove: _removeYfbmHatch,
          ),
          if (currentRows.isEmpty)
            const Text(
              'No samples added yet. Tap "Add Sample" below.',
              style:
                  TextStyle(color: AppTheme.textSecondary, fontSize: 13),
            ),
          ...currentRows.asMap().entries.map((entry) {
            final i = entry.key;
            final row = entry.value;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppTheme.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Text('${i + 1}',
                        style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: AppTheme.primary)),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row['total'],
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Total Weight (g)',
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: row['yolk'],
                      keyboardType: const TextInputType.numberWithOptions(
                          decimal: true),
                      decoration: const InputDecoration(
                        labelText: 'Yolk Weight (g)',
                        isDense: true,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline,
                        color: AppTheme.red, size: 20),
                    onPressed: () {
                      setState(() {
                        final removed = currentRows.removeAt(i);
                        removed['total']?.dispose();
                        removed['yolk']?.dispose();
                      });
                    },
                  ),
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            onPressed: () {
              setState(() {
                _yfbmHatches[_yfbmSelectedHatch].add({
                  'total': TextEditingController(),
                  'yolk': TextEditingController(),
                });
              });
            },
            icon: const Icon(Icons.add, size: 18),
            label: const Text('Add Sample'),
          ),
        ],
      ),
    );
  }

  // ── Section D — Pasgar Score & Wing Feathering (combined) ──────────────────

  Widget _buildSectionD() {
    final h = _pasgarHatches[_pasgarSelectedHatch];
    return SectionCard(
      title: 'D — Pasgar Score & Wing Feathering',
      icon: Icons.fact_check_outlined,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _hatchSelector(
            count: _pasgarHatches.length,
            selected: _pasgarSelectedHatch,
            onSelect: (i) => setState(() => _pasgarSelectedHatch = i),
            onAdd: _addPasgarHatch,
            onRemove: _removePasgarHatch,
          ),
          SectionCard(
            title: 'Scoring Instructions',
            isCollapsible: true,
            child: const Text(
              'Examine each chick for 5 defect types. '
              'Record the count of chicks showing each defect.\n\n'
              '• Reflexes: lack of righting reflex or leg tone\n'
              '• Beak: deformities, crossed beak\n'
              '• Navel: unhealed or infected navel\n'
              '• Belly: distended or bruised abdomen\n'
              '• Legs: splayed legs, hock problems',
              style: TextStyle(
                  fontSize: 13, color: AppTheme.textSecondary, height: 1.5),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              const Text('Sample Size:',
                  style: TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(width: 12),
              SizedBox(
                width: 100,
                child: TextField(
                  controller: h['sample'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(isDense: true),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          _defectRow('Reflexes', h['reflexes']!),
          _defectRow('Beak', h['beak']!),
          _defectRow('Navel', h['navel']!),
          _defectRow('Belly', h['belly']!),
          _defectRow('Legs', h['legs']!),
          const Divider(height: 28),
          const Text(
            'Wing Feathering',
            style:
                TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 6),
          const Text(
            'Count the number of chicks with adequate wing feathering.',
            style: TextStyle(
                fontSize: 13, color: AppTheme.textSecondary, height: 1.4),
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: h['feathered'],
                  keyboardType: TextInputType.number,
                  decoration:
                      const InputDecoration(labelText: 'Feathered Count'),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: TextField(
                  controller: h['wingSample'],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                      labelText: 'Total Sample Size'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _defectRow(String label, TextEditingController ctrl) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary)),
          ),
          Expanded(
            flex: 2,
            child: TextField(
              controller: ctrl,
              keyboardType: TextInputType.number,
              textAlign: TextAlign.center,
              decoration:
                  const InputDecoration(isDense: true, hintText: '0'),
            ),
          ),
        ],
      ),
    );
  }
}
