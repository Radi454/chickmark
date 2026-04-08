import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/egg_breakout.dart';
import '../../utils/app_theme.dart';
import '../../widgets/section_card.dart';

class EggBreakoutScreen extends StatefulWidget {
  const EggBreakoutScreen({super.key});

  @override
  State<EggBreakoutScreen> createState() => _EggBreakoutScreenState();
}

class _EggBreakoutScreenState extends State<EggBreakoutScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // ── Fixed top-section controllers ──────────────────────────────────────────
  final _eggStorageDaysCtrl = TextEditingController();
  final _eggBreakoutAgeCtrl = TextEditingController();
  final _incubatorIdCtrl = TextEditingController();
  final _hatcherIdCtrl = TextEditingController();
  final _sampleSizeCtrl = TextEditingController();

  // ── Tray data ──────────────────────────────────────────────────────────────
  // Each element: {trayId, trayPosition, infertile, earlyDead24h, ...}
  final List<Map<String, dynamic>> _trays = [];
  // Per-tray per-category controllers
  final List<Map<String, TextEditingController>> _trayCtrls = [];
  final List<TextEditingController> _trayIdCtrls = [];
  final List<String> _trayPositions = [];

  bool _isSaving = false;

  // ── Helpers ────────────────────────────────────────────────────────────────

  double get _currentFlockAgeWeeks {
    final provider = context.read<AppProvider>();
    return provider.currentFlock?.currentAgeWeeks ?? 0.0;
  }

  double? get _eggProductionAgeDays {
    final age = _currentFlockAgeWeeks;
    final breakoutAge = int.tryParse(_eggBreakoutAgeCtrl.text);
    final storageDays = int.tryParse(_eggStorageDaysCtrl.text);
    if (breakoutAge == null || storageDays == null) return null;
    return (age * 7) - breakoutAge - storageDays;
  }

  String get _flockId {
    final provider = context.read<AppProvider>();
    return provider.currentFlock?.flockCode ?? '';
  }

  @override
  void initState() {
    super.initState();
    _rebuildTabController();
    _addTray();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  void _rebuildTabController() {
    if (_trays.isEmpty) {
      _tabController = TabController(length: 1, vsync: this);
      return;
    }
    _tabController = TabController(length: _trays.length, vsync: this);
  }

  void _addTray() {
    final trayNum = _trays.length + 1;
    final emptyData = <String, dynamic>{
      'trayId': '$trayNum',
      'trayPosition': 'Top',
      for (final k in kEggBreakoutCategories) k: 0,
    };
    final ctrls = <String, TextEditingController>{
      for (final k in kEggBreakoutCategories)
        k: TextEditingController(text: '0'),
    };
    setState(() {
      _trays.add(emptyData);
      _trayCtrls.add(ctrls);
      _trayIdCtrls.add(TextEditingController(text: '$trayNum'));
      _trayPositions.add('Top');
      _tabController.dispose();
      _rebuildTabController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_tabController.length > 0) {
          _tabController.animateTo(_trays.length - 1);
        }
      });
    });
  }

  void _loadExisting() {
    final provider = context.read<AppProvider>();
    final eb = provider.eggBreakout;
    if (eb == null) return;

    setState(() {
      _eggStorageDaysCtrl.text = eb.eggStorageDays?.toString() ?? '';
      _eggBreakoutAgeCtrl.text = eb.eggBreakoutAgeDays?.toString() ?? '';
      _incubatorIdCtrl.text = eb.incubatorId ?? '';
      _hatcherIdCtrl.text = eb.hatcherId ?? '';
      _sampleSizeCtrl.text = eb.sampleSize?.toString() ?? '';

      final loaded = eb.trayData;
      if (loaded.isNotEmpty) {
        for (final m in _trayCtrls) {
          for (final c in m.values) {
            c.dispose();
          }
        }
        for (final c in _trayIdCtrls) {
          c.dispose();
        }
        _trays.clear();
        _trayCtrls.clear();
        _trayIdCtrls.clear();
        _trayPositions.clear();

        for (final tray in loaded) {
          final data = Map<String, dynamic>.from(tray);
          final ctrls = <String, TextEditingController>{
            for (final k in kEggBreakoutCategories)
              k: TextEditingController(text: (tray[k] ?? 0).toString()),
          };
          _trays.add(data);
          _trayCtrls.add(ctrls);
          _trayIdCtrls.add(
            TextEditingController(text: tray['trayId']?.toString() ?? ''),
          );
          _trayPositions.add(tray['trayPosition'] as String? ?? 'Top');
        }
        _tabController.dispose();
        _rebuildTabController();
      }
    });
  }

  @override
  void dispose() {
    _tabController.dispose();
    _eggStorageDaysCtrl.dispose();
    _eggBreakoutAgeCtrl.dispose();
    _incubatorIdCtrl.dispose();
    _hatcherIdCtrl.dispose();
    _sampleSizeCtrl.dispose();
    for (final m in _trayCtrls) {
      for (final c in m.values) {
        c.dispose();
      }
    }
    for (final c in _trayIdCtrls) {
      c.dispose();
    }
    super.dispose();
  }

  // ── Save ───────────────────────────────────────────────────────────────────

  Future<void> _save() async {
    final provider = context.read<AppProvider>();
    final session = provider.currentSession;
    if (session == null) return;

    setState(() => _isSaving = true);
    try {
      // Merge tray positions & IDs into tray data
      final trayDataToSave = List<Map<String, dynamic>>.generate(
        _trays.length,
        (i) {
          final map = Map<String, dynamic>.from(_trays[i]);
          map['trayId'] = _trayIdCtrls[i].text;
          map['trayPosition'] = _trayPositions[i];
          for (final k in kEggBreakoutCategories) {
            map[k] = int.tryParse(_trayCtrls[i][k]?.text ?? '0') ?? 0;
          }
          return map;
        },
      );

      final existing = provider.eggBreakout;
      final eb = EggBreakout(
        id: existing?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: session.customerId,
        flockId: session.flockId,
        eggStorageDays: int.tryParse(_eggStorageDaysCtrl.text),
        eggBreakoutAgeDays: int.tryParse(_eggBreakoutAgeCtrl.text),
        incubatorId: _incubatorIdCtrl.text.isEmpty
            ? null
            : _incubatorIdCtrl.text,
        hatcherId: _hatcherIdCtrl.text.isEmpty ? null : _hatcherIdCtrl.text,
        sampleSize: int.tryParse(_sampleSizeCtrl.text),
        trayDataJson: jsonEncode(trayDataToSave),
        isCompleted: true,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );

      await provider.saveEggBreakout(eb);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Egg Breakout saved and marked complete!'),
            backgroundColor: AppTheme.green,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final flockAgeWeeks = _currentFlockAgeWeeks;
    final eggProdAge = _eggProductionAgeDays;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Egg Breakout Analysis'),
        actions: [
          TextButton.icon(
            onPressed: _addTray,
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text(
              'Add Tray',
              style: TextStyle(color: Colors.white, fontSize: 13),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                // ── Fixed top section ────────────────────────────────────────
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
                      _numField(_eggStorageDaysCtrl, 'Egg Storage Days'),
                      _numField(
                        _eggBreakoutAgeCtrl,
                        'Egg Breakout Age (Days of Incubation)',
                      ),
                      _readOnlyField(
                        'Egg Production Age (Days)',
                        eggProdAge != null
                            ? eggProdAge.toStringAsFixed(0)
                            : '—',
                        hint: 'FlockAge×7 − BreakoutAge − StorageDays',
                      ),
                      _textField(_incubatorIdCtrl, 'Incubator ID'),
                      _textField(_hatcherIdCtrl, 'Hatcher ID'),
                      _numField(_sampleSizeCtrl, 'Sample Size'),
                    ],
                  ),
                ),

                // ── Tray tabs ────────────────────────────────────────────────
                if (_trays.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 6,
                    ),
                    child: Column(
                      children: [
                        // Tab bar
                        Container(
                          color: AppTheme.primary,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabs: List.generate(
                              _trays.length,
                              (i) => Tab(text: 'Tray ${i + 1}'),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 520,
                          child: TabBarView(
                            controller: _tabController,
                            children: List.generate(
                              _trays.length,
                              (i) => _buildTrayContent(i),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          // ── Submit button ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
            child: SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSaving ? null : _save,
                icon: _isSaving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
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
    );
  }

  Widget _buildTrayContent(int i) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Tray ID + Position row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _trayIdCtrls[i],
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Tray ID',
                    isDense: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: DropdownButtonFormField<String>(
                  initialValue: _trayPositions[i],
                  decoration: const InputDecoration(
                    labelText: 'Tray Position',
                    isDense: true,
                  ),
                  items: kTrayPositions
                      .map((p) => DropdownMenuItem(value: p, child: Text(p)))
                      .toList(),
                  onChanged: (v) {
                    if (v != null) setState(() => _trayPositions[i] = v);
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          // 15 category fields
          ...List.generate(kEggBreakoutCategories.length, (ci) {
            final key = kEggBreakoutCategories[ci];
            final label = kEggBreakoutCategoryLabels[key] ?? key;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Expanded(
                    flex: 5,
                    child: Text(
                      '${ci + 1}. $label',
                      style: const TextStyle(
                        fontSize: 13,
                        color: AppTheme.textPrimary,
                      ),
                    ),
                  ),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: _trayCtrls[i][key],
                      keyboardType: TextInputType.number,
                      textAlign: TextAlign.center,
                      textInputAction: ci < kEggBreakoutCategories.length - 1
                          ? TextInputAction.next
                          : TextInputAction.done,
                      style: const TextStyle(fontSize: 14),
                      decoration: const InputDecoration(
                        isDense: true,
                        contentPadding: EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 10,
                        ),
                      ),
                      onChanged: (v) {
                        _trays[i][key] = int.tryParse(v) ?? 0;
                      },
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  // ── Field helpers ──────────────────────────────────────────────────────────

  Widget _readOnlyField(String label, String value, {String? hint}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          helperText: hint,
          filled: true,
          fillColor: AppTheme.background,
        ),
        child: Text(
          value,
          style: const TextStyle(
            fontSize: 15,
            fontWeight: FontWeight.w600,
            color: AppTheme.textPrimary,
          ),
        ),
      ),
    );
  }

  Widget _numField(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: TextInputType.number,
        decoration: InputDecoration(labelText: label),
        onChanged: (_) => setState(() {}),
      ),
    );
  }

  Widget _textField(TextEditingController ctrl, String label) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        decoration: InputDecoration(labelText: label),
      ),
    );
  }
}
