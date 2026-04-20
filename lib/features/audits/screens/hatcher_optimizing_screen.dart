import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../providers/audit_provider.dart';
import '../widgets/govee_sector.dart';
import '../widgets/photo_button.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class HatcherOptimizingScreen extends StatefulWidget {
  final AuditContextData context;
  const HatcherOptimizingScreen({super.key, required this.context});
  @override
  State<HatcherOptimizingScreen> createState() =>
      _HatcherOptimizingScreenState();
}

class _HatcherOptimizingScreenState extends State<HatcherOptimizingScreen> {
  final Map<String, TextEditingController> _controllers = {};
  final Map<String, String?> _photos = {};
  final TextEditingController _avgController = TextEditingController();
  final TextEditingController _cvController = TextEditingController();
  final TextEditingController _incubationAgeController = TextEditingController(
    text: '18',
  );
  bool _chickPanting = false;

  @override
  void initState() {
    super.initState();
    final rows = ['Door', 'Middle', 'Back'];
    final cols = ['Top', 'Middle', 'Bottom'];
    for (var r in rows) {
      for (var c in cols) {
        _controllers['${r}_$c'] = TextEditingController();
      }
    }
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    auditProvider.initialize(
      AuditContext(
        auditType: widget.context.auditType,
        customerId: widget.context.customerId,
        flockId: widget.context.flockId,
        breed: widget.context.breed,
        date: widget.context.date,
      ),
      notify: false,
      currentUser: context.read<AuthProvider>().user,
    );
  }

  void _updateCalculations() {
    final temps = _controllers.values
        .map((c) => double.tryParse(c.text))
        .where((t) => t != null)
        .map((t) => t!)
        .toList();
    if (temps.isEmpty) return;
    final avg = CalculationUtils.average(temps);
    final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;
    _avgController.text = avg.toStringAsFixed(1);
    _cvController.text = cv.toStringAsFixed(1);
    final readings = _controllers.map((key, value) {
      return MapEntry(key, double.tryParse(value.text));
    });
    final auditProvider = context.read<AuditProvider>();
    auditProvider.updateField('hoCvtReadings', jsonEncode(readings));
    auditProvider.updateField('hoCvtAvg', avg);
    auditProvider.updateField('hoCvtCv', cv);
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();
    final audit = auditProvider.activeDraft;
    return Scaffold(
      appBar: GradientAppBar(
        title: 'Hatcher Optimizing',
        actions: [
          if (!auditProvider.isReadOnly)
            IconButton(
              icon: const Icon(Icons.edit),
              onPressed: () => auditProvider.setEditMode(true),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Column(
                  children: [
                    Text(
                      'Breed: ${widget.context.breed ?? "--"}',
                      style: AppTextStyles.body,
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'Hatcher ID',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) {
                        auditProvider.updateField('hatcherId', v);
                        auditProvider.updateField('hoHatcherId', v);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Column(
                  children: [
                    Text(
                      'Incubation Age: ${_incubationAgeController.text} days',
                      style: AppTextStyles.body,
                    ),
                    Slider(
                      value:
                          double.tryParse(_incubationAgeController.text) ?? 18,
                      min: 18,
                      max: 21,
                      divisions: 3,
                      onChanged: (v) {
                        final age = v.toInt();
                        setState(() {
                          _incubationAgeController.text = age.toString();
                        });
                        auditProvider.updateField('hoIncubationAge', age);
                      },
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            GoveeSector(
              isAvailable: false,
              isConnected: false,
              onScanTap: () {},
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Column(
                  children: [
                    TextField(
                      decoration: const InputDecoration(
                        labelText: 'CO2 Level (ppm)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => auditProvider.updateField(
                        'hoCo2',
                        double.tryParse(v),
                      ),
                    ),
                    const SizedBox(height: 8),
                    PhotoButton(
                      photoPath: audit.hoCo2Photo,
                      enabled: !auditProvider.isReadOnly,
                      onPhotoCaptured: (p) =>
                          auditProvider.updateField('hoCo2Photo', p),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(child: _statCard('AVG', _avgController.text, null)),
                const SizedBox(width: 8),
                Expanded(child: _statCard('CV%', _cvController.text, null)),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Column(
                  children: [
                    Text(
                      'Chick Vent Temperature (CVT) - Optimum: 103-105°F',
                      style: AppTextStyles.body,
                    ),
                    _buildCvtGrid(auditProvider),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Card(
              elevation: 2,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.cardRadius),
              ),
              child: Padding(
                padding: const EdgeInsets.all(AppSizes.cardPadding),
                child: Column(
                  children: [
                    Text('Chick Panting', style: AppTextStyles.body),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('No')),
                              ButtonSegment(value: true, label: Text('Yes')),
                            ],
                            selected: {_chickPanting},
                            onSelectionChanged: (s) {
                              setState(() => _chickPanting = s.first);
                              auditProvider.updateField(
                                'hoChickPanting',
                                s.first ? 1 : 0,
                              );
                            },
                          ),
                        ),
                        const SizedBox(width: 8),
                        PhotoButton(
                          photoPath: audit.hoChickPantingPhoto,
                          enabled: !auditProvider.isReadOnly,
                          onPhotoCaptured: (p) => auditProvider.updateField(
                            'hoChickPantingPhoto',
                            p,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: auditProvider.isReadOnly
            ? null
            : () => auditProvider.saveTab(0),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.save),
        label: const Text('Save'),
      ),
    );
  }

  Widget _statCard(String label, String value, Color? color) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.grey[100],
      borderRadius: BorderRadius.circular(8),
    ),
    child: Column(
      children: [
        Text(label, style: AppTextStyles.caption),
        Text(value.isEmpty ? '--' : value, style: AppTextStyles.heading),
      ],
    ),
  );

  Widget _buildCvtGrid(AuditProvider provider) {
    final rows = ['Door', 'Middle', 'Back'];
    final cols = ['Top', 'Middle', 'Bottom'];
    return Column(
      children: [
        for (var r in rows)
          Row(
            children: [
              SizedBox(width: 60, child: Text(r, style: AppTextStyles.body)),
              for (var c in cols)
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: TextField(
                      controller: _controllers['${r}_$c'],
                      enabled: !provider.isReadOnly,
                      keyboardType: TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: const InputDecoration(
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: (_) => _updateCalculations(),
                    ),
                  ),
                ),
              for (var c in cols)
                PhotoButton(
                  photoPath: _photos['${r}_$c'],
                  enabled: !provider.isReadOnly,
                  onPhotoCaptured: (p) =>
                      setState(() => _photos['${r}_$c'] = p),
                ),
            ],
          ),
      ],
    );
  }

  @override
  void dispose() {
    for (var c in _controllers.values) {
      c.dispose();
    }
    super.dispose();
  }
}
