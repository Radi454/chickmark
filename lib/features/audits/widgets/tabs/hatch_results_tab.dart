import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../data/models/audit_model.dart';

class HatchResultsTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final VoidCallback onSave;
  const HatchResultsTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    required this.onSave,
  });
  @override
  State<HatchResultsTab> createState() => _HatchResultsTabState();
}

class _HatchResultsTabState extends State<HatchResultsTab> {
  final _totalEggsController = TextEditingController();
  final _hatchedController = TextEditingController();
  final _culledController = TextEditingController();
  final _deadController = TextEditingController();
  final _storageDaysController = TextEditingController();
  final _fertilityController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _totalEggsController.text = widget.audit.haTotalEggsSet?.toString() ?? '';
    _hatchedController.text = widget.audit.haHatched?.toString() ?? '';
    _culledController.text = widget.audit.haCulled?.toString() ?? '';
    _deadController.text = widget.audit.haDead?.toString() ?? '';
    _storageDaysController.text = widget.audit.haStorageDays?.toString() ?? '';
    _fertilityController.text = widget.audit.haFertility?.toString() ?? '';
  }

  @override
  Widget build(BuildContext context) {
    final totalEggs = int.tryParse(_totalEggsController.text) ?? 0;
    final hatched = int.tryParse(_hatchedController.text) ?? 0;
    final hatchability = CalculationUtils.hatchability(hatched, totalEggs);
    final fertility = double.tryParse(_fertilityController.text) ?? 0.0;
    final hof = CalculationUtils.hof(hatchability, fertility);
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
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: _numberField(
                          'Total Eggs Set',
                          _totalEggsController,
                          'haTotalEggsSet',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _numberField(
                          'Hatched',
                          _hatchedController,
                          'haHatched',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _numberField(
                          'Culled',
                          _culledController,
                          'haCulled',
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _numberField('Dead', _deadController, 'haDead'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: _statCard(
                  'Hatchability',
                  '${hatchability.toStringAsFixed(1)}%',
                  hatchability >= 80,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  'HOF',
                  '${hof.toStringAsFixed(1)}%',
                  fertility > 0 ? hof >= 85 : null,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _statCard(
                  'Storage Days',
                  _storageDaysController.text,
                  null,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Storage Days',
              border: OutlineInputBorder(),
            ),
            controller: _storageDaysController,
            onChanged: (v) =>
                widget.onFieldChanged('haStorageDays', int.tryParse(v)),
          ),
          const SizedBox(height: 16),
          TextField(
            decoration: const InputDecoration(
              labelText: 'Average Tray Fertility (%)',
              border: OutlineInputBorder(),
            ),
            controller: _fertilityController,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            onChanged: (v) {
              setState(() {});
              _persistCalculations();
            },
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    String label,
    TextEditingController controller,
    String field,
  ) => TextField(
    controller: controller,
    enabled: !widget.isReadOnly,
    keyboardType: TextInputType.number,
    decoration: InputDecoration(
      labelText: label,
      border: const OutlineInputBorder(),
    ),
    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
    onChanged: (v) {
      setState(() {});
      widget.onFieldChanged(field, int.tryParse(v));
      _persistCalculations();
    },
  );

  void _persistCalculations() {
    final totalEggs = int.tryParse(_totalEggsController.text) ?? 0;
    final hatched = int.tryParse(_hatchedController.text) ?? 0;
    final hatchability = CalculationUtils.hatchability(hatched, totalEggs);
    final fertility = double.tryParse(_fertilityController.text) ?? 0.0;
    widget.onFieldChanged('haHatchability', hatchability);
    widget.onFieldChanged('haFertility', fertility);
    widget.onFieldChanged('haHof', CalculationUtils.hof(hatchability, fertility));
  }
  Widget _statCard(String label, String value, bool? isGood) {
    final color = isGood == null
        ? Colors.grey[100]
        : (isGood ? AppColors.greenTab : Colors.red);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color?.withAlpha(25),
        borderRadius: BorderRadius.circular(8),
        border: isGood != null ? Border.all(color: color!) : null,
      ),
      child: Column(
        children: [
          Text(label, style: AppTextStyles.caption),
          Text(
            value,
            style: AppTextStyles.heading.copyWith(
              color: isGood != null ? color : null,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    _totalEggsController.dispose();
    _hatchedController.dispose();
    _culledController.dispose();
    _deadController.dispose();
    _storageDaysController.dispose();
    _fertilityController.dispose();
    super.dispose();
  }
}
