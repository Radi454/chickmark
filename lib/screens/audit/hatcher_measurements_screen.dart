import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/hatcher_measurements.dart';
import '../../utils/app_theme.dart';
import '../../widgets/ble_sensor_widget.dart';
import '../../widgets/temperature_grid_widget.dart';

class HatcherMeasurementsScreen extends StatefulWidget {
  const HatcherMeasurementsScreen({super.key});

  @override
  State<HatcherMeasurementsScreen> createState() =>
      _HatcherMeasurementsScreenState();
}

class _HatcherMeasurementsScreenState
    extends State<HatcherMeasurementsScreen> {
  // BLE readings
  double? _temperature;
  double? _humidity;

  // Metadata
  final _hatcherIdCtrl = TextEditingController();

  // Chick vent temperature grid — 9 cells row-major [topFront..botBack]
  final List<double?> _gridValues = List.filled(9, null);

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  void _loadExisting() {
    final provider = context.read<AppProvider>();
    final hm = provider.hatcherMeasurements;
    if (hm == null) return;

    setState(() {
      _temperature = hm.temperature;
      _humidity = hm.humidity;
      _hatcherIdCtrl.text = hm.hatcherId ?? '';
      _gridValues[0] = hm.topFront;
      _gridValues[1] = hm.topMiddle;
      _gridValues[2] = hm.topBack;
      _gridValues[3] = hm.midFront;
      _gridValues[4] = hm.midMiddle;
      _gridValues[5] = hm.midBack;
      _gridValues[6] = hm.botFront;
      _gridValues[7] = hm.botMiddle;
      _gridValues[8] = hm.botBack;
    });
  }

  @override
  void dispose() {
    _hatcherIdCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<AppProvider>();
    final session = provider.currentSession;
    if (session == null) return;

    setState(() => _isSaving = true);
    try {
      final existing = provider.hatcherMeasurements;
      final hm = HatcherMeasurements(
        id: existing?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: session.customerId,
        flockId: session.flockId,
        hatcherId:
            _hatcherIdCtrl.text.isEmpty ? null : _hatcherIdCtrl.text,
        temperature: _temperature,
        humidity: _humidity,
        topFront: _gridValues[0],
        topMiddle: _gridValues[1],
        topBack: _gridValues[2],
        midFront: _gridValues[3],
        midMiddle: _gridValues[4],
        midBack: _gridValues[5],
        botFront: _gridValues[6],
        botMiddle: _gridValues[7],
        botBack: _gridValues[8],
        isCompleted: true,
        createdAt: existing?.createdAt ?? DateTime.now(),
      );

      await provider.saveHatcherMeasurements(hm);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Hatcher Measurements saved and marked complete!'),
            backgroundColor: AppTheme.green,
          ),
        );
        Navigator.pop(context);
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AppProvider>();
    final session = provider.currentSession;
    final breed = session?.breed ?? '—';
    final flockAge = session != null
        ? '${session.flockAgeWeeks.toStringAsFixed(1)} wks'
        : '—';

    return Scaffold(
      appBar: AppBar(title: const Text('Hatcher Measurements')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 32),
        child: Column(
          children: [
            // BLE Sensor
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: BleSensorWidget(
                temperature: _temperature,
                humidity: _humidity,
                onReading: (t, h) => setState(() {
                  _temperature = t;
                  _humidity = h;
                }),
              ),
            ),

            // Metadata card
            Card(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Hatcher Information',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _hatcherIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Hatcher ID',
                        prefixIcon:
                            Icon(Icons.label_outline, size: 18),
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Divider(height: 1),
                    const SizedBox(height: 12),
                    // Read-only flock info
                    Row(
                      children: [
                        Expanded(
                          child: _readOnlyField(
                              'Breed', breed, Icons.egg_alt_outlined),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _readOnlyField(
                              'Flock Age',
                              flockAge,
                              Icons.access_time_outlined),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),

            // Chick vent temperature grid
            Card(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TemperatureGridWidget(
                  values: _gridValues,
                  label: 'Chick Vent Temperature Grid (°C)',
                  onChanged: (index, value) {
                    setState(() => _gridValues[index] = value);
                  },
                ),
              ),
            ),

            // Save button
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
                  label: const Text('Save & Mark Complete'),
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

  Widget _readOnlyField(String label, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: AppTheme.background,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppTheme.textSecondary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: const TextStyle(
                        fontSize: 10, color: AppTheme.textSecondary)),
                Text(value,
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: AppTheme.textPrimary),
                    overflow: TextOverflow.ellipsis),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
