import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/hatchery_results.dart';
import '../../utils/app_theme.dart';
import '../../widgets/section_card.dart';

class HatcheryResultsScreen extends StatefulWidget {
  const HatcheryResultsScreen({super.key});

  @override
  State<HatcheryResultsScreen> createState() => _HatcheryResultsScreenState();
}

class _HatcheryResultsScreenState extends State<HatcheryResultsScreen>
    with TickerProviderStateMixin {
  late TabController _tabController;

  // ── Fixed top-section controllers ──────────────────────────────────────────
  final _eggStorageDaysCtrl = TextEditingController();
  final _totalHatcherCapacityCtrl =
      TextEditingController(text: '19200');

  // ── Per-hatcher data ───────────────────────────────────────────────────────
  final List<_HatcherData> _hatchers = [];

  bool _isSaving = false;

  // ── Helpers ────────────────────────────────────────────────────────────────

  double get _currentFlockAgeWeeks {
    final provider = context.read<AppProvider>();
    return provider.currentFlock?.currentAgeWeeks ?? 0.0;
  }

  double? get _eggProductionAgeDays {
    final age = _currentFlockAgeWeeks;
    final storageDays = int.tryParse(_eggStorageDaysCtrl.text);
    if (storageDays == null) return null;
    return (age * 7) - 21 - storageDays;
  }

  String get _flockId {
    final provider = context.read<AppProvider>();
    return provider.currentFlock?.flockCode ?? '';
  }

  int get _totalHatcherCapacity =>
      int.tryParse(_totalHatcherCapacityCtrl.text) ?? 19200;

  @override
  void initState() {
    super.initState();
    _rebuildTabController();
    _addHatcher();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  void _rebuildTabController() {
    _tabController = TabController(
        length: _hatchers.isEmpty ? 1 : _hatchers.length, vsync: this);
  }

  void _addHatcher() {
    setState(() {
      _hatchers.add(_HatcherData());
      _tabController.dispose();
      _rebuildTabController();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_hatchers.isNotEmpty) {
          _tabController.animateTo(_hatchers.length - 1);
        }
      });
    });
  }

  void _loadExisting() {
    final provider = context.read<AppProvider>();
    final hr = provider.hatcheryResults;
    if (hr == null) return;

    setState(() {
      _eggStorageDaysCtrl.text = hr.eggStorageDays?.toString() ?? '';
      _totalHatcherCapacityCtrl.text =
          (hr.totalHatcherCapacity ?? 19200).toString();

      final loaded = hr.hatchers;
      if (loaded.isNotEmpty) {
        for (final h in _hatchers) {
          h.dispose();
        }
        _hatchers.clear();
        for (final entry in loaded) {
          _hatchers.add(_HatcherData.fromEntry(entry));
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
    _totalHatcherCapacityCtrl.dispose();
    for (final h in _hatchers) {
      h.dispose();
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
      final entries = _hatchers
          .map((h) => HatcherEntry(
                setterId: h.setterIdCtrl.text,
                hatcherId: h.hatcherIdCtrl.text,
                eggsSet: int.tryParse(h.eggsSetCtrl.text),
                hatched: int.tryParse(h.hatchedCtrl.text),
                culled: int.tryParse(h.culledCtrl.text),
                dead: int.tryParse(h.deadCtrl.text),
                infertileCount: int.tryParse(h.infertileCtrl.text),
                fertilityPercent: double.tryParse(h.fertilityCtrl.text),
              ))
          .toList();

      final existing = provider.hatcheryResults;
      final hr = HatcheryResults(
        id: existing?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: provider.currentCustomer?.id ?? session.customerId,
        flockId: provider.currentFlock?.id ?? session.flockId,
        eggStorageDays: int.tryParse(_eggStorageDaysCtrl.text),
        totalHatcherCapacity: _totalHatcherCapacity,
        isCompleted: true,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );
      hr.hatchers = entries;

      await provider.saveHatcheryResults(hr);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Hatchery results saved and marked complete!'),
            backgroundColor: AppTheme.green,
          ),
        );
        Navigator.of(context).pop();
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
        title: const Text('Hatchery Results'),
        actions: [
          TextButton.icon(
            onPressed: _addHatcher,
            icon: const Icon(Icons.add, color: Colors.white, size: 18),
            label: const Text('Add Hatcher',
                style: TextStyle(color: Colors.white, fontSize: 13)),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                // ── Fixed top section ──────────────────────────────────────
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
                      _readOnlyField(
                        'Egg Production Age (Days)',
                        eggProdAge != null
                            ? eggProdAge.toStringAsFixed(0)
                            : '—',
                        hint: 'FlockAge×7 − 21 − StorageDays',
                      ),
                      _numField(_totalHatcherCapacityCtrl,
                          'Total Hatcher Capacity'),
                    ],
                  ),
                ),

                // ── Hatcher tabs ───────────────────────────────────────────
                if (_hatchers.isNotEmpty)
                  Card(
                    margin: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 6),
                    child: Column(
                      children: [
                        Container(
                          color: AppTheme.primary,
                          child: TabBar(
                            controller: _tabController,
                            isScrollable: true,
                            tabs: List.generate(
                              _hatchers.length,
                              (i) => Tab(text: 'Hatcher ${i + 1}'),
                            ),
                          ),
                        ),
                        SizedBox(
                          height: 560,
                          child: TabBarView(
                            controller: _tabController,
                            children: List.generate(
                              _hatchers.length,
                              (i) =>
                                  _buildHatcherContent(i),
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
    );
  }

  Widget _buildHatcherContent(int i) {
    final h = _hatchers[i];
    return StatefulBuilder(
      builder: (context, setInner) {
        final cap = _totalHatcherCapacity;
        final hatched = int.tryParse(h.hatchedCtrl.text);
        final fertility = double.tryParse(h.fertilityCtrl.text);

        double? hatchabilityPct;
        if (hatched != null && cap > 0) {
          hatchabilityPct = (hatched / cap) * 100;
        }

        double? hofPct;
        if (hatchabilityPct != null &&
            fertility != null &&
            fertility > 0) {
          hofPct = (hatchabilityPct / fertility) * 100;
        }

        return SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildHatcherField(h.setterIdCtrl, 'Setter ID',
                  isNumber: false),
              _buildHatcherField(h.hatcherIdCtrl, 'Hatcher ID',
                  isNumber: false),
              _buildHatcherField(h.eggsSetCtrl, 'Eggs Set'),
              _buildHatcherField(h.hatchedCtrl, 'Hatched',
                  onChanged: (_) => setInner(() {})),
              _buildHatcherField(h.culledCtrl, 'Culled'),
              _buildHatcherField(h.deadCtrl, 'Dead'),
              _buildHatcherField(h.infertileCtrl, 'Infertile Count'),
              _buildHatcherField(h.fertilityCtrl, 'Fertility %',
                  isDecimal: true,
                  onChanged: (_) => setInner(() {})),
              const SizedBox(height: 4),
              _readOnlyField(
                'Hatchability %',
                hatchabilityPct != null
                    ? '${hatchabilityPct.toStringAsFixed(2)} %'
                    : '—',
                hint: 'Hatched ÷ Total Hatcher Capacity × 100',
              ),
              _readOnlyField(
                'HOF %',
                hofPct != null
                    ? '${hofPct.toStringAsFixed(2)} %'
                    : '—',
                hint: 'Hatchability% ÷ Fertility% × 100',
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHatcherField(
    TextEditingController ctrl,
    String label, {
    bool isNumber = true,
    bool isDecimal = false,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: isDecimal
            ? const TextInputType.numberWithOptions(decimal: true)
            : isNumber
                ? TextInputType.number
                : TextInputType.text,
        decoration: InputDecoration(labelText: label),
        onChanged: onChanged,
      ),
    );
  }

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
              color: AppTheme.textPrimary),
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
}

// ── Per-hatcher state holder ──────────────────────────────────────────────────

class _HatcherData {
  final setterIdCtrl = TextEditingController();
  final hatcherIdCtrl = TextEditingController();
  final eggsSetCtrl = TextEditingController();
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
    h.eggsSetCtrl.text = e.eggsSet?.toString() ?? '';
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
    eggsSetCtrl.dispose();
    hatchedCtrl.dispose();
    culledCtrl.dispose();
    deadCtrl.dispose();
    infertileCtrl.dispose();
    fertilityCtrl.dispose();
  }
}
