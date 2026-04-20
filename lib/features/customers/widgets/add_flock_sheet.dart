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
  late String _selectedBreed;
  late DateTime _entryDate;

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
    _selectedBreed = widget.initialFlock?.breed ?? 'Ross308';
    _entryDate = widget.initialFlock?.entryDate ?? DateTime.now();
  }

  @override
  void dispose() {
    _flockIdController.dispose();
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

  void _saveFlock() {
    if (_formKey.currentState!.validate()) {
      final customersProvider = context.read<CustomersProvider>();
      final selectedCustomer = customersProvider.selectedCustomer;

      if (selectedCustomer == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Error: No customer selected')),
        );
        return;
      }

      final flock = FlockModel(
        id: _isEditing ? widget.initialFlock!.id : const Uuid().v4(),
        customerId: selectedCustomer.id,
        flockId: _flockIdController.text.trim(),
        breed: _selectedBreed,
        entryDate: _entryDate,
      );

      if (_isEditing) {
        customersProvider.updateFlock(flock);
      } else {
        customersProvider.addFlock(flock);
      }
      Navigator.pop(context);
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
                // ignore: deprecated_member_use
              value: _selectedBreed,
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
