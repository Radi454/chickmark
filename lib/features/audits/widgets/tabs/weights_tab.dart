import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_thresholds.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../data/models/audit_model.dart';
import '../weight_grid_widget.dart';

class WeightsTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final VoidCallback onSave;

  const WeightsTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    required this.onSave,
  });

  @override
  State<WeightsTab> createState() => _WeightsTabState();
}

class _WeightsTabState extends State<WeightsTab> {
  final List<TextEditingController> _controllers = [];
  final List<FocusNode> _focusNodes = [];

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    for (var i = 0; i < 100; i++) {
      _controllers.add(TextEditingController());
      _focusNodes.add(FocusNode());
    }

    final weightsJson = widget.audit.chickWeights;
    if (weightsJson != null && weightsJson.isNotEmpty) {
      try {
        final List<dynamic> weights = jsonDecode(weightsJson);
        for (var i = 0; i < weights.length && i < 100; i++) {
          _controllers[i].text = weights[i]?.toString() ?? '';
        }
      } catch (e) {
        // ignore parse errors
      }
    }
  }

  void _updateCalculations() {
    final weights = _controllers
        .map((c) => double.tryParse(c.text))
        .where((w) => w != null && w > 0)
        .map((w) => w!)
        .toList();

    if (weights.isEmpty) return;

    final avg = CalculationUtils.average(weights);
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;

    final minRange = avg * 0.9;
    final maxRange = avg * 1.1;
    final uniformity = CalculationUtils.uniformityPercent(
      weights,
      minRange,
      maxRange,
    );

    widget.onFieldChanged('chickWeights', jsonEncode(weights));
    widget.onFieldChanged('chickAvgWeight', avg);
    widget.onFieldChanged('chickUniformityPct', uniformity);
    widget.onFieldChanged('chickCvPct', cv);
  }

  @override
  Widget build(BuildContext context) {
    final weights = _controllers
        .map((c) => double.tryParse(c.text))
        .where((w) => w != null && w > 0)
        .map((w) => w!)
        .toList();

    final avg = weights.isEmpty ? 0.0 : CalculationUtils.average(weights);
    final cv = weights.length > 1 ? CalculationUtils.cvPercent(weights) : 0.0;
    final minRange = avg * 0.9;
    final maxRange = avg * 1.1;
    final uniformity = weights.isEmpty
        ? 0.0
        : CalculationUtils.uniformityPercent(weights, minRange, maxRange);

    return SingleChildScrollView(
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.scale, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Chick Weights',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: TextEditingController(
                      text: widget.audit.chickStorageDays?.toString() ?? '',
                    ),
                    enabled: !widget.isReadOnly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Storage Days',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      widget.onFieldChanged(
                        'chickStorageDays',
                        int.tryParse(value) ?? 0,
                      );
                    },
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          WeightGridWidget(
            controllers: _controllers,
            focusNodes: _focusNodes,
            enabled: !widget.isReadOnly,
            onChanged: _updateCalculations,
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'AVG',
                  '${avg.toStringAsFixed(1)}g',
                  Colors.blue,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildSummaryCard(
                  'CV%',
                  '${cv.toStringAsFixed(1)}%',
                  cv <= AppThresholds.cvAlertPct
                      ? AppColors.greenTab
                      : Colors.red,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildSummaryCard(
                  'Uniformity',
                  '${uniformity.toStringAsFixed(1)}%',
                  uniformity >= AppThresholds.uniformityGood
                      ? AppColors.greenTab
                      : Colors.red,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildSummaryCard(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: color),
      ),
      child: Column(
        children: [
          Text(label, style: AppTextStyles.caption),
          const SizedBox(height: 4),
          Text(value, style: AppTextStyles.heading.copyWith(color: color)),
        ],
      ),
    );
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    for (var node in _focusNodes) {
      node.dispose();
    }
    super.dispose();
  }
}
