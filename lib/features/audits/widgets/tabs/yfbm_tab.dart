import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_thresholds.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../data/models/audit_model.dart';
import '../audit_numeric_keyboard.dart';
import '../photo_button.dart';

class YfbmTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;

  const YfbmTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
  });

  @override
  State<YfbmTab> createState() => _YfbmTabState();
}

class _YfbmTabState extends State<YfbmTab> {
  static const String _tableNavigationGroup = 'yfbm-table';

  final List<_EntryData> _entries = [];
  final TextEditingController _avgPercentController = TextEditingController();
  final TextEditingController _cvPercentController = TextEditingController();
  String? _photoPath;

  @override
  void initState() {
    super.initState();
    _initializeEntries();
  }

  void _initializeEntries() {
    final entriesJson = widget.audit.yfbmEntries;
    if (entriesJson != null && entriesJson.isNotEmpty) {
      try {
        final List<dynamic> entriesList = jsonDecode(entriesJson);
        for (var entry in entriesList) {
          _entries.add(
            _EntryData(
              chickWeight: entry['chickWeight']?.toDouble(),
              yolkWeight: entry['yolkWeight']?.toDouble(),
            ),
          );
        }
      } catch (e) {
        // ignore
      }
    }

    _photoPath = widget.audit.yfbmPhoto;

    if (_entries.isEmpty) {
      for (var i = 0; i < 10; i++) {
        _entries.add(_EntryData());
      }
    }
    _updateCalculations();
  }

  void _updateCalculations() {
    final percentages = _entries
        .where(
          (e) =>
              e.chickWeight != null &&
              e.yolkWeight != null &&
              e.chickWeight! > 0,
        )
        .map((e) => (e.yolkWeight! / e.chickWeight!) * 100)
        .toList();

    if (percentages.isEmpty) {
      _avgPercentController.text = '';
      _cvPercentController.text = '';
      return;
    }

    final avg = CalculationUtils.average(percentages);
    final cv = percentages.length > 1
        ? CalculationUtils.cvPercent(percentages)
        : 0.0;

    _avgPercentController.text = avg.toStringAsFixed(1);
    _cvPercentController.text = cv.toStringAsFixed(1);

    final entriesList = _entries
        .where((e) => e.chickWeight != null && e.yolkWeight != null)
        .map((e) => e.toMap())
        .toList();
    widget.onFieldChanged('yfbmEntries', jsonEncode(entriesList));
    widget.onFieldChanged('yfbmAvgPct', avg);
    widget.onFieldChanged('yfbmCvPct', cv);
  }

  void _addEntry() {
    setState(() {
      _entries.add(_EntryData());
    });
  }

  void _removeEntry(int index) {
    setState(() {
      _entries.removeAt(index);
      _updateCalculations();
    });
  }

  void _updateEntry(int index, String field, double? value) {
    setState(() {
      if (field == 'chickWeight') {
        _entries[index].chickWeight = value;
      } else {
        _entries[index].yolkWeight = value;
      }
      _updateCalculations();
    });
  }

  @override
  Widget build(BuildContext context) {
    return AuditNumericKeyboardScope(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(child: _buildStatCard('AVG %', _avgPercentController)),
                const SizedBox(width: 8),
                Expanded(child: _buildStatCard('CV %', _cvPercentController)),
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
                        Icon(
                          Icons.photo_camera,
                          color: AppColors.primary,
                          size: 20,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Photo',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    PhotoButton(
                      photoPath: _photoPath,
                      enabled: !widget.isReadOnly,
                      onPhotoCaptured: (path) {
                        setState(() => _photoPath = path);
                        widget.onFieldChanged('yfbmPhoto', path);
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
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'YFBM Entries',
                          style: AppTextStyles.body.copyWith(
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (!widget.isReadOnly)
                          ElevatedButton.icon(
                            onPressed: _addEntry,
                            icon: const Icon(Icons.add, size: 18),
                            label: const Text('Add Row'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: AppColors.primary,
                              foregroundColor: Colors.white,
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Table(
                      border: TableBorder.all(
                        color: Colors.grey[300]!,
                        width: 1,
                      ),
                      columnWidths: const {
                        0: FixedColumnWidth(40),
                        1: FlexColumnWidth(),
                        2: FlexColumnWidth(),
                        3: FixedColumnWidth(80),
                        4: FixedColumnWidth(50),
                      },
                      children: [
                        TableRow(
                          decoration: BoxDecoration(color: Colors.grey[100]),
                          children: [
                            _cell('#', isHeader: true),
                            _cell('Chick (g)', isHeader: true),
                            _cell('Yolk (g)', isHeader: true),
                            _cell('%', isHeader: true),
                            _cell('', isHeader: true),
                          ],
                        ),
                        ...List.generate(_entries.length, (index) {
                          final entry = _entries[index];
                          final pct =
                              entry.chickWeight != null &&
                                  entry.yolkWeight != null &&
                                  entry.chickWeight! > 0
                              ? (entry.yolkWeight! / entry.chickWeight!) * 100
                              : null;
                          final isGood =
                              pct != null &&
                              pct >= AppThresholds.yfbmMin &&
                              pct <= AppThresholds.yfbmMax;
                          return TableRow(
                            children: [
                              _cell('${index + 1}'),
                              _weightCell(
                                entry.chickWeight,
                                (v) => _updateEntry(index, 'chickWeight', v),
                                row: index,
                                column: 0,
                              ),
                              _weightCell(
                                entry.yolkWeight,
                                (v) => _updateEntry(index, 'yolkWeight', v),
                                row: index,
                                column: 1,
                              ),
                              _cell(
                                pct?.toStringAsFixed(1) ?? '--',
                                textColor: isGood
                                    ? AppColors.greenTab
                                    : Colors.red,
                              ),
                              widget.isReadOnly
                                  ? _cell('')
                                  : _deleteCell(index),
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
      ),
    );
  }

  Widget _buildStatCard(String label, TextEditingController controller) {
    final value = double.tryParse(controller.text) ?? 0.0;
    final isGood = label.contains('AVG')
        ? value >= AppThresholds.yfbmMin && value <= AppThresholds.yfbmMax
        : value <= AppThresholds.cvAlertPct;
    final color = label.contains('AVG')
        ? (isGood ? AppColors.greenTab : Colors.red)
        : (isGood ? AppColors.greenTab : Colors.red);
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
            controller.text,
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

  Widget _weightCell(
    double? value,
    Function(double?) onChanged, {
    required int row,
    required int column,
  }) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: AuditNumericField(
        enabled: !widget.isReadOnly,
        controller: TextEditingController(text: value?.toString() ?? ''),
        allowDecimal: true,
        maxDecimalPlaces: 1,
        navigationGroup: _tableNavigationGroup,
        navigationRow: row,
        navigationColumn: column,
        textAlign: TextAlign.center,
        decoration: const InputDecoration(
          border: InputBorder.none,
          isDense: true,
        ),
        onChanged: (v) => onChanged(double.tryParse(v)),
      ),
    );
  }

  Widget _deleteCell(int index) {
    return IconButton(
      icon: const Icon(Icons.delete_outline, color: Colors.red, size: 20),
      onPressed: () => _removeEntry(index),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(),
    );
  }

  @override
  void dispose() {
    _avgPercentController.dispose();
    _cvPercentController.dispose();
    super.dispose();
  }
}

class _EntryData {
  double? chickWeight;
  double? yolkWeight;
  _EntryData({this.chickWeight, this.yolkWeight});
  Map<String, dynamic> toMap() => {
    'chickWeight': chickWeight,
    'yolkWeight': yolkWeight,
  };
}
