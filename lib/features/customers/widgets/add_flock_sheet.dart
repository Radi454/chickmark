import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../providers/customers_provider.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../data/models/breeder_isolation_area_model.dart';

/// One house row being edited in the flock-creation flow. A farm and a
/// flock are the same thing in this business, so house setup is folded into
/// flock creation rather than a separate farm-management screen: this is
/// the row's editable draft, converted to a [HouseModel] on save.
class _HouseDraft {
  _HouseDraft({this.existingId, String name = '', int females = 0, int males = 0})
    : nameController = TextEditingController(text: name),
      femalesController = TextEditingController(
        text: females == 0 ? '' : females.toString(),
      ),
      malesController = TextEditingController(
        text: males == 0 ? '' : males.toString(),
      );

  final String? existingId;
  final TextEditingController nameController;
  final TextEditingController femalesController;
  final TextEditingController malesController;

  void dispose() {
    nameController.dispose();
    femalesController.dispose();
    malesController.dispose();
  }
}

/// One isolation-area row being edited in the flock-creation flow
/// (breeder-flock-performance ticket 08). Unlike a house, an isolation area
/// has no opening bird count of its own — birds only ever arrive there via
/// an internal transfer recorded on a daily report — so this draft is just
/// a name.
class _IsolationAreaDraft {
  _IsolationAreaDraft({this.existingId, String name = ''})
    : nameController = TextEditingController(text: name);

  final String? existingId;
  final TextEditingController nameController;

  void dispose() {
    nameController.dispose();
  }
}

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
  late String _selectedBreed;
  late DateTime _entryDate;
  late bool _useCurrentAge;
  late bool _isSold;
  final List<_HouseDraft> _houseDrafts = [];
  final List<_IsolationAreaDraft> _isolationAreaDrafts = [];
  String? _saveError;
  bool _isSaving = false;

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
    _selectedBreed = widget.initialFlock?.breed ?? 'Ross308';
    _entryDate = widget.initialFlock?.entryDate ?? DateTime.now();
    _useCurrentAge = widget.initialFlock?.isAgeEstimated ?? false;
    _isSold = widget.initialFlock?.isSold ?? false;
    final existingFlock = widget.initialFlock;
    if (existingFlock != null) {
      final existingHouses = context
          .read<CustomersProvider>()
          .housesForFlock(existingFlock.id);
      for (final house in existingHouses) {
        _houseDrafts.add(
          _HouseDraft(
            existingId: house.id,
            name: house.name,
            females: house.openingFemales,
            males: house.openingMales,
          ),
        );
      }
      final existingAreas = context
          .read<CustomersProvider>()
          .isolationAreasForFlock(existingFlock.id);
      for (final area in existingAreas) {
        _isolationAreaDrafts.add(
          _IsolationAreaDraft(existingId: area.id, name: area.name),
        );
      }
    }
  }

  @override
  void dispose() {
    _flockIdController.dispose();
    _ageWeeksController.dispose();
    for (final draft in _houseDrafts) {
      draft.dispose();
    }
    for (final draft in _isolationAreaDrafts) {
      draft.dispose();
    }
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
    if (_isSaving) return;
    setState(() => _saveError = null);
    if (!_formKey.currentState!.validate()) return;

    final customersProvider = context.read<CustomersProvider>();
    final selectedCustomer = customersProvider.selectedCustomer;

    if (selectedCustomer == null) {
      setState(
        () => _saveError =
            'No customer selected. Reopen this sheet from a customer.',
      );
      return;
    }

    final enteredAge = int.tryParse(_ageWeeksController.text.trim());
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
      // Carried forward unread and unedited: depletionAgeWeeks is no longer
      // used by any Breeder Performance behaviour (see FlockModel), so this
      // sheet neither displays nor lets the user change it. Preserving the
      // existing value on edit just avoids clobbering it back to the
      // default ahead of the column's later removal.
      depletionAgeWeeks:
          widget.initialFlock?.depletionAgeWeeks ??
          FlockModel.defaultDepletionAgeWeeks,
      soldAt: _isSold ? existingSoldAt ?? DateTime.now() : null,
    );

    setState(() => _isSaving = true);
    try {
      if (_isEditing) {
        await customersProvider.updateFlock(flock);
      } else {
        await customersProvider.addFlock(flock);
      }
      for (final house in _housesToSave(flock.id)) {
        await customersProvider.saveHouse(house);
      }
      for (final area in _isolationAreasToSave(flock.id)) {
        await customersProvider.saveIsolationArea(area);
      }
    } catch (error) {
      // Without this the sheet just sat there on any repository/permission
      // failure, which reads as "Save does nothing".
      debugPrint('Error saving flock: $error');
      if (!mounted) return;
      setState(() {
        _isSaving = false;
        _saveError = _messageFor(error);
      });
      return;
    }
    if (!mounted) return;
    Navigator.of(context).pop(flock);
  }

  /// Rows with a blank name are skipped rather than saved as an unnamed
  /// house.
  List<HouseModel> _housesToSave(String flockId) {
    final houses = <HouseModel>[];
    for (final draft in _houseDrafts) {
      final name = draft.nameController.text.trim();
      if (name.isEmpty) continue;
      houses.add(
        HouseModel(
          id: draft.existingId ?? const Uuid().v4(),
          flockId: flockId,
          name: name,
          openingFemales: int.tryParse(draft.femalesController.text.trim()) ?? 0,
          openingMales: int.tryParse(draft.malesController.text.trim()) ?? 0,
        ),
      );
    }
    return houses;
  }

  void _addHouseDraft() {
    setState(() => _houseDrafts.add(_HouseDraft()));
  }

  void _removeHouseDraft(int index) {
    setState(() => _houseDrafts.removeAt(index).dispose());
  }

  /// Rows with a blank name are skipped, same as [_housesToSave].
  List<BreederIsolationArea> _isolationAreasToSave(String flockId) {
    final areas = <BreederIsolationArea>[];
    for (final draft in _isolationAreaDrafts) {
      final name = draft.nameController.text.trim();
      if (name.isEmpty) continue;
      areas.add(
        BreederIsolationArea(
          id: draft.existingId ?? const Uuid().v4(),
          flockId: flockId,
          name: name,
        ),
      );
    }
    return areas;
  }

  void _addIsolationAreaDraft() {
    setState(() => _isolationAreaDrafts.add(_IsolationAreaDraft()));
  }

  void _removeIsolationAreaDraft(int index) {
    setState(() => _isolationAreaDrafts.removeAt(index).dispose());
  }

  String _messageFor(Object error) {
    final raw = error is StateError ? error.message : error.toString();
    return raw.replaceFirst(RegExp(r'^Exception:\s*'), '');
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
              const SizedBox(height: AppSizes.spaceLg),
              _buildHousesSection(),
              const SizedBox(height: AppSizes.spaceLg),
              _buildIsolationAreasSection(),
              if (_saveError != null) ...[
                const SizedBox(height: AppSizes.spaceLg),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(AppSizes.spaceMd),
                  decoration: BoxDecoration(
                    color: AppColors.statusErrorBg,
                    borderRadius: BorderRadius.circular(AppSizes.inputRadius),
                    border: Border.all(color: AppColors.statusError),
                  ),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: AppSizes.iconSm,
                        color: AppColors.statusError,
                      ),
                      const SizedBox(width: AppSizes.spaceSm),
                      Expanded(
                        child: Text(
                          'Could not save: $_saveError',
                          style: AppTextStyles.caption.copyWith(
                            color: AppColors.statusError,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: AppSizes.spaceXl),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: _isSaving ? null : _saveFlock,
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

  /// A farm and a flock are the same thing in this business, so house setup
  /// lives inside flock creation instead of a separate farm-management
  /// screen. Each row is one house with its opening female/male bird count;
  /// `flocks.entryDate` above is the single placement date for all of them.
  Widget _buildHousesSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Houses',
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSizes.spaceSm),
        for (var i = 0; i < _houseDrafts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
            child: _HouseDraftRow(
              draft: _houseDrafts[i],
              onRemove: () => _removeHouseDraft(i),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addHouseDraft,
          icon: const Icon(Icons.add_home_work_outlined),
          label: Text(_houseDrafts.isEmpty ? 'Add house' : 'Add another house'),
        ),
      ],
    );
  }

  /// Isolation areas (breeder-flock-performance ticket 08) live alongside
  /// houses in this same flock-creation flow, for the same reason houses
  /// do: this is where the flock's locations are managed. Unlike a house, an
  /// isolation area has no opening bird count — see [_IsolationAreaDraft].
  Widget _buildIsolationAreasSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Isolation areas',
          style: AppTextStyles.caption.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: AppSizes.spaceSm),
        for (var i = 0; i < _isolationAreaDrafts.length; i++)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
            child: _IsolationAreaDraftRow(
              draft: _isolationAreaDrafts[i],
              onRemove: () => _removeIsolationAreaDraft(i),
            ),
          ),
        OutlinedButton.icon(
          onPressed: _addIsolationAreaDraft,
          icon: const Icon(Icons.shield_outlined),
          label: Text(
            _isolationAreaDrafts.isEmpty
                ? 'Add isolation area'
                : 'Add another isolation area',
          ),
        ),
      ],
    );
  }
}

