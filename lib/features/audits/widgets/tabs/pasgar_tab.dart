import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../data/models/audit_model.dart';

class PasgarTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final VoidCallback onSave;

  const PasgarTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    required this.onSave,
  });

  @override
  State<PasgarTab> createState() => _PasgarTabState();
}

class _PasgarTabState extends State<PasgarTab> {
  final List<TextEditingController> _controllers = [];
  final TextEditingController _sampleSizeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    _sampleSizeController.text =
        widget.audit.pasgarSampleSize?.toString() ?? '100';

    final defectCounts = [
      widget.audit.pasgarReflexes ?? 0,
      widget.audit.pasgarBeak ?? 0,
      widget.audit.pasgarNavel ?? 0,
      widget.audit.pasgarBelly ?? 0,
      widget.audit.pasgarLeg ?? 0,
      widget.audit.pasgarFeatherDev ?? 0,
    ];

    for (var i = 0; i < 6; i++) {
      _controllers.add(TextEditingController(text: defectCounts[i].toString()));
    }
  }

  @override
  Widget build(BuildContext context) {
    final sampleSize = int.tryParse(_sampleSizeController.text) ?? 0;
    final defectCounts = _controllers
        .map((c) => int.tryParse(c.text) ?? 0)
        .toList();

    final pasgarScore = CalculationUtils.pasgarScore(
      sampleSize,
      defectCounts.take(5).toList(),
    );

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
                      Icon(Icons.numbers, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Sample Size',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _sampleSizeController,
                    enabled: !widget.isReadOnly,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Number of chicks sampled',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (value) {
                      setState(() {});
                      widget.onFieldChanged(
                        'pasgarSampleSize',
                        int.tryParse(value) ?? 0,
                      );
                      _persistScore();
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
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.warning, color: AppColors.primary, size: 20),
                      const SizedBox(width: 8),
                      Text(
                        'Defect Counts',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildDefectInput(0, 'Reflexes', Icons.accessibility_new),
                  const SizedBox(height: 12),
                  _buildDefectInput(1, 'Beak', Icons.pets),
                  const SizedBox(height: 12),
                  _buildDefectInput(2, 'Navel', Icons.healing),
                  const SizedBox(height: 12),
                  _buildDefectInput(3, 'Belly', Icons.circle_outlined),
                  const SizedBox(height: 12),
                  _buildDefectInput(4, 'Leg', Icons.directions_walk),
                  const SizedBox(height: 12),
                  _buildDefectInput(5, 'Feather Dev', Icons.air),
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
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'PASGAR Score',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        pasgarScore.toStringAsFixed(1),
                        style: AppTextStyles.heading.copyWith(
                          fontSize: 32,
                          color: pasgarScore >= 95
                              ? AppColors.greenTab
                              : pasgarScore >= 90
                              ? Colors.orange
                              : Colors.red,
                        ),
                      ),
                    ],
                  ),
                  Icon(
                    Icons.assessment,
                    size: 48,
                    color: pasgarScore >= 95
                        ? AppColors.greenTab
                        : pasgarScore >= 90
                        ? Colors.orange
                        : Colors.red,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDefectInput(int index, String label, IconData icon) {
    return Row(
      children: [
        Icon(icon, color: AppColors.primary, size: 20),
        const SizedBox(width: 8),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label, style: AppTextStyles.body),
              Text(
                _defectPercent(index),
                style: AppTextStyles.caption.copyWith(
                  color: _isDefectAlert(index) ? Colors.red : Colors.grey,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 80,
          child: TextField(
            controller: _controllers[index],
            enabled: !widget.isReadOnly,
            keyboardType: TextInputType.number,
            textAlign: TextAlign.center,
            decoration: const InputDecoration(
              border: OutlineInputBorder(),
              isDense: true,
            ),
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            onChanged: (value) {
              _updateDefectCount(index, value);
            },
          ),
        ),
      ],
    );
  }

  void _updateDefectCount(int index, String value) {
    final count = int.tryParse(value) ?? 0;
    final fieldNames = [
      'pasgarReflexes',
      'pasgarBeak',
      'pasgarNavel',
      'pasgarBelly',
      'pasgarLeg',
      'pasgarFeatherDev',
    ];
    setState(() {});
    widget.onFieldChanged(fieldNames[index], count);
    _persistScore();
  }

  void _persistScore() {
    final sampleSize = int.tryParse(_sampleSizeController.text) ?? 0;
    final scoredDefects = _controllers
        .take(5)
        .map((c) => int.tryParse(c.text) ?? 0)
        .toList();
    widget.onFieldChanged(
      'pasgarFinalScore',
      CalculationUtils.pasgarScore(sampleSize, scoredDefects),
    );
  }

  String _defectPercent(int index) {
    final sampleSize = int.tryParse(_sampleSizeController.text) ?? 0;
    if (sampleSize <= 0) return '0.0%';
    final count = int.tryParse(_controllers[index].text) ?? 0;
    return '${((count / sampleSize) * 100).toStringAsFixed(1)}%';
  }

  bool _isDefectAlert(int index) {
    final sampleSize = int.tryParse(_sampleSizeController.text) ?? 0;
    if (sampleSize <= 0) return false;
    final count = int.tryParse(_controllers[index].text) ?? 0;
    return (count / sampleSize) * 100 > 20;
  }

  @override
  void dispose() {
    for (var controller in _controllers) {
      controller.dispose();
    }
    _sampleSizeController.dispose();
    super.dispose();
  }
}
