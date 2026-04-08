import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/vaccine_storage.dart';
import '../../utils/app_theme.dart';
import '../../widgets/ble_sensor_widget.dart';
import '../../widgets/section_card.dart';

class VaccineStorageScreen extends StatefulWidget {
  const VaccineStorageScreen({super.key});

  @override
  State<VaccineStorageScreen> createState() => _VaccineStorageScreenState();
}

class _VaccineStorageScreenState extends State<VaccineStorageScreen> {
  final _uuid = const Uuid();

  // BLE readings
  double? _roomTemp;
  double? _roomHumidity;

  // Fridge vaccines
  final List<_FridgeVaccineEntry> _fridgeEntries = [];

  // HVT containers
  final List<_HvtEntry> _hvtEntries = [];

  // Handling checklist
  bool _coldChain = false;
  bool _expiryChecked = false;
  bool _dilutionProtocol = false;
  bool _roomBiosecure = false;

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _loadExisting();
  }

  void _loadExisting() {
    final existing = context.read<AppProvider>().vaccineStorage;
    if (existing == null) return;

    _roomTemp = existing.roomTemperature;
    _roomHumidity = existing.roomHumidity;

    for (final v in existing.fridgeVaccines) {
      _fridgeEntries.add(_FridgeVaccineEntry(
        nameController: TextEditingController(text: v.name),
        type: v.manufacturer ?? 'Live',
        tempController:
            TextEditingController(text: v.storageTemp?.toStringAsFixed(1) ?? ''),
      ));
    }

    for (final c in existing.hvtContainers) {
      _hvtEntries.add(_HvtEntry(
        idController: TextEditingController(text: c.id ?? ''),
        nitrogenController:
            TextEditingController(text: c.storageTemp?.toStringAsFixed(1) ?? ''),
        hasPhoto: false,
      ));
    }

    _coldChain = existing.coldChainMaintained;
    _expiryChecked = existing.expiryDatesChecked;
    _dilutionProtocol = existing.dilutionProtocolFollowed;
    _roomBiosecure = existing.vaccinationRoomBiosecure;
  }

  // ── Add / remove fridge vaccines ──────────────────────────────────────────

  void _addFridgeVaccine() {
    setState(() {
      _fridgeEntries.add(_FridgeVaccineEntry(
        nameController: TextEditingController(),
        type: 'Live',
        tempController: TextEditingController(),
      ));
    });
  }

  void _removeFridgeVaccine(int index) {
    setState(() {
      _fridgeEntries[index].dispose();
      _fridgeEntries.removeAt(index);
    });
  }

  // ── Add / remove HVT containers ───────────────────────────────────────────

  void _addHvtContainer() {
    setState(() {
      _hvtEntries.add(_HvtEntry(
        idController: TextEditingController(),
        nitrogenController: TextEditingController(),
        hasPhoto: false,
      ));
    });
  }

  void _removeHvtContainer(int index) {
    setState(() {
      _hvtEntries[index].dispose();
      _hvtEntries.removeAt(index);
    });
  }

  // ── Temperature flag helpers ───────────────────────────────────────────────

  Color _tempFlagColor(double? temp) {
    if (temp == null) return AppTheme.textSecondary;
    return (temp >= 2.0 && temp <= 8.0) ? AppTheme.green : AppTheme.red;
  }

  IconData _tempFlagIcon(double? temp) {
    if (temp == null) return Icons.help_outline;
    return (temp >= 2.0 && temp <= 8.0) ? Icons.check_circle : Icons.cancel;
  }

  // ── Save ──────────────────────────────────────────────────────────────────

  Future<void> _save() async {
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
      final fridgeVaccines = _fridgeEntries.map((e) {
        final tempStr = e.tempController.text.trim();
        return FridgeVaccine(
          name: e.nameController.text.trim(),
          manufacturer: e.type, // using manufacturer field to store type
          storageTemp: tempStr.isEmpty ? null : double.tryParse(tempStr),
        );
      }).toList();

      final hvtContainers = _hvtEntries.map((e) {
        final nitrogenStr = e.nitrogenController.text.trim();
        return HvtContainer(
          id: e.idController.text.trim(),
          storageTemp: nitrogenStr.isEmpty ? null : double.tryParse(nitrogenStr),
        );
      }).toList();

      final existing = provider.vaccineStorage;
      final vs = VaccineStorage(
        id: existing?.id ?? _uuid.v4(),
        auditSessionId: session.id,
        customerId: provider.currentCustomer!.id,
        flockId: provider.currentFlock!.id,
        roomTemperature: _roomTemp,
        roomHumidity: _roomHumidity,
        coldChainMaintained: _coldChain,
        expiryDatesChecked: _expiryChecked,
        dilutionProtocolFollowed: _dilutionProtocol,
        vaccinationRoomBiosecure: _roomBiosecure,
        isCompleted: true,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );
      vs.fridgeVaccines = fridgeVaccines;
      vs.hvtContainers = hvtContainers;

      await provider.saveVaccineStorage(vs);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Vaccine storage saved and marked complete!'),
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
    for (final e in _fridgeEntries) {
      e.dispose();
    }
    for (final e in _hvtEntries) {
      e.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vaccine Storage & Handling')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const SizedBox(height: 8),

          // ── BLE Sensor ────────────────────────────────────────────────────
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

          const SizedBox(height: 8),

          // ── Fridge Vaccines ───────────────────────────────────────────────
          SectionCard(
            title: 'Fridge Vaccines',
            icon: Icons.vaccines,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (_fridgeEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No vaccines added. Tap the button below to add.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ...List.generate(_fridgeEntries.length, (i) {
                  final entry = _fridgeEntries[i];
                  final tempVal =
                      double.tryParse(entry.tempController.text.trim());
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                      side: BorderSide(
                        color: _tempFlagColor(tempVal).withValues(alpha: 0.4),
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              Icon(
                                _tempFlagIcon(tempVal),
                                color: _tempFlagColor(tempVal),
                                size: 20,
                              ),
                              const SizedBox(width: 6),
                              Text(
                                'Vaccine ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppTheme.red, size: 20),
                                onPressed: () => _removeFridgeVaccine(i),
                                padding: EdgeInsets.zero,
                                constraints: const BoxConstraints(),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          TextFormField(
                            controller: entry.nameController,
                            decoration: const InputDecoration(
                              labelText: 'Vaccine Name',
                              isDense: true,
                            ),
                            onChanged: (_) => setState(() {}),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: DropdownButtonFormField<String>(
                                  initialValue: entry.type,
                                  decoration: const InputDecoration(
                                    labelText: 'Type',
                                    isDense: true,
                                  ),
                                  items: const [
                                    DropdownMenuItem(
                                        value: 'Live', child: Text('Live')),
                                    DropdownMenuItem(
                                        value: 'Killed',
                                        child: Text('Killed')),
                                  ],
                                  onChanged: (val) {
                                    if (val != null) {
                                      setState(() => entry.type = val);
                                    }
                                  },
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: entry.tempController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true, signed: true),
                                  decoration: InputDecoration(
                                    labelText: 'Storage Temp (°C)',
                                    isDense: true,
                                    suffixIcon: tempVal != null
                                        ? Icon(
                                            _tempFlagIcon(tempVal),
                                            color: _tempFlagColor(tempVal),
                                            size: 18,
                                          )
                                        : null,
                                  ),
                                  onChanged: (_) => setState(() {}),
                                ),
                              ),
                            ],
                          ),
                          if (tempVal != null)
                            Padding(
                              padding: const EdgeInsets.only(top: 6),
                              child: Row(
                                children: [
                                  Icon(
                                    _tempFlagIcon(tempVal),
                                    color: _tempFlagColor(tempVal),
                                    size: 14,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    (tempVal >= 2.0 && tempVal <= 8.0)
                                        ? 'Within 2–8 °C range'
                                        : 'Outside 2–8 °C range!',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: _tempFlagColor(tempVal),
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _addFridgeVaccine,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Vaccine'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),

          // ── HVT Vaccines (Liquid Nitrogen) ────────────────────────────────
          SectionCard(
            title: 'HVT Vaccines (Liquid Nitrogen)',
            icon: Icons.science_outlined,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.info_outline,
                          size: 16, color: AppTheme.primary),
                      SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Liquid nitrogen containers store HVT vaccines at '
                          'approximately \u2212196 °C. Record nitrogen level in cm.',
                          style: TextStyle(
                              fontSize: 12, color: AppTheme.textSecondary),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (_hvtEntries.isEmpty)
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: Text(
                      'No containers added.',
                      style: TextStyle(
                          color: AppTheme.textSecondary, fontSize: 13),
                    ),
                  ),
                ...List.generate(_hvtEntries.length, (i) {
                  final entry = _hvtEntries[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 10),
                    elevation: 1,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              const Icon(Icons.science_outlined,
                                  color: AppTheme.primary, size: 18),
                              const SizedBox(width: 6),
                              Text(
                                'Container ${i + 1}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.w600,
                                  fontSize: 13,
                                ),
                              ),
                              const Spacer(),
                              IconButton(
                                icon: const Icon(Icons.delete_outline,
                                    color: AppTheme.red, size: 20),
                                onPressed: () => _removeHvtContainer(i),
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
                                  controller: entry.idController,
                                  decoration: const InputDecoration(
                                    labelText: 'Container ID',
                                    isDense: true,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: TextFormField(
                                  controller: entry.nitrogenController,
                                  keyboardType:
                                      const TextInputType.numberWithOptions(
                                          decimal: true),
                                  decoration: const InputDecoration(
                                    labelText: 'Nitrogen Level (cm)',
                                    isDense: true,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              OutlinedButton.icon(
                                onPressed: () {
                                  setState(
                                      () => entry.hasPhoto = !entry.hasPhoto);
                                  ScaffoldMessenger.of(context)
                                      .showSnackBar(SnackBar(
                                    content: Text(entry.hasPhoto
                                        ? 'Photo captured (simulated).'
                                        : 'Photo removed.'),
                                    duration:
                                        const Duration(milliseconds: 1200),
                                  ));
                                },
                                icon: Icon(
                                  entry.hasPhoto
                                      ? Icons.check_circle_outline
                                      : Icons.camera_alt_outlined,
                                  size: 16,
                                ),
                                label: Text(
                                    entry.hasPhoto ? 'Photo Added' : 'Upload Photo'),
                                style: OutlinedButton.styleFrom(
                                  foregroundColor: entry.hasPhoto
                                      ? AppTheme.green
                                      : AppTheme.textSecondary,
                                  side: BorderSide(
                                    color: entry.hasPhoto
                                        ? AppTheme.green
                                        : Colors.grey.shade400,
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 12, vertical: 8),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 4),
                OutlinedButton.icon(
                  onPressed: _addHvtContainer,
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add Container'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: AppTheme.primary,
                    side: const BorderSide(color: AppTheme.primary),
                  ),
                ),
              ],
            ),
          ),

          // ── Handling Checklist ────────────────────────────────────────────
          SectionCard(
            title: 'Handling Checklist',
            icon: Icons.checklist_outlined,
            child: Column(
              children: [
                _ChecklistRow(
                  label: 'Cold chain maintained',
                  value: _coldChain,
                  onChanged: (v) => setState(() => _coldChain = v),
                ),
                const Divider(height: 1),
                _ChecklistRow(
                  label: 'Expiry dates checked',
                  value: _expiryChecked,
                  onChanged: (v) => setState(() => _expiryChecked = v),
                ),
                const Divider(height: 1),
                _ChecklistRow(
                  label: 'Dilution protocol followed',
                  value: _dilutionProtocol,
                  onChanged: (v) => setState(() => _dilutionProtocol = v),
                ),
                const Divider(height: 1),
                _ChecklistRow(
                  label: 'Vaccination room biosecure',
                  value: _roomBiosecure,
                  onChanged: (v) => setState(() => _roomBiosecure = v),
                ),
              ],
            ),
          ),
        ],
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
          label: Text(_isSaving ? 'Saving...' : 'Save Vaccine Storage'),
          style: ElevatedButton.styleFrom(
            minimumSize: const Size.fromHeight(50),
          ),
        ),
      ),
    );
  }
}

// ── Local state helpers ────────────────────────────────────────────────────

class _FridgeVaccineEntry {
  final TextEditingController nameController;
  String type;
  final TextEditingController tempController;

  _FridgeVaccineEntry({
    required this.nameController,
    required this.type,
    required this.tempController,
  });

  void dispose() {
    nameController.dispose();
    tempController.dispose();
  }
}

class _HvtEntry {
  final TextEditingController idController;
  final TextEditingController nitrogenController;
  bool hasPhoto;

  _HvtEntry({
    required this.idController,
    required this.nitrogenController,
    required this.hasPhoto,
  });

  void dispose() {
    idController.dispose();
    nitrogenController.dispose();
  }
}

// ── Checklist row widget ───────────────────────────────────────────────────

class _ChecklistRow extends StatelessWidget {
  final String label;
  final bool value;
  final ValueChanged<bool> onChanged;

  const _ChecklistRow({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(label,
                style: const TextStyle(
                    fontSize: 14, color: AppTheme.textPrimary)),
          ),
          Row(
            children: [
              _ToggleChip(
                label: 'No',
                selected: !value,
                color: AppTheme.red,
                onTap: () => onChanged(false),
              ),
              const SizedBox(width: 8),
              _ToggleChip(
                label: 'Yes',
                selected: value,
                color: AppTheme.green,
                onTap: () => onChanged(true),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _ToggleChip extends StatelessWidget {
  final String label;
  final bool selected;
  final Color color;
  final VoidCallback onTap;

  const _ToggleChip({
    required this.label,
    required this.selected,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? color : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? color : Colors.grey.shade400),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: selected ? Colors.white : AppTheme.textSecondary,
          ),
        ),
      ),
    );
  }
}
