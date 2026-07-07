import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../data/models/hatchery_model.dart';
import '../../../providers/customers_provider.dart';
import '../../auth/providers/auth_provider.dart';

class AddHatcherySheet extends StatefulWidget {
  final String customerId;
  final HatcheryModel? initialHatchery;

  const AddHatcherySheet({
    super.key,
    required this.customerId,
    this.initialHatchery,
  });

  @override
  State<AddHatcherySheet> createState() => _AddHatcherySheetState();
}

class _AddHatcherySheetState extends State<AddHatcherySheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _locationController;
  late final TextEditingController _notesController;

  bool get _isEditing => widget.initialHatchery != null;

  @override
  void initState() {
    super.initState();
    final initial = widget.initialHatchery;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _locationController = TextEditingController(text: initial?.location ?? '');
    _notesController = TextEditingController(text: initial?.notes ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _locationController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final auth = context.read<AuthProvider>();
    final provider = context.read<CustomersProvider>();
    final initial = widget.initialHatchery;
    final hatchery = HatcheryModel(
      id: initial?.id ?? const Uuid().v4(),
      customerId: widget.customerId,
      name: _nameController.text.trim(),
      location: _locationController.text.trim().isEmpty
          ? null
          : _locationController.text.trim(),
      notes: _notesController.text.trim().isEmpty
          ? null
          : _notesController.text.trim(),
      createdAt: initial?.createdAt ?? DateTime.now(),
      createdBy: initial?.createdBy ?? auth.user?.id ?? '',
    );
    if (_isEditing) {
      await provider.updateHatchery(hatchery);
    } else {
      await provider.addHatchery(hatchery);
    }
    if (!mounted) return;
    Navigator.pop(context, hatchery);
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
                _isEditing ? 'Edit Hatchery' : 'Add Hatchery',
                style: AppTextStyles.heading.copyWith(fontSize: 20),
              ),
              const SizedBox(height: 20),
              _field(
                controller: _nameController,
                label: 'Hatchery name *',
                hint: 'Main hatchery',
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return 'Please enter a hatchery name';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),
              _field(
                controller: _locationController,
                label: 'Location',
                hint: 'City, site, or address',
              ),
              const SizedBox(height: 16),
              _field(
                controller: _notesController,
                label: 'Notes',
                hint: 'Optional',
                maxLines: 3,
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _save,
                  icon: Icon(
                    _isEditing
                        ? Icons.save_outlined
                        : Icons.add_business_outlined,
                  ),
                  label: Text(_isEditing ? 'Update Hatchery' : 'Save Hatchery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: AppColors.primary,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
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

  Widget _field({
    required TextEditingController controller,
    required String label,
    required String hint,
    String? Function(String?)? validator,
    int maxLines = 1,
  }) {
    return TextFormField(
      controller: controller,
      maxLines: maxLines,
      decoration: InputDecoration(
        labelText: label,
        hintText: hint,
        filled: true,
        fillColor: AppColors.background,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
      ),
      style: AppTextStyles.body,
      validator: validator,
    );
  }
}
