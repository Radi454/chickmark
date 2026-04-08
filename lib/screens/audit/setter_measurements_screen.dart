import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../providers/app_provider.dart';
import '../../models/setter_measurements.dart';
import '../../utils/app_theme.dart';
import '../../widgets/ble_sensor_widget.dart';
import '../../widgets/temperature_grid_widget.dart';

class SetterMeasurementsScreen extends StatefulWidget {
  const SetterMeasurementsScreen({super.key});

  @override
  State<SetterMeasurementsScreen> createState() =>
      _SetterMeasurementsScreenState();
}

class _SetterMeasurementsScreenState extends State<SetterMeasurementsScreen> {
  // BLE readings
  double? _temperature;
  double? _humidity;

  // Metadata
  final _setterIdCtrl = TextEditingController();
  final _incubationAgeCtrl = TextEditingController();

  // Eggshell temperature grid — 9 cells row-major [topFront..botBack]
  final List<double?> _gridValues = List.filled(9, null);

  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadExisting());
  }

  void _loadExisting() {
    final provider = context.read<AppProvider>();
    final sm = provider.setterMeasurements;
    if (sm == null) return;

    setState(() {
      _temperature = sm.temperature;
      _humidity = sm.humidity;
      _setterIdCtrl.text = sm.setterId ?? '';
      _incubationAgeCtrl.text = sm.incubationAge?.toString() ?? '';
      _gridValues[0] = sm.topFront;
      _gridValues[1] = sm.topMiddle;
      _gridValues[2] = sm.topBack;
      _gridValues[3] = sm.midFront;
      _gridValues[4] = sm.midMiddle;
      _gridValues[5] = sm.midBack;
      _gridValues[6] = sm.botFront;
      _gridValues[7] = sm.botMiddle;
      _gridValues[8] = sm.botBack;
    });
  }

  @override
  void dispose() {
    _setterIdCtrl.dispose();
    _incubationAgeCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final provider = context.read<AppProvider>();
    final session = provider.currentSession;
    if (session == null) return;

    setState(() => _isSaving = true);
    try {
      final existing = provider.setterMeasurements;
      final sm = SetterMeasurements(
        id: existing?.id ?? const Uuid().v4(),
        auditSessionId: session.id,
        customerId: session.customerId,
        flockId: session.flockId,
        setterId:
            _setterIdCtrl.text.isEmpty ? null : _setterIdCtrl.text,
        incubationAge: int.tryParse(_incubationAgeCtrl.text),
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

      await provider.saveSetterMeasurements(sm);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Setter Measurements saved and marked complete!'),
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
      appBar: AppBar(title: const Text('Setter Measurements')),
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
                      'Setter Information',
                      style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: AppTheme.textPrimary),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: _setterIdCtrl,
                      decoration: const InputDecoration(
                        labelText: 'Setter ID',
                        prefixIcon:
                            Icon(Icons.label_outline, size: 18),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      controller: _incubationAgeCtrl,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Incubation Age (days)',
                        prefixIcon: Icon(Icons.calendar_today_outlined,
                            size: 18),
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

            // Temperature grid
            Card(
              margin: const EdgeInsets.fromLTRB(16, 6, 16, 6),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: TemperatureGridWidget(
                  values: _gridValues,
                  label: 'Eggshell Temperature Grid (°C)',
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
