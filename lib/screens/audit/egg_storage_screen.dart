import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/egg_storage.dart';
import '../../utils/app_theme.dart';
import '../../widgets/ble_sensor_widget.dart';
import '../../widgets/section_card.dart';

class EggStorageScreen extends StatefulWidget {
  const EggStorageScreen({super.key});

  @override
  State<EggStorageScreen> createState() => _EggStorageScreenState();
}

class _EggStorageScreenState extends State<EggStorageScreen> {
  static const double _tempTarget = 19.0;
  final _uuid = const Uuid();
  final _formKey = GlobalKey<FormState>();

  // BLE
  double? _roomTemp;
  double? _roomHumidity;

  // Egg Storage fields
  final _eggshellTempCtrl = TextEditingController();
  String? _turningFrequency;

  // UV Candling trays (up to 10)
  final List<_TrayEntry> _trays = [];

  // Quality Metadata
  final _storageDaysCtrl = TextEditingController();
  String? _sanitizationMethod;
  final _sanitizationAgentCtrl = TextEditingController();

  bool _isSaving = false;

  // Turning frequency options
  static const List<String> _turningOptions = [
    'No turning',
    '1 time per day',
    '2 times per day',
    '3 times per day',
    '4 times per day',
    '5 times per day',
    '6 times per day',
    '7 times per day',
    '8 times per day',
    '9 times per day',
    '10 times per day',
  ];

  @override
  void initState() {
    super.initState();
    _loadExisting();
    // Start with one tray
    if (_trays.isEmpty) _addTray();
  }

  void _loadExisting() {
    final existing = context.read<AppProvider>().eggStorage;
    if (existing == null) return;

    _roomTemp = existing.temperature;
    _roomHumidity = existing.humidity;
    _eggshellTempCtrl.text =
        existing.eggshellTemperature?.toStringAsFixed(1) ?? '';
    _turningFrequency = existing.turningFrequency;
    _storageDaysCtrl.text = existing.storageDays?.toString() ?? '';
    _sanitizationMethod = existing.sanitizationMethod;
    _sanitizationAgentCtrl.text = existing.sanitizationAgent ?? '';
    // UV tray data stored in uvTrays field as comma-separated "total:affected" pairs
    if (existing.uvTrays != null && existing.uvTrays!.isNotEmpty) {
      _trays.clear();
      for (final pair in existing.uvTrays!.split(';')) {
        final parts = pair.split(':');
        if (parts.length == 2) {
          _trays.add(_TrayEntry(
            totalCtrl: TextEditingController(text: parts[0]),
            affectedCtrl: TextEditingController(text: parts[1]),
          ));
        }
      }
    }
  }

  void _addTray() {
    if (_trays.length >= 10) return;
    setState(() {
      _trays.add(_TrayEntry(
        totalCtrl: TextEditingController(text: '150'),
        affectedCtrl: TextEditingController(text: '0'),
      ));
    });
  }

  void _removeTray(int index) {
    setState(() {
      _trays[index].dispose();
      _trays.removeAt(index);
    });
  }

  double? get _eggshellTemp =>
      double.tryParse(_eggshellTempCtrl.text.trim());

  Color get _eggshellTempColor {
    final t = _eggshellTemp;
    if (t == null) return AppTheme.textSecondary;
    return t < _tempTarget ? AppTheme.green : AppTheme.red;
  }

  double? _trayPercent(_TrayEntry tray) {
    final total = int.tryParse(tray.totalCtrl.text.trim());
    final affected = int.tryParse(tray.affectedCtrl.text.trim());
    if (total == null || total == 0 || affected == null) return null;
    return (affected / total) * 100;
  }

