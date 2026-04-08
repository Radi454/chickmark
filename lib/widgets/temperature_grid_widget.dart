import 'package:flutter/material.dart';
import '../utils/app_theme.dart';

class TemperatureGridWidget extends StatelessWidget {
  final List<double?> values; // 9 values: row-major [top-front..bot-back]
  final Function(int index, double? value) onChanged;
  final String label;

  const TemperatureGridWidget({
    super.key,
    required this.values,
    required this.onChanged,
    this.label = 'Temperature Grid (°C)',
  });

  Color _cellColor(double? v) {
    if (v == null) return Colors.grey.shade100;
    if (v < 37.5) return Colors.blue.shade100;
    if (v <= 38.5) return AppTheme.green.withValues(alpha: 0.2);
    return AppTheme.red.withValues(alpha: 0.2);
  }

  double? _average() {
    final vals = values.whereType<double>().toList();
    if (vals.isEmpty) return null;
    return vals.reduce((a, b) => a + b) / vals.length;
  }

  @override
  Widget build(BuildContext context) {
    final cols = ['Front', 'Middle', 'Back'];
    final rows = ['Top', 'Middle', 'Bottom'];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 14,
                color: AppTheme.textPrimary)),
        const SizedBox(height: 8),
        Table(
          border: TableBorder.all(color: Colors.grey.shade300),
          columnWidths: const {
            0: FlexColumnWidth(1.2),
            1: FlexColumnWidth(1),
            2: FlexColumnWidth(1),
            3: FlexColumnWidth(1),
          },
          children: [
            TableRow(
              decoration:
                  BoxDecoration(color: AppTheme.primary.withValues(alpha: 0.1)),
              children: [
                const TableCell(
                    child: Padding(
                        padding: EdgeInsets.all(6),
                        child: Text('Position',
                            style: TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12)))),
                ...cols.map((c) => TableCell(
                    child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(c,
                            textAlign: TextAlign.center,
                            style: const TextStyle(
                                fontWeight: FontWeight.bold, fontSize: 12))))),
              ],
            ),
            ...List.generate(3, (rowIdx) {
              return TableRow(children: [
                TableCell(
                    child: Padding(
                        padding: const EdgeInsets.all(6),
                        child: Text(rows[rowIdx],
                            style: const TextStyle(
                                fontWeight: FontWeight.w500, fontSize: 12)))),
                ...List.generate(3, (colIdx) {
                  final idx = rowIdx * 3 + colIdx;
                  return TableCell(
                    child: Container(
                      color: _cellColor(values[idx]),
                      child: _TempCell(
                        value: values[idx],
                        onChanged: (v) => onChanged(idx, v),
                      ),
                    ),
                  );
                }),
              ]);
            }),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const Text('Grid Average: ',
                style: TextStyle(
                    fontSize: 13, color: AppTheme.textSecondary)),
            Text(
              _average() != null
                  ? '${_average()!.toStringAsFixed(2)} °C'
                  : '—',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: AppTheme.primary),
            ),
            const SizedBox(width: 16),
            _legend(Colors.blue.shade100, '< 37.5°C'),
            const SizedBox(width: 8),
            _legend(AppTheme.green.withValues(alpha: 0.3), '37.5–38.5°C'),
            const SizedBox(width: 8),
            _legend(AppTheme.red.withValues(alpha: 0.3), '> 38.5°C'),
          ],
        ),
      ],
    );
  }

  Widget _legend(Color color, String text) => Row(
        children: [
          Container(width: 12, height: 12, color: color),
          const SizedBox(width: 4),
          Text(text, style: const TextStyle(fontSize: 10)),
        ],
      );
}

class _TempCell extends StatefulWidget {
  final double? value;
  final Function(double?) onChanged;
  const _TempCell({required this.value, required this.onChanged});

  @override
  State<_TempCell> createState() => _TempCellState();
}

class _TempCellState extends State<_TempCell> {
  late TextEditingController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = TextEditingController(
        text: widget.value?.toStringAsFixed(1) ?? '');
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(4),
      child: TextField(
        controller: _ctrl,
        keyboardType:
            const TextInputType.numberWithOptions(decimal: true),
        textAlign: TextAlign.center,
        style: const TextStyle(fontSize: 13),
        decoration: const InputDecoration(
          isDense: true,
          contentPadding:
              EdgeInsets.symmetric(horizontal: 4, vertical: 6),
          border: InputBorder.none,
          hintText: '—',
        ),
        onChanged: (v) {
          widget.onChanged(double.tryParse(v));
        },
      ),
    );
  }
}
