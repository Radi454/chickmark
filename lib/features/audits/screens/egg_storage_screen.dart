import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/calculation_utils.dart';
import '../providers/audit_provider.dart';
import '../widgets/govee_sector.dart';
import '../widgets/photo_button.dart';
import '../widgets/weight_grid_widget.dart';
import '../../auth/providers/auth_provider.dart';
import 'audit_context_screen.dart';

class EggStorageScreen extends StatefulWidget {
  final AuditContextData context;

  const EggStorageScreen({super.key, required this.context});

  @override
  State<EggStorageScreen> createState() => _EggStorageScreenState();
}

class _EggStorageScreenState extends State<EggStorageScreen> {
  final List<_UvTray> _uvTrays = [];
  final List<TextEditingController> _eggWeightControllers = List.generate(
    100,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _eggWeightFocusNodes = List.generate(
    100,
    (_) => FocusNode(),
  );

  @override
  void initState() {
    super.initState();
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    final auditContext = AuditContext(
      auditType: widget.context.auditType,
      customerId: widget.context.customerId,
      flockId: widget.context.flockId,
      breed: widget.context.breed,
      date: widget.context.date,
    );
    auditProvider.initialize(
      auditContext,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
    );
  }

  @override
  void dispose() {
    for (var c in _eggWeightControllers) {
      c.dispose();
    }
    for (var n in _eggWeightFocusNodes) {
      n.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final auditProvider = context.watch<AuditProvider>();
    final audit = auditProvider.activeDraft;

    return Scaffold(
      appBar: GradientAppBar(
        title: 'Egg Storage & Handling',
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
            _buildSectorCard(
              title: 'Sector 1: Environment',
              child: GoveeSector(
                isAvailable: false,
                isConnected: false,
                onScanTap: () {},
              ),
            ),
            const SizedBox(height: 16),
            _buildSectorCard(
              title: 'Sector 2: CO₂',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      enabled: !auditProvider.isReadOnly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'CO₂ Level (ppm)',
                        border: OutlineInputBorder(),
                      ),
                      onChanged: (v) => auditProvider.updateField(
                        'esCo2',
                        double.tryParse(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  PhotoButton(
                    photoPath: audit.esCo2Photo,
                    enabled: !auditProvider.isReadOnly,
                    onPhotoCaptured: (p) =>
                        auditProvider.updateField('esCo2Photo', p),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectorCard(
              title: 'Sector 3: Shell Temperature',
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      enabled: !auditProvider.isReadOnly,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Shell Temperature (°C)',
                        border: OutlineInputBorder(),
                        suffixText: '°C',
                      ),
                      onChanged: (v) => auditProvider.updateField(
                        'esShellTemp',
                        double.tryParse(v),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  _buildTempStatus(audit.esShellTemp),
                  const SizedBox(width: 8),
                  PhotoButton(
                    photoPath: audit.esShellTempPhoto,
                    enabled: !auditProvider.isReadOnly,
                    onPhotoCaptured: (p) =>
                        auditProvider.updateField('esShellTempPhoto', p),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectorCard(
              title: 'Sector 4: Egg Turning',
              child: DropdownButtonFormField<int>(
                initialValue: audit.esTurningTimes,
                decoration: const InputDecoration(
                  labelText: 'Turning Times',
                  border: OutlineInputBorder(),
                ),
                items: const [
                  DropdownMenuItem(value: 0, child: Text('No Turning')),
                  DropdownMenuItem(value: 1, child: Text('1 time')),
                  DropdownMenuItem(value: 2, child: Text('2 times')),
                  DropdownMenuItem(value: 3, child: Text('3 times')),
                  DropdownMenuItem(value: 4, child: Text('4 times')),
                  DropdownMenuItem(value: 5, child: Text('5 times')),
                ],
                onChanged: auditProvider.isReadOnly
                    ? null
                    : (v) => auditProvider.updateField('esTurningTimes', v),
              ),
            ),
            const SizedBox(height: 16),
            _buildSectorCard(
              title: 'Sector 5: UV Tray Inspection',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (_uvTrays.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue[50],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        'Overall Avg Affected: ${_calculateOverallAvgAffected().toStringAsFixed(1)}%',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  const SizedBox(height: 12),
                  ..._uvTrays.asMap().entries.map(
                    (e) => _buildUvTrayCard(e.key, e.value, auditProvider),
                  ),
                  if (_uvTrays.length < 10 && !auditProvider.isReadOnly)
                    ElevatedButton.icon(
                      onPressed: () => setState(() => _uvTrays.add(_UvTray())),
                      icon: const Icon(Icons.add),
                      label: const Text('Add UV Tray'),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            _buildSectorCard(
              title: 'Sector 6: Egg Uniformity',
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  WeightGridWidget(
                    controllers: _eggWeightControllers,
                    focusNodes: _eggWeightFocusNodes,
                    enabled: !auditProvider.isReadOnly,
                  ),
                  const SizedBox(height: 16),
                  _buildUniformitySummary(),
                ],
              ),
            ),
            const SizedBox(height: 80),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: auditProvider.isReadOnly
            ? null
            : () => _handleSave(auditProvider),
        backgroundColor: AppColors.primary,
        icon: const Icon(Icons.save),
        label: const Text('Save'),
      ),
    );
  }

  Widget _buildSectorCard({required String title, required Widget child}) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildTempStatus(double? temp) {
    if (temp == null) return const SizedBox.shrink();
    final isOptimal =
        temp >= AppThresholds.shellTempMin &&
        temp <= AppThresholds.shellTempMax;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: (isOptimal ? AppColors.greenTab : Colors.red).withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isOptimal ? AppColors.greenTab : Colors.red),
      ),
      child: Text(
        isOptimal ? 'Optimal' : 'Warning',
        style: AppTextStyles.caption.copyWith(
          color: isOptimal ? AppColors.greenTab : Colors.red,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildUvTrayCard(int index, _UvTray tray, AuditProvider provider) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                enabled: !provider.isReadOnly,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Total Eggs',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(
                  () => _uvTrays[index] = tray..totalEggs = int.tryParse(v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                enabled: !provider.isReadOnly,
                keyboardType: TextInputType.number,
                decoration: const InputDecoration(
                  labelText: 'Affected',
                  border: OutlineInputBorder(),
                ),
                onChanged: (v) => setState(
                  () => _uvTrays[index] = tray..affectedCount = int.tryParse(v),
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              '${tray.affectedPct.toStringAsFixed(1)}%',
              style: AppTextStyles.body.copyWith(
                fontWeight: FontWeight.bold,
                color: _getAffectedColor(tray.affectedPct),
              ),
            ),
            const SizedBox(width: 8),
            if (!provider.isReadOnly)
              IconButton(
                icon: const Icon(Icons.delete, color: Colors.red),
                onPressed: () => setState(() => _uvTrays.removeAt(index)),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildUniformitySummary() {
    final weights = _eggWeightControllers
        .map((c) => double.tryParse(c.text))
        .where((w) => w != null && w > 0)
        .map((w) => w!)
        .toList();
    if (weights.isEmpty) {
      return const Card(
        child: Padding(
          padding: EdgeInsets.all(12),
          child: Text('Enter egg weights'),
        ),
      );
    }
    final avg = CalculationUtils.average(weights);
    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      avg * 0.9,
      avg * 1.1,
    );
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          children: [
            Expanded(
              child: _summCard(
                'AVG',
                '${avg.toStringAsFixed(1)}g',
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _summCard(
                'Uniformity',
                '${uniformity.toStringAsFixed(1)}%',
                uniformity >= 85 ? AppColors.greenTab : Colors.red,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _summCard(
                'CV%',
                '${cv.toStringAsFixed(1)}%',
                cv <= 8 ? AppColors.greenTab : Colors.red,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(8),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color),
    ),
    child: Column(
      children: [
        Text(label, style: AppTextStyles.caption),
        Text(
          value,
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.bold,
            color: color,
          ),
        ),
      ],
    ),
  );

  double _calculateOverallAvgAffected() => _uvTrays.isEmpty
      ? 0.0
      : _uvTrays.map((t) => t.affectedPct).reduce((a, b) => a + b) /
            _uvTrays.length;
  Color _getAffectedColor(double pct) => pct <= 5
      ? AppColors.greenTab
      : pct <= 10
      ? Colors.orange
      : Colors.red;

  Future<void> _handleSave(AuditProvider provider) async {
    provider.updateField(
      'esUvTrays',
      jsonEncode(_uvTrays.map((t) => t.toMap()).toList()),
    );
    await provider.saveTab(0);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Egg Storage audit saved'),
          backgroundColor: AppColors.greenTab,
        ),
      );
    }
  }
}

class _UvTray {
  int? totalEggs;
  int? affectedCount;
  double get affectedPct => totalEggs == null || totalEggs == 0
      ? 0.0
      : (affectedCount ?? 0) / totalEggs! * 100;
  Map<String, dynamic> toMap() => {
    'totalEggs': totalEggs,
    'affectedCount': affectedCount,
  };
}