  double? get _overallAvgPercent {
    final percents = _trays
        .map(_trayPercent)
        .where((p) => p != null)
        .cast<double>()
        .toList();
    if (percents.isEmpty) return null;
    return percents.reduce((a, b) => a + b) / percents.length;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;

    final provider = context.read<AppProvider>();
    final session = provider.currentSession;
    if (session == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No active audit session.')),
      );
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Encode tray data as "total:affected" pairs joined by ";"
      final uvTraysEncoded = _trays
          .map((t) =>
              '${t.totalCtrl.text.trim()}:${t.affectedCtrl.text.trim()}')
          .join(';');

      final existing = provider.eggStorage;
      final es = EggStorage(
        id: existing?.id ?? _uuid.v4(),
        auditSessionId: session.id,
        customerId: provider.currentCustomer!.id,
        flockId: provider.currentFlock!.id,
        temperature: _roomTemp,
        humidity: _roomHumidity,
        eggshellTemperature: _eggshellTemp,
        turningFrequency: _turningFrequency,
        uvTrays: uvTraysEncoded.isEmpty ? null : uvTraysEncoded,
        storageDays: int.tryParse(_storageDaysCtrl.text.trim()),
        sanitizationMethod: _sanitizationMethod,
        sanitizationAgent: _sanitizationAgentCtrl.text.trim().isEmpty
            ? null
            : _sanitizationAgentCtrl.text.trim(),
        isCompleted: true,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );

      await provider.saveEggStorage(es);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Egg storage saved and marked complete!'),
            backgroundColor: AppTheme.green,
          ),
        );
        Navigator.of(context).pop();
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  void dispose() {
    _eggshellTempCtrl.dispose();
    _storageDaysCtrl.dispose();
    _sanitizationAgentCtrl.dispose();
    for (final t in _trays) {
      t.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final avgPercent = _overallAvgPercent;

    return Scaffold(
      appBar: AppBar(title: const Text('Egg Storage & Handling')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.only(bottom: 100),
          children: [
            const SizedBox(height: 8),

            // ── BLE Sensor ─────────────────────────────────────────────────
            BleSensorWidget(
              temperature: _roomTemp,
              humidity: _roomHumidity,
              onReading: (temp, hum) {
                setState(() {
                  _roomTemp = temp;
                  _roomHumidity = hum;
                });
              },
            ),

            // ── Egg Storage Section ────────────────────────────────────────
            SectionCard(
              title: 'Egg Storage',
              icon: Icons.egg_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Eggshell temperature
                  TextFormField(
                    controller: _eggshellTempCtrl,
                    keyboardType: const TextInputType.numberWithOptions(
                        decimal: true, signed: true),
                    decoration: InputDecoration(
                      labelText: 'Eggshell Temperature (°C)',
                      hintText: 'Target < 19 °C',
                      suffixIcon: _eggshellTemp != null
                          ? Icon(
                              _eggshellTemp! < _tempTarget
                                  ? Icons.check_circle
                                  : Icons.cancel,
                              color: _eggshellTempColor,
                              size: 20,
                            )
                          : null,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                  if (_eggshellTemp != null) ...[
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        Icon(
                          _eggshellTemp! < _tempTarget
                              ? Icons.check_circle
                              : Icons.warning_amber,
                          color: _eggshellTempColor,
                          size: 14,
                        ),
                        const SizedBox(width: 4),
                        Text(
                          _eggshellTemp! < _tempTarget
                              ? 'Within target (< 19 °C)'
                              : 'Exceeds target of 19 °C!',
                          style: TextStyle(
                            fontSize: 11,
                            color: _eggshellTempColor,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: 14),
                  // Turning frequency dropdown
                  DropdownButtonFormField<String>(
                    initialValue: _turningFrequency,
                    decoration: const InputDecoration(
                      labelText: 'Turning Frequency',
                    ),
                    hint: const Text('Select frequency'),
                    items: _turningOptions
                        .map((o) => DropdownMenuItem(value: o, child: Text(o)))
                        .toList(),
                    onChanged: (val) => setState(() => _turningFrequency = val),
                  ),
                ],
              ),
            ),

            // ── UV Torch Candling Section ──────────────────────────────────
            SectionCard(
              title: 'UV Torch Candling',
              icon: Icons.flashlight_on_outlined,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Info banner
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: AppTheme.amber.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: AppTheme.amber.withValues(alpha: 0.4)),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.info_outline,
                            size: 16, color: AppTheme.amber),
                        SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Sample: 10 trays per lot',
                            style: TextStyle(
                                fontSize: 13,
                                color: AppTheme.textPrimary,
                                fontWeight: FontWeight.w500),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Tray list
                  ...List.generate(_trays.length, (i) {
                    final tray = _trays[i];
                    final pct = _trayPercent(tray);
                    return Card(
                      margin: const EdgeInsets.only(bottom: 8),
                      elevation: 1,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Text(
                                  'Tray ${i + 1}',
                                  style: const TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    color: AppTheme.primary,
                                  ),
                                ),
                                if (pct != null) ...[
                                  const SizedBox(width: 8),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: (pct > 5
                                              ? AppTheme.red
                                              : AppTheme.green)
                                          .withValues(alpha: 0.12),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      '${pct.toStringAsFixed(1)} % affected',
                                      style: TextStyle(
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,
                                        color: pct > 5
                                            ? AppTheme.red
                                            : AppTheme.green,
                                      ),
                                    ),
                                  ),
                                ],
                                const Spacer(),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline,
                                      color: AppTheme.red, size: 20),
                                  onPressed: () => _removeTray(i),
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            Row(
                              children: [
                                Expanded(
                                  child: TextFormField(
                                    controller: tray.totalCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Total Eggs',
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: TextFormField(
                                    controller: tray.affectedCtrl,
                                    keyboardType: TextInputType.number,
                                    decoration: const InputDecoration(
                                      labelText: 'Affected Count',
                                      isDense: true,
                                    ),
                                    onChanged: (_) => setState(() {}),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 8),
                            // Photo upload button
                            OutlinedButton.icon(
                              onPressed: () {
                                setState(() =>
                                    tray.hasPhoto = !tray.hasPhoto);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: Text(tray.hasPhoto
                                        ? 'Photo captured (simulated).'
                                        : 'Photo removed.'),
                                    duration:
                                        const Duration(milliseconds: 1200),
                                  ),
                                );
                              },
                              icon: Icon(
                                tray.hasPhoto
                                    ? Icons.check_circle_outline
                                    : Icons.camera_alt_outlined,
                                size: 16,
                              ),
                              label: Text(tray.hasPhoto
                                  ? 'Photo Added'
                                  : 'Upload Photo'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: tray.hasPhoto
                                    ? AppTheme.green
                                    : AppTheme.textSecondary,
                                side: BorderSide(
                                  color: tray.hasPhoto
                                      ? AppTheme.green
                                      : Colors.grey.shade400,
                                ),
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 12, vertical: 8),
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  }),

                  // Add tray button
                  if (_trays.length < 10)
                    OutlinedButton.icon(
                      onPressed: _addTray,
                      icon: const Icon(Icons.add, size: 18),
                      label: Text('Add Tray (${_trays.length}/10)'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: AppTheme.primary,
                        side: const BorderSide(color: AppTheme.primary),
                      ),
                    ),

                  // Overall average
                  if (avgPercent != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: (avgPercent > 5 ? AppTheme.red : AppTheme.green)
                            .withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: (avgPercent > 5
                                  ? AppTheme.red
                                  : AppTheme.green)
                              .withValues(alpha: 0.4),
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            avgPercent > 5
                                ? Icons.warning_amber
                                : Icons.check_circle,
                            color: avgPercent > 5
                                ? AppTheme.red
                                : AppTheme.green,
                            size: 20,
                          ),
                          const SizedBox(width: 10),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Overall Average Affected',
                                style: TextStyle(
                                    fontSize: 12,
                                    color: AppTheme.textSecondary),
                              ),
                              Text(
                                '${avgPercent.toStringAsFixed(2)} %',
                                style: TextStyle(
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                  color: avgPercent > 5
                                      ? AppTheme.red
                                      : AppTheme.green,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // ── Egg Quality Metadata ───────────────────────────────────────
            SectionCard(
              title: 'Egg Quality Metadata',
              icon: Icons.assignment_outlined,
              child: Column(
                children: [
                  TextFormField(
                    controller: _storageDaysCtrl,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Storage Days',
                      hintText: 'Days eggs stored before setting',
                    ),
                  ),
                  const SizedBox(height: 14),
                  DropdownButtonFormField<String>(
                    initialValue: _sanitizationMethod,
                    decoration:
                        const InputDecoration(labelText: 'Sanitization Method'),
                    hint: const Text('Select method'),
                    items: const [
                      DropdownMenuItem(value: 'Spray', child: Text('Spray')),
                      DropdownMenuItem(
                          value: 'Fumigation', child: Text('Fumigation')),
                      DropdownMenuItem(value: 'None', child: Text('None')),
                    ],
                    onChanged: (val) =>
                        setState(() => _sanitizationMethod = val),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _sanitizationAgentCtrl,
                    decoration: const InputDecoration(
                      labelText: 'Sanitization Agent',
                      hintText: 'e.g. Formaldehyde, Quaternary ammonium',
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),

      // ── Save Button ───────────────────────────────────────────────────────
      bottomNavigationBar: Padding(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
        child: ElevatedButton.icon(
          onPressed: _isSaving ? null : _save,
          icon: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Colors.white),
                )
              : const Icon(Icons.save_outlined),
          label: Text(_isSaving ? 'Saving...' : 'Save Egg Storage'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
      ),
    );
  }
}

// ── Local state helpers ────────────────────────────────────────────────────

class _TrayEntry {
  final TextEditingController totalCtrl;
  final TextEditingController affectedCtrl;
  bool hasPhoto = false;

  _TrayEntry({
    required this.totalCtrl,
    required this.affectedCtrl,
  });

  void dispose() {
    totalCtrl.dispose();
    affectedCtrl.dispose();
  }
}