class _IsolationAreaDraftRow extends StatelessWidget {
  const _IsolationAreaDraftRow({required this.draft, required this.onRemove});

  final _IsolationAreaDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.inputRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Row(
        children: [
          Expanded(
            child: TextFormField(
              controller: draft.nameController,
              decoration: const InputDecoration(
                labelText: 'Isolation area name',
              ),
            ),
          ),
          IconButton(
            onPressed: onRemove,
            icon: const Icon(Icons.close),
            tooltip: 'Remove isolation area',
          ),
        ],
      ),
    );
  }
}

class _HouseDraftRow extends StatelessWidget {
  const _HouseDraftRow({required this.draft, required this.onRemove});

  final _HouseDraft draft;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSizes.spaceMd),
      decoration: BoxDecoration(
        color: AppColors.background,
        borderRadius: BorderRadius.circular(AppSizes.inputRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.nameController,
                  decoration: const InputDecoration(labelText: 'House name'),
                ),
              ),
              IconButton(
                onPressed: onRemove,
                icon: const Icon(Icons.close),
                tooltip: 'Remove house',
              ),
            ],
          ),
          const SizedBox(height: AppSizes.spaceSm),
          Row(
            children: [
              Expanded(
                child: TextFormField(
                  controller: draft.femalesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Opening females',
                  ),
                ),
              ),
              const SizedBox(width: AppSizes.spaceMd),
              Expanded(
                child: TextFormField(
                  controller: draft.malesController,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(
                    labelText: 'Opening males',
                  ),
                ),
              ),
            ],
          ),
        ],
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
