import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_thresholds.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/calculation_utils.dart';
import '../../../data/models/audit_model.dart';
import '../../../data/models/temperature_rh_model.dart';
import '../../auth/providers/auth_provider.dart';
import '../providers/audit_provider.dart';
import '../widgets/est_grid_widget.dart';
import '../widgets/govee_recording_card.dart';
import '../widgets/unsaved_changes_guard.dart';
import '../widgets/photo_button.dart';
import '../widgets/weight_grid_widget.dart';
import 'audit_context_screen.dart';

class EggStorageScreen extends StatefulWidget {
  final AuditContextData context;
  final AuditModel? initialAudit;
  final int initialSectionIndex;

  const EggStorageScreen({
    super.key,
    required this.context,
    this.initialAudit,
    this.initialSectionIndex = 0,
  });

  @override
  State<EggStorageScreen> createState() => _EggStorageScreenState();
}

class _EggStorageScreenState extends State<EggStorageScreen> {
  final ScrollController _scrollController = ScrollController();
  late final List<GlobalKey> _sectionKeys = List.generate(
    7,
    (_) => GlobalKey(),
  );
  final TextEditingController _shellTempController = TextEditingController();
  final Map<String, TextEditingController> _estControllers = {};
  final Map<String, String?> _estPhotos = {};
  final TextEditingController _estAvgController = TextEditingController();
  final TextEditingController _estCvController = TextEditingController();
  final List<_UvTray> _uvTrays = [];
  final List<TextEditingController> _eggWeightControllers = List.generate(
    100,
    (_) => TextEditingController(),
  );
  final List<FocusNode> _eggWeightFocusNodes = List.generate(
    100,
    (_) => FocusNode(),
  );
  String? _eggOrientation;
  String? _traySpacing;
  String? _coolerProximity;
  String? _wallProximity;
  bool? _condensation;

