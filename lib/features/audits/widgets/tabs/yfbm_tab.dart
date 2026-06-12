import 'dart:convert';
import 'package:flutter/material.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/constants/app_thresholds.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../core/utils/calculation_utils.dart';
import '../../../../data/models/audit_model.dart';
import '../audit_keyboard_dismiss.dart';
import '../audit_numeric_keyboard.dart';
import '../photo_button.dart';

class YfbmTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final bool embedded;

  const YfbmTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    this.embedded = false,
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
        .map((e) => CalculationUtils.percentOf(e.yolkWeight, e.chickWeight))
        .whereType<double>()
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
      _entries.removeAt(index).dispose();
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

  Future<void> _openEntriesSheet() async {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            void refreshSheet() => setSheetState(() {});

            return AuditKeyboardDismiss(
              child: AuditNumericKeyboardScope(
                child: Padding(
                  padding: EdgeInsets.only(
                    bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
                  ),
                  child: DraggableScrollableSheet(
                    expand: false,
                    initialChildSize: 0.9,
                    minChildSize: 0.56,
                    maxChildSize: 0.96,
                    builder: (context, scrollController) {
                      return Container(
                        key: const ValueKey('yfbm-entries-sheet'),
                        clipBehavior: Clip.antiAlias,
                        decoration: const BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.vertical(
                            top: Radius.circular(22),
                          ),
                        ),
                        child: Column(
                          children: [
                            _buildSheetHeader(sheetContext, refreshSheet),
                            Expanded(
                              child: _buildEntriesList(
                                scrollController,
                                refreshSheet,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildSummaryGrid(),
        const SizedBox(height: 16),
        Container(
          padding: const EdgeInsets.all(AppSizes.cardPadding),
          decoration: BoxDecoration(
            color: AppColors.surfaceRaised,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Icon(Icons.photo_camera, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Photo',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              PhotoButton(
                photoPath: _photoPath,
                enabled: !widget.isReadOnly,
                fieldKey: 'yfbm_photo',
                onPhotoCaptured: (path) {
                  setState(() => _photoPath = path);
                  widget.onFieldChanged('yfbmPhoto', path);
                },
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        _buildEntriesLauncher(),
      ],
    );

    if (widget.embedded) return AuditNumericKeyboardScope(child: content);

    return AuditNumericKeyboardScope(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSizes.cardPadding),
        child: content,
      ),
    );
  }

  Widget _buildEntriesLauncher() {
    final completedRows = _entries
        .where((e) => e.chickWeight != null && e.yolkWeight != null)
        .length;
    return Container(
      padding: const EdgeInsets.all(AppSizes.cardPadding),
      decoration: BoxDecoration(
        color: AppColors.surfaceRaised,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < 390;
          final status = Text(
            completedRows == 0
                ? 'No YFBM rows entered yet'
                : '$completedRows YFBM rows entered',
            style: AppTextStyles.body.copyWith(
              color: AppColors.textSecondary,
              fontWeight: FontWeight.w700,
            ),
          );
          final button = ElevatedButton.icon(
            onPressed: _openEntriesSheet,
            icon: const Icon(Icons.table_rows, size: 18),
            label: const Text('Enter YFBM Entries'),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              minimumSize: const Size(0, 44),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
              ),
            ),
          );

          if (compact) {
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                status,
                const SizedBox(height: 12),
                SizedBox(width: double.infinity, child: button),
              ],
            );
          }

          return Row(
            children: [
              Expanded(child: status),
              const SizedBox(width: 12),
              button,
            ],
          );
        },
      ),
    );
  }

  Widget _buildSheetHeader(
    BuildContext sheetContext,
    VoidCallback refreshSheet,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 8, 12),
      child: Column(
        children: [
          Center(
            child: Container(
              width: 44,
              height: 4,
              decoration: BoxDecoration(
                color: AppColors.borderDefault,
                borderRadius: BorderRadius.circular(AppSizes.pillRadius),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'YFBM Entries',
                      style: AppTextStyles.heading.copyWith(fontSize: 22),
                    ),
                  ],
                ),
              ),
              if (!widget.isReadOnly) ...[
                FilledButton.icon(
                  onPressed: () {
                    _addEntry();
                    refreshSheet();
                  },
                  icon: const Icon(Icons.add, size: 18),
                  label: const Text('Add row'),
                ),
                const SizedBox(width: 4),
              ],
              IconButton(
                tooltip: 'Close',
                onPressed: () => Navigator.pop(sheetContext),
                icon: const Icon(Icons.close),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEntriesList(
    ScrollController? scrollController,
    VoidCallback refreshSheet,
  ) {
    return ListView.separated(
      controller: scrollController,
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 18),
      itemCount: _entries.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (context, index) {
        final entry = _entries[index];
        return _entryCard(index, entry, refreshSheet);
      },
    );
  }

  Widget _entryCard(int index, _EntryData entry, VoidCallback refreshSheet) {
    final complete = entry.chickWeight != null && entry.yolkWeight != null;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: complete ? AppColors.surfaceRaised : AppColors.surfaceVariant,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: complete
              ? AppColors.primary.withValues(alpha: 0.35)
              : AppColors.borderDefault,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final compact = constraints.maxWidth < 560;
            final rowNumber = _rowNumber(index);
            final fields = [
              _fieldBlock(
                label: 'Chick',
                controller: entry.chickController,
                suffix: 'g',
                onChanged: (v) {
                  _updateEntry(index, 'chickWeight', v);
                  refreshSheet();
                },
                row: index,
                column: 0,
              ),
              _fieldBlock(
                label: 'Yolk',
                controller: entry.yolkController,
                suffix: 'g',
                onChanged: (v) {
                  _updateEntry(index, 'yolkWeight', v);
                  refreshSheet();
                },
                row: index,
                column: 1,
              ),
            ];
            final deleteButton = widget.isReadOnly
                ? const SizedBox.shrink()
                : _deleteButton(index, refreshSheet);

            if (compact) {
              return Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      rowNumber,
                      const SizedBox(width: 10),
                      Expanded(child: fields[0]),
                      const SizedBox(width: 8),
                      Expanded(child: fields[1]),
                      deleteButton,
                    ],
                  ),
                ],
              );
            }

            return Row(
              children: [
                rowNumber,
                const SizedBox(width: 12),
                Expanded(child: fields[0]),
                const SizedBox(width: 10),
                Expanded(child: fields[1]),
                deleteButton,
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildSummaryGrid() {
    final completedRows = _completedRows();
    final stats = [
      _YfbmSummaryStat(
        icon: Icons.check_circle_outline,
        label: 'Rows',
        value: '$completedRows/${_entries.length}',
        color: completedRows == 0 ? AppColors.textSecondary : AppColors.primary,
      ),
      _YfbmSummaryStat(
        icon: Icons.track_changes_outlined,
        label: 'Average',
        value: _avgPercentController.text.isEmpty
            ? '--'
            : '${_avgPercentController.text}%',
        color: _metricColor(_avgPercentController.text, true),
      ),
      _YfbmSummaryStat(
        icon: Icons.show_chart,
        label: 'CV',
        value: _cvPercentController.text.isEmpty
            ? '--'
            : '${_cvPercentController.text}%',
        color: _metricColor(_cvPercentController.text, false),
      ),
      _YfbmSummaryStat(
        icon: Icons.flag_outlined,
        label: _targetLabel,
        value: 'Range',
        color: AppColors.textSecondary,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth < 460 ? 2 : 4;
        const spacing = 8.0;
        final itemWidth =
            (constraints.maxWidth - (spacing * (columns - 1))) / columns;

        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final stat in stats)
              SizedBox(width: itemWidth, child: _buildSummaryCard(stat)),
          ],
        );
      },
    );
  }

  Widget _buildSummaryCard(_YfbmSummaryStat stat) {
    return Container(
      constraints: const BoxConstraints(minHeight: 74),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: stat.color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: stat.color.withValues(alpha: 0.2)),
      ),
      child: Row(
        children: [
          Icon(stat.icon, size: 18, color: stat.color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  stat.value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.body.copyWith(
                    color: stat.color,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  stat.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.textSecondary,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _rowNumber(int index) {
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Text(
        '${index + 1}',
        style: AppTextStyles.body.copyWith(
          color: AppColors.textPrimary,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }

  Widget _fieldBlock({
    required String label,
    required TextEditingController controller,
    required String suffix,
    required Function(double?) onChanged,
    required int row,
    required int column,
  }) {
    return AuditNumericField(
      key: ValueKey(
        column == 0 ? 'yfbm-entry-chick-$row' : 'yfbm-entry-yolk-$row',
      ),
      enabled: !widget.isReadOnly,
      controller: controller,
      allowDecimal: true,
      maxDecimalPlaces: 1,
      navigationGroup: _tableNavigationGroup,
      navigationRow: row,
      navigationColumn: column,
      textAlign: TextAlign.center,
      style: AppTextStyles.title.copyWith(fontWeight: FontWeight.w800),
      decoration: InputDecoration(
        labelText: label,
        suffixText: suffix,
        filled: true,
        fillColor: AppColors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 12,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(
            color: AppColors.borderFocused,
            width: 2,
          ),
        ),
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: AppColors.borderDefault),
        ),
      ),
      onChanged: (v) => onChanged(double.tryParse(v)),
    );
  }

  Widget _deleteButton(int index, VoidCallback refreshSheet) {
    return Padding(
      padding: const EdgeInsets.only(left: 6),
      child: IconButton(
        tooltip: 'Delete row',
        icon: const Icon(Icons.delete_outline, size: 20),
        color: AppColors.statusError,
        style: IconButton.styleFrom(
          backgroundColor: AppColors.statusErrorBg,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
        onPressed: () {
          _removeEntry(index);
          refreshSheet();
        },
      ),
    );
  }

  int _completedRows() => _entries
      .where((entry) => entry.chickWeight != null && entry.yolkWeight != null)
      .length;

  String get _targetLabel =>
      'Target ${AppThresholds.yfbmMin.toStringAsFixed(0)}-'
      '${AppThresholds.yfbmMax.toStringAsFixed(0)}%';

  Color _metricColor(String text, bool average) {
    final value = double.tryParse(text);
    if (value == null) return AppColors.textSecondary;
    if (average) return _percentageColor(value);
    return value <= AppThresholds.cvAlertPct
        ? AppColors.statusGood
        : AppColors.statusError;
  }

  Color _percentageColor(double? pct) {
    if (pct == null) return AppColors.textSecondary;
    return pct >= AppThresholds.yfbmMin && pct <= AppThresholds.yfbmMax
        ? AppColors.statusGood
        : AppColors.statusError;
  }

  @override
  void dispose() {
    for (final entry in _entries) {
      entry.dispose();
    }
    _avgPercentController.dispose();
    _cvPercentController.dispose();
    super.dispose();
  }
}

class _YfbmSummaryStat {
  final IconData icon;
  final String label;
  final String value;
  final Color color;

  const _YfbmSummaryStat({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });
}

class _EntryData {
  double? chickWeight;
  double? yolkWeight;
  late final TextEditingController chickController;
  late final TextEditingController yolkController;

  _EntryData({this.chickWeight, this.yolkWeight}) {
    chickController = TextEditingController(text: _formatWeight(chickWeight));
    yolkController = TextEditingController(text: _formatWeight(yolkWeight));
  }

  static String _formatWeight(double? value) {
    if (value == null) return '';
    return value % 1 == 0 ? value.toStringAsFixed(0) : value.toString();
  }

  Map<String, dynamic> toMap() => {
    'chickWeight': chickWeight,
    'yolkWeight': yolkWeight,
  };

  void dispose() {
    chickController.dispose();
    yolkController.dispose();
  }
}
