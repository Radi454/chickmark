import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
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
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _isEditing ? 'Edit Flock' : 'Add New Flock',
                style: AppTextStyles.heading.copyWith(fontSize: 20),
              ),
              if (_isEditing) ...[
                const SizedBox(height: 6),
                Text(
                  'Update details, availability, and depletion rules from one place.',
                  style: AppTextStyles.caption,
                ),
              ],
              const SizedBox(height: 20),
              TextFormField(
                controller: _flockIdController,
                decoration: InputDecoration(
                  labelText: 'Flock ID *',
                  hintText: 'Enter flock ID',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
                style: AppTextStyles.body,
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a flock ID';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String>(
                initialValue: _selectedBreed,
                decoration: InputDecoration(
                  labelText: 'Breed',
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                ),
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
              const SizedBox(height: 16),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.calendar_today_outlined),
                    label: Text('Entry date'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.warning_amber_outlined),
                    label: Text('Current age'),
                  ),
                ],
                selected: {_useCurrentAge},
                onSelectionChanged: (selection) {
                  setState(() {
                    _useCurrentAge = selection.first;
                  });
                },
              ),
              const SizedBox(height: 12),
              if (_useCurrentAge)
                TextFormField(
                  controller: _ageWeeksController,
                  decoration: InputDecoration(
                    labelText: 'Current age weeks *',
                    hintText: 'Enter current flock age',
                    helperText: 'This creates an estimated entry date.',
                    prefixIcon: const Icon(Icons.warning_amber_outlined),
                    filled: true,
                    fillColor: AppColors.background,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
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
                ListTile(
                  title: Text(
                    'Entry Date',
                    style: AppTextStyles.body.copyWith(
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  subtitle: Text(
                    '${_entryDate.day}/${_entryDate.month}/${_entryDate.year}',
                    style: AppTextStyles.body,
                  ),
                  trailing: const Icon(Icons.calendar_today),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(color: Colors.grey.shade300),
                  ),
                  onTap: _selectDate,
                ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _depletionAgeController,
                decoration: InputDecoration(
                  labelText: 'Depletion age weeks *',
                  hintText: 'Default is 65 weeks',
                  helperText:
                      'Flocks at or beyond this age are hidden from new audits.',
                  prefixIcon: const Icon(Icons.hourglass_bottom_outlined),
                  filled: true,
                  fillColor: AppColors.background,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
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
              const SizedBox(height: 16),
              Text(
                'Availability',
                style: AppTextStyles.caption.copyWith(
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 8),
              SegmentedButton<bool>(
                segments: const [
                  ButtonSegment(
                    value: false,
                    icon: Icon(Icons.check_circle_outline),
                    label: Text('Active'),
                  ),
                  ButtonSegment(
                    value: true,
                    icon: Icon(Icons.sell_outlined),
                    label: Text('Sold'),
                  ),
                ],
                selected: {_isSold},
                onSelectionChanged: (selection) {
                  setState(() {
                    _isSold = selection.first;
                  });
                },
              ),
              if (!_isSold) ...[
                const SizedBox(height: 8),
                Text(
                  'Active flocks are still hidden from new audits once they reach depletion age.',
                  style: AppTextStyles.caption,
                ),
              ],
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _saveFlock,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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
