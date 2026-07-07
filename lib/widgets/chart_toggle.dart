import 'package:hatchaudit/localized_material.dart';
import 'package:hatchaudit/core/constants/app_colors.dart';

enum ChartType { bar, line, donut }

class ChartToggle extends StatelessWidget {
  final ChartType selected;
  final ValueChanged<ChartType> onChanged;

  const ChartToggle({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SegmentedButton<ChartType>(
      segments: const [
        ButtonSegment(value: ChartType.bar, label: Text('Bar')),
        ButtonSegment(value: ChartType.line, label: Text('Line')),
        ButtonSegment(value: ChartType.donut, label: Text('Donut')),
      ],
      selected: {selected},
      onSelectionChanged: (selected) => onChanged(selected.first),
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return AppColors.primary;
          }
          return null;
        }),
      ),
    );
  }
}
