import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../../../../core/constants/app_sizes.dart';
import '../../../../core/theme/app_text_styles.dart';
import '../../../../data/models/audit_model.dart';

class EggBreakoutTab extends StatefulWidget {
  final AuditModel audit;
  final bool isReadOnly;
  final Function(String key, dynamic value) onFieldChanged;
  final VoidCallback onSave;
  const EggBreakoutTab({
    super.key,
    required this.audit,
    required this.isReadOnly,
    required this.onFieldChanged,
    required this.onSave,
  });
  @override
  State<EggBreakoutTab> createState() => _EggBreakoutTabState();
}

class _EggBreakoutTabState extends State<EggBreakoutTab> {
  final Map<String, TextEditingController> _controllers = {};

  static const List<_BreakoutField> _fields = [
    _BreakoutField('Infertile', 'ebInfertileCount'),
    _BreakoutField('Early Dead', 'ebEarlyDeadCount'),
    _BreakoutField('Mid Black Eye', 'ebMidDeadCount'),
    _BreakoutField('Late Dead', 'ebLateDeadCount'),
    _BreakoutField('Internal Pip', 'ebInternalPipCount'),
    _BreakoutField('External Pip', 'ebExternalPipCount'),
    _BreakoutField('Cracked', 'ebCrackedCount'),
    _BreakoutField('Contaminated', 'ebContaminatedCount'),
    _BreakoutField('Malposition', 'ebMalpositionCount'),
    _BreakoutField('Exposed Brain', 'ebExposedBrainCount'),
    _BreakoutField('Crossed Beak', 'ebCrossedBeakCount'),
    _BreakoutField('Culled / Dead', 'ebCulledDeadCount'),
  ];

  @override
  void initState() {
    super.initState();
    _controllers['ebTraySize'] = TextEditingController(
      text: (widget.audit.ebTraySize ?? 750).toString(),
    );
    _controllers['ebBreakoutAgeDays'] = TextEditingController(
      text: (widget.audit.ebBreakoutAgeDays ?? 21).toString(),
    );
    for (final field in _fields) {
      _controllers[field.key] = TextEditingController(
        text: _fieldValue(field.key)?.toString() ?? '',
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.isReadOnly) return;
      widget.onFieldChanged('ebTraySize', widget.audit.ebTraySize ?? 750);
      widget.onFieldChanged(
        'ebBreakoutAgeDays',
        widget.audit.ebBreakoutAgeDays ?? 21,
      );
      widget.onFieldChanged(
        'ebBreakoutType',
        widget.audit.ebBreakoutType ?? 'Hatch Residue',
      );
    });
  }

  @override
  Widget build(BuildContext context) {
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
                  Text(
                    '21-Day Hatch Residue Breakout',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  Row(
                    children: [
                      Expanded(
                        child: _numberField(
                          'Tray Size',
                          'ebTraySize',
                          _controllers['ebTraySize']!,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _numberField(
                          'Breakout Age Days',
                          'ebBreakoutAgeDays',
                          _controllers['ebBreakoutAgeDays']!,
                        ),
                      ),
                    ],
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
                  Text(
                    'Egg Counts',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 16),
                  ..._fields.map(
                    (field) => Padding(
                      padding: const EdgeInsets.only(bottom: 12),
                      child: _numberField(
                        field.label,
                        field.key,
                        _controllers[field.key]!,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _numberField(
    String label,
    String field,
    TextEditingController controller,
  ) {
    return TextField(
      controller: controller,
      enabled: !widget.isReadOnly,
      keyboardType: TextInputType.number,
      decoration: InputDecoration(
        labelText: label,
        border: const OutlineInputBorder(),
      ),
      inputFormatters: [FilteringTextInputFormatter.digitsOnly],
      onChanged: (value) => widget.onFieldChanged(field, int.tryParse(value)),
    );
  }

  int? _fieldValue(String key) {
    final map = widget.audit.toMap();
    return map[key] as int?;
  }

  @override
  void dispose() {
    for (final controller in _controllers.values) {
      controller.dispose();
    }
    super.dispose();
  }
}

class _BreakoutField {
  final String label;
  final String key;

  const _BreakoutField(this.label, this.key);
}
