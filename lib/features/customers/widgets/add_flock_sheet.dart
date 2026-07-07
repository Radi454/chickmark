import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../providers/customers_provider.dart';
import '../../../data/models/flock_model.dart';

class AddFlockSheet extends StatefulWidget {
  final FlockModel? initialFlock;

  const AddFlockSheet({super.key, this.initialFlock});

  @override
  State<AddFlockSheet> createState() => _AddFlockSheetState();
}

class _AddFlockSheetState extends State<AddFlockSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _flockIdController;
  late final TextEditingController _ageWeeksController;
  late final TextEditingController _depletionAgeController;
  late String _selectedBreed;
  late DateTime _entryDate;
  late bool _useCurrentAge;
  late bool _isSold;

  bool get _isEditing => widget.initialFlock != null;

  final List<String> _breeds = [
    'Ross308',
    'Arbo',
    'Avian',
    'Cobb500',
    'Hubbard',
    'IR',
  ];

  @override
  void initState() {
    super.initState();
    _flockIdController = TextEditingController(
      text: widget.initialFlock?.flockId ?? '',
    );
    _ageWeeksController = TextEditingController(
      text: widget.initialFlock == null
          ? ''
          : widget.initialFlock!.currentAgeWeeks.toInt().toString(),
    );
    _depletionAgeController = TextEditingController(
      text:
          (widget.initialFlock?.depletionAgeWeeks ??
                  FlockModel.defaultDepletionAgeWeeks)
              .toString(),
    );
    _selectedBreed = widget.initialFlock?.breed ?? 'Ross308';
    _entryDate = widget.initialFlock?.entryDate ?? DateTime.now();
    _useCurrentAge = widget.initialFlock?.isAgeEstimated ?? false;
    _isSold = widget.initialFlock?.isSold ?? false;
  }

  @override
  void dispose() {
    _flockIdController.dispose();
    _ageWeeksController.dispose();
    _depletionAgeController.dispose();
    super.dispose();
  }

  Future<void> _selectDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _entryDate = picked;
      });
    }
  }

  Future<void> _saveFlock() async {
    if (_formKey.currentState!.validate()) {
      final customersProvider = context.read<CustomersProvider>();
      final selectedCustomer = customersProvider.selectedCustomer;

      if (selectedCustomer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No customer selected')),
        );
        return;
      }

      final enteredAge = int.tryParse(_ageWeeksController.text.trim());
      final depletionAge =
          int.tryParse(_depletionAgeController.text.trim()) ??
          FlockModel.defaultDepletionAgeWeeks;
      final resolvedEntryDate = _useCurrentAge && enteredAge != null
          ? DateTime.now().subtract(Duration(days: enteredAge * 7))
          : _entryDate;
      final existingSoldAt = widget.initialFlock?.soldAt;

      final flock = FlockModel(
        id: _isEditing ? widget.initialFlock!.id : const Uuid().v4(),
        customerId: selectedCustomer.id,
        flockId: _flockIdController.text.trim(),
        breed: _selectedBreed,
        entryDate: resolvedEntryDate,
        isAgeEstimated: _useCurrentAge,
        status: _isSold ? FlockModel.soldStatus : FlockModel.activeStatus,
        depletionAgeWeeks: depletionAge,
        soldAt: _isSold ? existingSoldAt ?? DateTime.now() : null,
      );

      if (_isEditing) {
        await customersProvider.updateFlock(flock);
      } else {
        await customersProvider.addFlock(flock);
      }
      if (!mounted) return;
      Navigator.of(context).pop(flock);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(AppSizes.sheetRadius),
        ),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.spaceXl,
          AppSizes.spaceLg,
          AppSizes.spaceXl,
          AppSizes.spaceXl,
        ),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Center(
                child: Container(
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                    color: AppColors.borderDefault,
                    borderRadius: BorderRadius.circular(AppSizes.pillRadius),
                  ),
                ),
              ),
              const SizedBox(height: AppSizes.spaceLg),
              Text(
                _isEditing ? 'Edit Flock' : 'Add New Flock',
                style: AppTextStyles.heading,
              ),
              if (_isEditing) ...[
                const SizedBox(height: AppSizes.spaceXs),
                Text(
                  'Update details, availability, and depletion rules from one place.',
                  style: AppTextStyles.caption,
                ),
              ],
              const SizedBox(height: AppSizes.spaceLg),
              TextFormField(
                controller: _flockIdController,
                decoration: const InputDecoration(
                  labelText: 'Flock ID *',
                  hintText: 'Enter flock ID',
                ),
                style: AppTextStyles.body,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a flock ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.spaceMd),
              DropdownButtonFormField<String>(
                initialValue: _selectedBreed,
                decoration: const InputDecoration(labelText: 'Breed'),
                style: AppTextStyles.body,
                items: _breeds.map((breed) {
                  return DropdownMenuItem<String>(
                    value: breed,
                    child: Text(breed),
                  );
                }).toList(),
                onChanged: (value) {
                  if (value != null) {
                    setState(() {
                      _selectedBreed = value;
                    });
                  }
                },
              ),
              const SizedBox(height: AppSizes.spaceLg),
              _ChoiceRow<bool>(
                label: 'Age source',
                value: _useCurrentAge,
                options: const [
                  _ChoiceOption(
                    value: false,
                    icon: Icons.calendar_today_outlined,
                    label: 'Entry date',
                  ),
                  _ChoiceOption(
                    value: true,
                    icon: Icons.calculate_outlined,
                    label: 'Current age',
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _useCurrentAge = value;
                  });
                },
              ),
              const SizedBox(height: AppSizes.spaceMd),
              if (_useCurrentAge)
                TextFormField(
                  controller: _ageWeeksController,
                  decoration: const InputDecoration(
                    labelText: 'Current age weeks *',
                    hintText: 'Enter current flock age',
                    helperText: 'This creates an estimated entry date.',
                    prefixIcon: Icon(Icons.calculate_outlined),
                  ),
                  keyboardType: TextInputType.number,
                  style: AppTextStyles.body,
                  validator: (value) {
                    if (!_useCurrentAge) return null;
                    final age = int.tryParse(value?.trim() ?? '');
                    if (age == null || age < 0 || age > 120) {
                      return 'Enter age between 0 and 120 weeks';
                    }
                    return null;
                  },
                )
              else
                _DateFieldButton(date: _entryDate, onTap: _selectDate),
              const SizedBox(height: AppSizes.spaceMd),
              TextFormField(
                controller: _depletionAgeController,
                decoration: const InputDecoration(
                  labelText: 'Depletion age weeks *',
                  hintText: 'Default is 65 weeks',
                  helperText:
                      'Flocks at or beyond this age are hidden from new audits.',
                  prefixIcon: Icon(Icons.hourglass_bottom_outlined),
                ),
                keyboardType: TextInputType.number,
                style: AppTextStyles.body,
                validator: (value) {
                  final age = int.tryParse(value?.trim() ?? '');
                  if (age == null || age < 1 || age > 160) {
                    return 'Enter depletion age between 1 and 160 weeks';
                  }
                  return null;
                },
              ),
              const SizedBox(height: AppSizes.spaceLg),
              _ChoiceRow<bool>(
                label: 'Availability',
                value: _isSold,
                options: const [
                  _ChoiceOption(
                    value: false,
                    icon: Icons.check_circle_outline,
                    label: 'Active',
                  ),
                  _ChoiceOption(
                    value: true,
                    icon: Icons.sell_outlined,
                    label: 'Sold',
                  ),
                ],
                onChanged: (value) {
                  setState(() {
                    _isSold = value;
                  });
                },
              ),
              if (!_isSold) ...[
                const SizedBox(height: AppSizes.spaceSm),
                Text(
                  'Active flocks are still hidden from new audits once they reach depletion age.',
                  style: AppTextStyles.caption,
                ),
              ],
              const SizedBox(height: AppSizes.spaceXl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveFlock,
                  style: ElevatedButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSizes.spaceLg,
                    ),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(
                        AppSizes.buttonRadius,
                      ),
                    ),
                  ),
                  child: Text(
                    _isEditing ? 'Update' : 'Save',
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ChoiceOption<T> {
  final T value;
  final IconData icon;
  final String label;

  const _ChoiceOption({
    required this.value,
    required this.icon,
    required this.label,
  });
}

class _ChoiceRow<T> extends StatelessWidget {
  final String label;
  final T value;
  final List<_ChoiceOption<T>> options;
  final ValueChanged<T> onChanged;

  const _ChoiceRow({
    required this.label,
    required this.value,
    required this.options,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSizes.spaceSm),
        Container(
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: AppColors.background,
            borderRadius: BorderRadius.circular(AppSizes.buttonRadius),
            border: Border.all(color: AppColors.borderDefault),
          ),
          child: Row(
            children: options.map((option) {
              final selected = option.value == value;
              return Expanded(
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
                  onTap: () => onChanged(option.value),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSizes.spaceMd,
                      vertical: AppSizes.spaceSm,
                    ),
                    decoration: BoxDecoration(
                      color: selected ? AppColors.surface : Colors.transparent,
                      borderRadius: BorderRadius.circular(AppSizes.badgeRadius),
                      boxShadow: selected
                          ? const [
                              BoxShadow(
                                color: AppColors.cardShadow,
                                blurRadius: 8,
                                offset: Offset(0, 2),
                              ),
                            ]
                          : null,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          option.icon,
                          size: AppSizes.iconSm,
                          color: selected
                              ? AppColors.primary
                              : AppColors.textSecondary,
                        ),
                        const SizedBox(width: AppSizes.spaceSm),
                        Flexible(
                          child: Text(
                            option.label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.badgeLabel.copyWith(
                              color: selected
                                  ? AppColors.textPrimary
                                  : AppColors.textSecondary,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }
}

class _DateFieldButton extends StatelessWidget {
  final DateTime date;
  final VoidCallback onTap;

  const _DateFieldButton({required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final formattedDate = '${date.day}/${date.month}/${date.year}';

    return InkWell(
      borderRadius: BorderRadius.circular(AppSizes.inputRadius),
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceLg,
          vertical: AppSizes.spaceMd,
        ),
        decoration: BoxDecoration(
          color: AppColors.surface,
          borderRadius: BorderRadius.circular(AppSizes.inputRadius),
          border: Border.all(color: AppColors.borderDefault),
        ),
        child: Row(
          children: [
            const Icon(
              Icons.calendar_today_outlined,
              size: AppSizes.iconSm,
              color: AppColors.textSecondary,
            ),
            const SizedBox(width: AppSizes.spaceMd),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Entry date',
                    style: AppTextStyles.caption.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: AppSizes.spaceXs),
                  Text(formattedDate, style: AppTextStyles.body),
                ],
              ),
            ),
            const Icon(
              Icons.edit_calendar_outlined,
              size: AppSizes.iconSm,
              color: AppColors.primary,
            ),
          ],
        ),
      ),
    );
  }
}
