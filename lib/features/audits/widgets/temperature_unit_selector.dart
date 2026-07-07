import 'package:hatchaudit/localized_material.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../models/temperature_entry_unit.dart';

class TemperatureUnitSelector extends StatelessWidget {
  const TemperatureUnitSelector({
    super.key,
    required this.value,
    required this.onChanged,
    required this.keyPrefix,
    this.enabled = true,
  });

  final TemperatureEntryUnit value;
  final ValueChanged<TemperatureEntryUnit> onChanged;
  final String keyPrefix;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      key: ValueKey('$keyPrefix-unit-selector'),
      spacing: 6,
      children: [
        _chip(TemperatureEntryUnit.fahrenheit, '°F'),
        _chip(TemperatureEntryUnit.celsius, '°C'),
      ],
    );
  }

  Widget _chip(TemperatureEntryUnit unit, String label) {
    final selected = value == unit;
    final keySuffix = unit == TemperatureEntryUnit.fahrenheit ? 'f' : 'c';
    return ChoiceChip(
      key: ValueKey('$keyPrefix-unit-$keySuffix'),
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: enabled ? (_) => onChanged(unit) : null,
      selectedColor: AppColors.primary.withAlpha(30),
      labelStyle: AppTextStyles.body.copyWith(
        color: selected ? AppColors.primary : AppColors.textBody,
        fontWeight: FontWeight.w800,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: BorderSide(
          color: selected ? AppColors.primary : AppColors.borderDefault,
        ),
      ),
    );
  }
}