  List<TextInputFormatter> get _decimalInputFormatters => [
    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}')),
  ];

  List<TextInputFormatter> get _integerInputFormatters => [
    FilteringTextInputFormatter.digitsOnly,
  ];

  @override
  void initState() {
    super.initState();
    final rows = ['door', 'middle', 'back'];
    final cols = ['top', 'middle', 'bottom'];
    for (var r in rows) {
      for (var c in cols) {
        _estControllers['${r}_$c'] = TextEditingController();
      }
    }
    final auditProvider = Provider.of<AuditProvider>(context, listen: false);
    final auditContext = AuditContext(
      auditType: widget.context.auditType,
      customerId: widget.context.customerId,
      flockId: widget.context.flockId,
      breed: widget.context.breed,
      setterId: widget.context.setterId,
      hatcherId: widget.context.hatcherId,
      date: widget.context.date,
    );
    auditProvider.initialize(
      auditContext,
      existingAudit: widget.initialAudit,
      notify: false,
      currentUser: context.read<AuthProvider>().user,
      sessionId: widget.context.sessionId,
    );
    _initializeFormState(auditProvider.activeDraft);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollToInitialSection();
    });
  }

  void _initializeFormState(AuditModel audit) {
    _shellTempController.text = _formatNumber(audit.esShellTemp);
    _loadEstGrid(audit.esEstReadingsJson);
    _estAvgController.text = audit.esEstAvg != null
        ? audit.esEstAvg!.toStringAsFixed(1)
        : '';
    _estCvController.text = audit.esEstCv != null
        ? audit.esEstCv!.toStringAsFixed(1)
        : '';
    _loadUvTrays(audit.esUvTrays);
    _loadEggWeights(audit.esEggWeights);
    _eggOrientation = audit.esEggOrientation;
    _traySpacing = audit.esTraySpacing;
    _coolerProximity = audit.esCoolerProximity;
    _wallProximity = audit.esWallProximity;
    _condensation = audit.esCondensation;
  }

  void _loadEstGrid(String? readingsJson) {
    if (readingsJson == null || readingsJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(readingsJson);
      if (decoded is! Map) return;
      for (var entry in decoded.entries) {
        final key = entry.key;
        if (_estControllers.containsKey(key)) {
          final val = entry.value;
          if (val is num) {
            _estControllers[key]!.text = val.toStringAsFixed(1);
          }
        }
      }
    } catch (_) {
      // Keep grid blank if stored data is malformed.
    }
  }

  void _loadUvTrays(String? traysJson) {
    for (final tray in _uvTrays) {
      tray.dispose();
    }
    _uvTrays.clear();

    if (traysJson == null || traysJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(traysJson);
      if (decoded is! List) return;
      for (final item in decoded) {
        if (item is Map) {
          _uvTrays.add(_UvTray.fromMap(Map<String, dynamic>.from(item)));
        }
      }
    } catch (_) {
      // Keep a blank UV section if stored data is malformed.
    }
  }

  void _loadEggWeights(String? weightsJson) {
    if (weightsJson == null || weightsJson.trim().isEmpty) return;
    try {
      final decoded = jsonDecode(weightsJson);
      if (decoded is! List) return;
      for (
        var i = 0;
        i < decoded.length && i < _eggWeightControllers.length;
        i++
      ) {
        _eggWeightControllers[i].text = _formatNumber(decoded[i]);
      }
    } catch (_) {
      // Keep weight fields blank if stored data is malformed.
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _shellTempController.dispose();
    for (final controller in _estControllers.values) {
      controller.dispose();
    }
    _estAvgController.dispose();
    _estCvController.dispose();
    for (final tray in _uvTrays) {
      tray.dispose();
    }
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

    return UnsavedChangesGuard(
      child: Scaffold(
        appBar: widget.context.sessionId != null ? null : GradientAppBar(
          title: 'Egg Storage & Handling',
          actions: [
            if (auditProvider.isReadOnly)
              IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => auditProvider.setEditMode(true),
              ),
          ],
        ),
        body: SingleChildScrollView(
          controller: _scrollController,
          padding: const EdgeInsets.all(AppSizes.cardPadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              GoveeRecordingCard(
                key: _sectionKeys[0],
                place: TemperaturePlace.eggStorageRoom,
                auditSessionId: widget.context.sessionId ??
                    '${widget.context.customerId}_${widget.context.flockId}',
                label: 'Egg Storage Environment',
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'Shell Temperature',
                icon: Icons.thermostat_outlined,
                cardKey: _sectionKeys[1],
                child: _buildShellTemperatureSection(audit, auditProvider),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'Egg Shell Temperature Grid',
                icon: Icons.grid_on,
                cardKey: _sectionKeys[2],
                child: _buildEstGridSection(auditProvider),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'Egg Turning',
                icon: Icons.rotate_right,
                cardKey: _sectionKeys[3],
                child: _buildEggTurningSection(audit, auditProvider),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'UV Tray Inspection',
                icon: Icons.grid_on,
                cardKey: _sectionKeys[4],
                child: _buildUvTraySection(auditProvider),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'Egg Uniformity',
                icon: Icons.monitor_weight_outlined,
                cardKey: _sectionKeys[5],
                child: _buildEggUniformitySection(auditProvider),
              ),
              const SizedBox(height: 16),
              _buildSectionCard(
                title: 'Storage Checklist',
                icon: Icons.checklist,
                cardKey: _sectionKeys[6],
                child: _buildStorageChecklistSection(audit, auditProvider),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildShellTemperatureSection(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextField(
                controller: _shellTempController,
                enabled: !auditProvider.isReadOnly,
                keyboardType: const TextInputType.numberWithOptions(
                  decimal: true,
                ),
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(
                  labelText: 'Shell Temperature',
                  border: OutlineInputBorder(),
                  suffixText: '°C',
                ),
                inputFormatters: _decimalInputFormatters,
                onChanged: (value) => auditProvider.updateField(
                  'esShellTemp',
                  double.tryParse(value),
                ),
              ),
            ),
            const SizedBox(width: 8),
            PhotoButton(
              photoPath: audit.esShellTempPhoto,
              enabled: !auditProvider.isReadOnly,
              onPhotoCaptured: (path) =>
                  auditProvider.updateField('esShellTempPhoto', path),
            ),
          ],
        ),
        if (audit.esShellTemp != null) ...[
          const SizedBox(height: 12),
          _buildTempStatus(audit.esShellTemp!, isCelsius: true),
        ],
      ],
    );
  }

  Widget _buildEstGridSection(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        EstGridWidget(
          controllers: _estControllers,
          photos: _estPhotos,
          enabled: !auditProvider.isReadOnly,
          title: 'Shell Temperature Grid (°C) – Optimum: 19–21 °C',
          unitSuffix: '°C',
          tempStatusFn: CalculationUtils.shellTempStatus,
          tempZoneFn: CalculationUtils.shellTempZone,
          onValueChanged: (key, value) => _updateEstCalculations(auditProvider),
          onPhotoCaptured: (key, path) {
            setState(() => _estPhotos[key] = path);
          },
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: _summCard(
                'AVG',
                _estAvgController.text.isEmpty
                    ? '--'
                    : '${_estAvgController.text}°C',
                Colors.blue,
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _summCard(
                'CV%',
                _estCvController.text.isEmpty
                    ? '--'
                    : '${_estCvController.text}%',
                Colors.blueGrey,
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildEggTurningSection(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
    const options = <int, String>{
      0: 'No Turning',
      1: '1 time',
      2: '2 times',
      3: '3 times',
      4: '4 times',
      5: '5 times',
    };

    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: options.entries.map((entry) {
        final selected = audit.esTurningTimes == entry.key;
        return ChoiceChip(
          label: Text(entry.value),
          selected: selected,
          onSelected: auditProvider.isReadOnly
              ? null
              : (_) => auditProvider.updateField('esTurningTimes', entry.key),
          selectedColor: AppColors.primary.withAlpha(30),
          checkmarkColor: AppColors.primary,
          labelStyle: AppTextStyles.body.copyWith(
            color: selected ? AppColors.primary : Colors.black87,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? AppColors.primary : Colors.grey[300]!,
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildUvTraySection(AuditProvider auditProvider) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_uvTrays.isNotEmpty) ...[
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.blue[50],
              borderRadius: BorderRadius.circular(8),
            ),
            child: Text(
              'Overall Avg Affected: ${_calculateOverallAvgAffected().toStringAsFixed(1)}%',
              style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold),
            ),
          ),
          const SizedBox(height: 12),
        ],
        ..._uvTrays.asMap().entries.map(
          (entry) => _buildUvTrayCard(entry.key, entry.value, auditProvider),
        ),
        if (_uvTrays.length < 10 && !auditProvider.isReadOnly)
          ElevatedButton.icon(
            onPressed: () => setState(() => _uvTrays.add(_UvTray())),
            icon: const Icon(Icons.add),
            label: const Text('Add UV Tray'),
          ),
      ],
    );
  }

  Widget _buildEggUniformitySection(AuditProvider auditProvider) {
    final stats = _eggWeightStats();
    final enteredCount = stats?.sampleSize ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildUniformitySummary(),
        const SizedBox(height: 12),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            onPressed: () => _openEggWeightSheet(auditProvider),
            icon: const Icon(Icons.grid_on),
            label: Text(
              auditProvider.isReadOnly
                  ? 'View Egg Weight Sheet ($enteredCount/100)'
                  : 'Open Egg Weight Sheet ($enteredCount/100)',
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildStorageChecklistSection(
    AuditModel audit,
    AuditProvider auditProvider,
  ) {
    const orientations = ['Point Down', 'Point Up', 'Horizontal', 'Mixed'];
    const spacings = ['Adequate', 'Tight', 'Loose'];
    const proximities = ['Near', 'Far', 'Adjacent', 'Separate'];
    const wallProximities = ['Far', 'Near', 'Against'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildChoiceRow(
          label: 'Egg Orientation',
          options: orientations,
          selected: _eggOrientation,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            setState(() => _eggOrientation = v);
            auditProvider.updateField('es_eggOrientation', v);
          },
        ),
        const SizedBox(height: 12),
        _buildChoiceRow(
          label: 'Tray Spacing',
          options: spacings,
          selected: _traySpacing,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            setState(() => _traySpacing = v);
            auditProvider.updateField('es_traySpacing', v);
          },
        ),
        const SizedBox(height: 12),
        _buildChoiceRow(
          label: 'Cooler Proximity',
          options: proximities,
          selected: _coolerProximity,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            setState(() => _coolerProximity = v);
            auditProvider.updateField('es_coolerProximity', v);
          },
        ),
        const SizedBox(height: 12),
        _buildChoiceRow(
          label: 'Wall Proximity',
          options: wallProximities,
          selected: _wallProximity,
          enabled: !auditProvider.isReadOnly,
          onChanged: (v) {
            setState(() => _wallProximity = v);
            auditProvider.updateField('es_wallProximity', v);
          },
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Text('Condensation Present', style: AppTextStyles.body),
            ),
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment(value: false, label: Text('No')),
                ButtonSegment(value: true, label: Text('Yes')),
              ],
              selected: {_condensation ?? false},
              onSelectionChanged: auditProvider.isReadOnly
                  ? null
                  : (s) {
                      setState(() => _condensation = s.first);
                      auditProvider.updateField(
                        'es_condensation',
                        s.first ? 1 : 0,
                      );
                    },
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChoiceRow({
    required String label,
    required List<String> options,
    required String? selected,
    required bool enabled,
    required Function(String) onChanged,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.body.copyWith(fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: options.map((opt) {
            final isSelected = selected == opt;
            return ChoiceChip(
              label: Text(opt),
              selected: isSelected,
              onSelected: enabled ? (_) => onChanged(opt) : null,
              selectedColor: AppColors.primary.withAlpha(30),
              checkmarkColor: AppColors.primary,
              labelStyle: AppTextStyles.body.copyWith(
                color: isSelected ? AppColors.primary : Colors.black87,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
                side: BorderSide(
                  color: isSelected ? AppColors.primary : Colors.grey[300]!,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  void _scrollToInitialSection() {
    final index = widget.initialSectionIndex
        .clamp(0, _sectionKeys.length - 1)
        .toInt();
    final targetContext = _sectionKeys[index].currentContext;
    if (targetContext == null) return;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      alignment: 0.05,
    );
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required Widget child,
    Key? cardKey,
  }) {
    return Card(
      key: cardKey,
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: AppColors.primary, size: 20),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildTempStatus(double temp, {bool isCelsius = false}) {
    final status = isCelsius
        ? CalculationUtils.shellTempStatus(temp)
        : CalculationUtils.estStatus(temp);
    final color = status == TemperatureStatus.optimal
        ? AppColors.greenTab
        : status == TemperatureStatus.high
        ? Colors.red
        : Colors.orange;
    final label = isCelsius
        ? CalculationUtils.shellTempZone(temp)
        : CalculationUtils.estZone(temp);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Text(
        label,
        style: AppTextStyles.caption.copyWith(
          color: color,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildUvTrayCard(int index, _UvTray tray, AuditProvider provider) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey[300]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'Tray ${index + 1}',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              if (!provider.isReadOnly)
                IconButton(
                  tooltip: 'Delete tray',
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () => setState(() {
                    final removed = _uvTrays.removeAt(index);
                    removed.dispose();
                  }),
                ),
            ],
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: 120,
            child: TextField(
              controller: tray.totalEggsController,
              enabled: !provider.isReadOnly,
              keyboardType: TextInputType.number,
              textInputAction: TextInputAction.next,
              decoration: const InputDecoration(
                labelText: 'Total Eggs',
                border: OutlineInputBorder(),
              ),
              inputFormatters: _integerInputFormatters,
              onChanged: (value) => setState(() {
                tray.totalEggs = int.tryParse(value);
              }),
            ),
          ),
          const SizedBox(height: 12),
          _buildConditionCounter(
            label: 'Cuticle Damage',
            value: tray.cuticleDamage,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() => tray.cuticleDamage++),
            onDecrement: () => setState(() {
              if (tray.cuticleDamage > 0) tray.cuticleDamage--;
            }),
          ),
          const SizedBox(height: 6),
          _buildConditionCounter(
            label: 'Washed',
            value: tray.washed,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() => tray.washed++),
            onDecrement: () => setState(() {
              if (tray.washed > 0) tray.washed--;
            }),
          ),
          const SizedBox(height: 6),
          _buildConditionCounter(
            label: 'Dirty',
            value: tray.dirty,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() => tray.dirty++),
            onDecrement: () => setState(() {
              if (tray.dirty > 0) tray.dirty--;
            }),
          ),
          const SizedBox(height: 6),
          _buildConditionCounter(
            label: 'Upside Down',
            value: tray.upsideDown,
            enabled: !provider.isReadOnly,
            onIncrement: () => setState(() => tray.upsideDown++),
            onDecrement: () => setState(() {
              if (tray.upsideDown > 0) tray.upsideDown--;
            }),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: Text(
                  'Affected: ${tray.affectedCount} eggs (${tray.affectedPct.toStringAsFixed(1)}%)',
                  style: AppTextStyles.body.copyWith(
                    fontWeight: FontWeight.bold,
                    color: _getAffectedColor(tray.affectedPct),
                  ),
                ),
              ),
              PhotoButton(
                photoPath: tray.photoPath,
                enabled: !provider.isReadOnly,
                onPhotoCaptured: (path) => setState(() {
                  tray.photoPath = path;
                }),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildConditionCounter({
    required String label,
    required int value,
    required bool enabled,
    required VoidCallback onIncrement,
    required VoidCallback onDecrement,
  }) {
    return Row(
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w600),
        ),
        const Spacer(),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: enabled ? onDecrement : null,
            icon: const Icon(Icons.remove, size: 16),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: Colors.grey.shade100,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        Text(
          '$value',
          style: AppTextStyles.body.copyWith(
            fontWeight: FontWeight.w700,
            color: value > 0 ? AppColors.primary : AppTextStyles.caption.color,
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            onPressed: enabled ? onIncrement : null,
            icon: const Icon(Icons.add, size: 16),
            padding: EdgeInsets.zero,
            style: IconButton.styleFrom(
              backgroundColor: AppColors.infoBg,
              foregroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUniformitySummary() {
    final stats = _eggWeightStats();
    if (stats == null) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[100],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text('Enter egg weights', style: AppTextStyles.body),
      );
    }

    final cards = [
      _SummaryMetric('Samples', '${stats.sampleSize}/100', Colors.blueGrey),
      _SummaryMetric(
        'AVG Weight',
        '${stats.avg.toStringAsFixed(1)}g',
        Colors.blue,
      ),
      _SummaryMetric(
        'Min Range',
        '${stats.minRange.toStringAsFixed(1)}g',
        Colors.blueGrey,
      ),
      _SummaryMetric(
        'Max Range',
        '${stats.maxRange.toStringAsFixed(1)}g',
        Colors.blueGrey,
      ),
      _SummaryMetric(
        'Uniformity 10%',
        '${stats.uniformity.toStringAsFixed(1)}%',
        _uniformityColor(stats.uniformity),
      ),
      _SummaryMetric(
        'CV%',
        '${stats.cv.toStringAsFixed(1)}%',
        stats.cv <= AppThresholds.cvAlertPct ? AppColors.greenTab : Colors.red,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 700 ? 3 : 2;
        final spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: cards
              .map(
                (card) => SizedBox(
                  width: itemWidth,
                  child: _summCard(card.label, card.value, card.color),
                ),
              )
              .toList(),
        );
      },
    );
  }

  Future<void> _openEggWeightSheet(AuditProvider provider) async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return Padding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
              ),
              child: DraggableScrollableSheet(
                expand: false,
                initialChildSize: 0.9,
                minChildSize: 0.55,
                maxChildSize: 0.95,
                builder: (context, scrollController) {
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                'Egg Uniformity Entry',
                                style: AppTextStyles.heading.copyWith(
                                  fontSize: 18,
                                ),
                              ),
                            ),
                            IconButton(
                              tooltip: 'Close',
                              icon: const Icon(Icons.close),
                              onPressed: () => Navigator.pop(sheetContext),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: SingleChildScrollView(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                          child: Column(
                            children: [
                              WeightGridWidget(
                                controllers: _eggWeightControllers,
                                focusNodes: _eggWeightFocusNodes,
                                enabled: !provider.isReadOnly,
                                mode: WeightsMode.egg,
                                onChanged: () {
                                  _updateEggWeights(provider);
                                  setSheetState(() {});
                                },
                              ),
                              const SizedBox(height: 16),
                              _buildUniformitySummary(),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            );
          },
        );
      },
    );
  }

  Widget _summCard(String label, String value, Color color) => Container(
    padding: const EdgeInsets.all(10),
    decoration: BoxDecoration(
      color: color.withAlpha(25),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: color),
    ),
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label, style: AppTextStyles.caption, textAlign: TextAlign.center),
        const SizedBox(height: 4),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: Text(
            value,
            maxLines: 1,
            style: AppTextStyles.body.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ),
      ],
    ),
  );

  double _calculateOverallAvgAffected() => _uvTrays.isEmpty
      ? 0.0
      : _uvTrays.map((t) => t.affectedPct).reduce((a, b) => a + b) /
            _uvTrays.length;

  Color _uniformityColor(double uniformity) {
    if (uniformity < AppThresholds.uniformityPoor) return Colors.red;
    if (uniformity <= AppThresholds.uniformityGood) return Colors.orange;
    return AppColors.greenTab;
  }

  Color _getAffectedColor(double pct) => pct <= 5
      ? AppColors.greenTab
      : pct <= 10
      ? Colors.orange
      : Colors.red;

  void _updateEstCalculations(AuditProvider provider) {
    final temps = _estControllers.values
        .map((c) => double.tryParse(c.text))
        .where((t) => t != null)
        .map((t) => t!)
        .toList();
    if (temps.isEmpty) {
      setState(() {
        _estAvgController.text = '';
        _estCvController.text = '';
      });
      provider.updateField('es_estAvg', null);
      provider.updateField('es_estCv', null);
    } else {
      final avg = CalculationUtils.average(temps);
      final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;
      setState(() {
        _estAvgController.text = avg.toStringAsFixed(1);
        _estCvController.text = cv.toStringAsFixed(1);
      });
      provider.updateField('es_estAvg', avg);
      provider.updateField('es_estCv', cv);
    }
    final readings = _estControllers.map((key, value) {
      return MapEntry(key, double.tryParse(value.text));
    });
    provider.updateField('es_estReadingsJson', jsonEncode(readings));
  }

  void _updateEggWeights(AuditProvider provider) {
    final allWeights = _eggWeightControllers
        .map((controller) => double.tryParse(controller.text))
        .toList();
    final weights = allWeights.whereType<double>().where((w) => w > 0).toList();

    provider.updateField('esEggWeights', jsonEncode(allWeights));
    provider.updateField('esEggSampleSize', weights.length);

    if (weights.isEmpty) {
      provider.updateField('esEggAvgWeight', null);
      provider.updateField('esEggUniformityPct', null);
      provider.updateField('esEggCvPct', null);
      if (mounted) setState(() {});
      return;
    }

    final avg = CalculationUtils.average(weights);
    final minRange = avg * 0.9;
    final maxRange = avg * 1.1;
    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      minRange,
      maxRange,
    );
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;

    provider.updateField('esEggAvgWeight', avg);
    provider.updateField('esEggUniformityPct', uniformity);
    provider.updateField('esEggCvPct', cv);
    if (mounted) setState(() {});
  }

  _EggWeightStats? _eggWeightStats() {
    final weights = _eggWeightControllers
        .map((controller) => double.tryParse(controller.text))
        .whereType<double>()
        .where((weight) => weight > 0)
        .toList();
    if (weights.isEmpty) return null;

    final avg = CalculationUtils.average(weights);
    final minRange = avg * 0.9;
    final maxRange = avg * 1.1;
    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      minRange,
      maxRange,
    );
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;

    return _EggWeightStats(
      sampleSize: weights.length,
      avg: avg,
      minRange: minRange,
      maxRange: maxRange,
      uniformity: uniformity,
      cv: cv,
    );
  }

  String _formatNumber(Object? value) {
    final parsed = value is num
        ? value.toDouble()
        : double.tryParse(value?.toString() ?? '');
    if (parsed == null) return '';
    if (parsed == parsed.roundToDouble()) return parsed.toStringAsFixed(0);
    return parsed.toString();
  }
}

