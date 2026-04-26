import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_thresholds.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../core/utils/temp_converter.dart';
import '../../../../data/models/audit_model.dart';
import '../../../../providers/app_provider.dart';
import '../photo_button.dart';

class CvtTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;

  const CvtTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
  });

  @override
  State<CvtTab> createState() => _CvtTabState();
}

class _CvtTabState extends State<CvtTab> {
  final List<TextEditingController> _tempControllers = [];
  final List<TextEditingController> _basketControllers = [];
  final List<String?> _photoPaths = [];
  final TextEditingController _sampleSizeController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _initializeControllers();
  }

  void _initializeControllers() {
    for (var i = 0; i < 3; i++) {
      _tempControllers.add(TextEditingController());
      _basketControllers.add(TextEditingController());
      _photoPaths.add(null);
    }

    _sampleSizeController.text = widget.audit.cvtSampleSize?.toString() ?? '3';

    _basketControllers[0].text = widget.audit.cvtTopBasket ?? '';
    _basketControllers[1].text = widget.audit.cvtMiddleBasket ?? '';
    _basketControllers[2].text = widget.audit.cvtBottomBasket ?? '';

    _tempControllers[0].text = widget.audit.cvtTopTemp?.toString() ?? '';
    _tempControllers[1].text = widget.audit.cvtMiddleTemp?.toString() ?? '';
    _tempControllers[2].text = widget.audit.cvtBottomTemp?.toString() ?? '';

    _photoPaths[0] = widget.audit.cvtTopPhoto;
    _photoPaths[1] = widget.audit.cvtMiddlePhoto;
    _photoPaths[2] = widget.audit.cvtBottomPhoto;
  }

  void _updateCalculations() {
    final temps = _tempControllers
        .map((c) => double.tryParse(c.text))
        .where((t) => t != null)
        .map((t) => t!)
        .toList();

    if (temps.isEmpty) return;

    final avg = CalculationUtils.average(temps);
    final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;

    widget.onFieldChanged('cvtAvg', avg);
    widget.onFieldChanged('cvtCvPct', cv);
  }

  @override
  Widget build(BuildContext context) {
    final appProvider = context.watch<AppProvider>();
    final showCelsius = appProvider.tempUnit == TempUnit.celsius;

    final temps = _tempControllers
        .map((c) => double.tryParse(c.text))
        .where((t) => t != null)
        .map((t) => t!)
        .toList();

    final avg = temps.isEmpty ? 0.0 : CalculationUtils.average(temps);
    final cv = temps.length > 1 ? CalculationUtils.cvPercent(temps) : 0.0;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: _buildStatCard(
                  'AVG Temp',
                  showCelsius
                      ? TempConverter.display(avg, showCelsius: true)
                      : '${avg.toStringAsFixed(1)}°F',
                  avg >= AppThresholds.cvtMin && avg <= AppThresholds.cvtMax,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildStatCard(
                  'CV %',
                  '${cv.toStringAsFixed(1)}%',
                  cv <= AppThresholds.cvAlertPct,
                ),
              ),
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
                      labelText: 'Number of baskets',
                    ),
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                    onChanged: (v) => widget.onFieldChanged(
                      'cvtSampleSize',
                      int.tryParse(v) ?? 3,
                    ),
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
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        'CVT Measurements',
                        style: AppTextStyles.body.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        'Optimum: 103-105°F',
                        style: AppTextStyles.caption.copyWith(
                          color: AppColors.greenTab,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),
                  Table(
                    border: TableBorder.all(color: Colors.grey[300]!, width: 1),
                    columnWidths: const {
                      0: FixedColumnWidth(80),
                      1: FlexColumnWidth(),
                      2: FlexColumnWidth(),
                      3: FixedColumnWidth(60),
                      4: FixedColumnWidth(50),
                    },
                    children: [
                      TableRow(
                        decoration: BoxDecoration(color: Colors.grey[100]),
                        children: [
                          _cell('Position', isHeader: true),
                          _cell('Basket', isHeader: true),
                          _cell('Temp', isHeader: true),
                          _cell('Status', isHeader: true),
                          _cell('', isHeader: true),
                        ],
                      ),
                      ...List.generate(3, (index) {
                        final positions = ['Top', 'Middle', 'Bottom'];
                        final temp = double.tryParse(
                          _tempControllers[index].text,
                        );
                        final isGood =
                            temp != null &&
                            temp >= AppThresholds.cvtMin &&
                            temp <= AppThresholds.cvtMax;
                        return TableRow(
                          children: [
                            _cell(positions[index]),
                            _textCell(_basketControllers[index], (v) {
                              final baskets = [
                                'cvtTopBasket',
                                'cvtMiddleBasket',
                                'cvtBottomBasket',
                              ];
                              widget.onFieldChanged(baskets[index], v);
                            }),
                            _textCell(_tempControllers[index], (v) {
                              final temps = [
                                'cvtTopTemp',
                                'cvtMiddleTemp',
                                'cvtBottomTemp',
                              ];
                              widget.onFieldChanged(
                                temps[index],
                                double.tryParse(v),
                              );
                              _updateCalculations();
                            }, numeric: true),
                            _cell(
                              temp == null ? '--' : (isGood ? 'OK' : 'Alert'),
                              textColor: temp == null
                                  ? Colors.grey
                                  : (isGood ? AppColors.greenTab : Colors.red),
                            ),
                            _photoCell(index),
                          ],
                        );
                      }),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, bool isGood) {
    final color = isGood ? AppColors.greenTab : Colors.red;
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
          Text(
            value,
            style: AppTextStyles.heading.copyWith(fontSize: 24, color: color),
          ),
        ],
      ),
    );
  }

  Widget _cell(String text, {bool isHeader = false, Color? textColor}) {
    return Padding(
      padding: const EdgeInsets.all(8),
      child: Text(
        text,
        style: AppTextStyles.body.copyWith(
          fontWeight: isHeader ? FontWeight.w600 : null,
          color: textColor,
        ),
        textAlign: TextAlign.center,
      ),
    );
  }

  Widget _textCell(
    TextEditingController controller,
    Function(String) onChanged, {
    bool numeric = false,
  }) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextField(
        controller: controller,
        enabled: !widget.isReadOnly,
        keyboardType: numeric
            ? const TextInputType.numberWithOptions(decimal: true)
            : TextInputType.text,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
        inputFormatters: numeric
            ? [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d{0,1}'))]
            : null,
        onChanged: onChanged,
      ),
    );
  }

  Widget _photoCell(int index) {
    return PhotoButton(
      photoPath: _photoPaths[index],
      enabled: !widget.isReadOnly,
      onPhotoCaptured: (path) {
        setState(() => _photoPaths[index] = path);
        final photos = ['cvtTopPhoto', 'cvtMiddlePhoto', 'cvtBottomPhoto'];
        widget.onFieldChanged(photos[index], path);
      },
    );
  }

  @override
  void dispose() {
    for (var c in _tempControllers) {
      c.dispose();
    }
    for (var c in _basketControllers) {
      c.dispose();
    }
    _sampleSizeController.dispose();
    super.dispose();
  }
}
