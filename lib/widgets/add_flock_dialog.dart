import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/app_provider.dart';
import '../utils/app_theme.dart';

class AddFlockDialog extends StatefulWidget {
  final String customerId;

  const AddFlockDialog({super.key, required this.customerId});

  @override
  State<AddFlockDialog> createState() => _AddFlockDialogState();
}

class _AddFlockDialogState extends State<AddFlockDialog> {
  final _formKey = GlobalKey<FormState>();
  final _flockCodeCtrl = TextEditingController();
  final _breedCtrl = TextEditingController();
  DateTime? _entryDate;
  bool _isSaving = false;

  @override
  void dispose() {
    _flockCodeCtrl.dispose();
    _breedCtrl.dispose();
    super.dispose();
  }

  double? get _ageWeeks {
    if (_entryDate == null) return null;
    return DateTime.now().difference(_entryDate!).inDays / 7.0;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _entryDate ?? DateTime.now().subtract(const Duration(days: 140)),
      firstDate: DateTime(2015),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _entryDate = picked);
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_entryDate == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please select a flock entry date.')),
      );
      return;
    }
    setState(() => _isSaving = true);
    try {
      final flock = await context.read<AppProvider>().createFlock(
            widget.customerId,
            _flockCodeCtrl.text.trim(),
            _breedCtrl.text.trim(),
            _entryDate!,
          );
      if (mounted) Navigator.of(context).pop(flock);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to create flock: $e'),
            backgroundColor: AppTheme.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ageWeeks = _ageWeeks;

    return AlertDialog(
      title: const Text('New Flock'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextFormField(
                controller: _flockCodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'Flock Code *',
                  prefixIcon: Icon(Icons.tag),
                ),
                textCapitalization: TextCapitalization.characters,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Flock code is required' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _breedCtrl,
                decoration: const InputDecoration(
                  labelText: 'Breed *',
                  prefixIcon: Icon(Icons.egg_outlined),
                  hintText: 'e.g. Ross 308',
                ),
                textCapitalization: TextCapitalization.words,
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Breed is required' : null,
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: _pickDate,
                borderRadius: BorderRadius.circular(8),
                child: InputDecorator(
                  decoration: const InputDecoration(
                    labelText: 'Flock Entry Date *',
                    prefixIcon: Icon(Icons.calendar_today),
                  ),
                  child: Text(
                    _entryDate == null
                        ? 'Tap to select date'
                        : DateFormat('dd MMM yyyy').format(_entryDate!),
                    style: TextStyle(
                      color: _entryDate == null
                          ? Theme.of(context).hintColor
                          : null,
                    ),
                  ),
                ),
              ),
              if (ageWeeks != null) ...[
                const SizedBox(height: 12),
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppTheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, size: 16),
                      const SizedBox(width: 8),
                      Text(
                        'Age: ${ageWeeks.toStringAsFixed(1)} wks  |  EP age: ${(ageWeeks + 3).toStringAsFixed(1)} wks',
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: _isSaving ? null : _save,
          child: _isSaving
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Create'),
        ),
      ],
    );
  }
}