class _UvTray {
  int? totalEggs;
  int cuticleDamage = 0;
  int washed = 0;
  int dirty = 0;
  int upsideDown = 0;
  String? photoPath;
  late final TextEditingController totalEggsController;

  int get affectedCount => cuticleDamage + washed + dirty + upsideDown;

  _UvTray({
    this.totalEggs = 150,
    this.cuticleDamage = 0,
    this.washed = 0,
    this.dirty = 0,
    this.upsideDown = 0,
    this.photoPath,
  }) {
    totalEggsController = TextEditingController(
      text: totalEggs?.toString() ?? '',
    );
  }

  factory _UvTray.fromMap(Map<String, dynamic> map) {
    return _UvTray(
      totalEggs: _parseInt(map['totalEggs']),
      cuticleDamage: _parseInt(map['cuticleDamage']) ?? 0,
      washed: _parseInt(map['washed']) ?? 0,
      dirty: _parseInt(map['dirty']) ?? 0,
      upsideDown: _parseInt(map['upsideDown']) ?? 0,
      photoPath: map['photoPath'] as String?,
    );
  }

  double get affectedPct => totalEggs == null || totalEggs == 0
      ? 0.0
      : affectedCount / totalEggs! * 100;

  Map<String, dynamic> toMap() => {
    'totalEggs': totalEggs,
    'cuticleDamage': cuticleDamage,
    'washed': washed,
    'dirty': dirty,
    'upsideDown': upsideDown,
    'photoPath': photoPath,
  };

  void dispose() {
    totalEggsController.dispose();
  }

  static int? _parseInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }
}

class _EggWeightStats {
  final int sampleSize;
  final double avg;
  final double minRange;
  final double maxRange;
  final double uniformity;
  final double cv;

  const _EggWeightStats({
    required this.sampleSize,
    required this.avg,
    required this.minRange,
    required this.maxRange,
    required this.uniformity,
    required this.cv,
  });
}

class _SummaryMetric {
  final String label;
  final String value;
  final Color color;

  const _SummaryMetric(this.label, this.value, this.color);
}
