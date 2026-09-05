import 'package:hatchaudit/localized_material.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/breeder_egg_grade_definition_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../data/repositories/breeder_egg_grade_definition_repository.dart';
import '../../../data/repositories/poultry_hierarchy_repository.dart';
import '../../../services/breeder/egg_batch_dispatch_service.dart';
import '../../../widgets/section_card.dart';

/// Records an egg batch — a flock's egg production for one collection date
/// and grade, with optional per-house contributions (breeder-flock
/// -performance ticket 14, design doc section 8 and 12).
class EggBatchEntryScreen extends StatefulWidget {
  final FlockModel flock;
  final EggBatchDispatchService? service;
  final BreederEggGradeDefinitionRepository? gradeRepository;
  final PoultryHierarchyRepository? houseRepository;

  const EggBatchEntryScreen({
    super.key,
    required this.flock,
    this.service,
    this.gradeRepository,
    this.houseRepository,
  });

  @override
  State<EggBatchEntryScreen> createState() => _EggBatchEntryScreenState();
}

class _EggBatchEntryScreenState extends State<EggBatchEntryScreen> {
  late final EggBatchDispatchService _service =
      widget.service ?? EggBatchDispatchService();
  late final BreederEggGradeDefinitionRepository _gradeRepository =
      widget.gradeRepository ?? BreederEggGradeDefinitionRepository();
  late final PoultryHierarchyRepository _houseRepository =
      widget.houseRepository ?? PoultryHierarchyRepository();

  List<BreederEggGradeDefinition> _grades = [];
  List<HouseModel> _houses = [];
  String? _gradeId;
  DateTime _collectionDate = DateTime.now();
  final _eggCountController = TextEditingController();
  final Map<String, TextEditingController> _houseControllers = {};

  bool _loading = true;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _eggCountController.dispose();
    for (final c in _houseControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final grades = await _gradeRepository.listActiveGrades();
    final houses = await _houseRepository.listHouses(widget.flock.id);
    if (!mounted) return;
    setState(() {
      _grades = grades;
      _gradeId ??= grades.isNotEmpty ? grades.first.id : null;
      _houses = houses;
      for (final house in houses) {
        _houseControllers[house.id] = TextEditingController();
      }
      _loading = false;
    });
  }

  int _houseTotal() {
    var total = 0;
    for (final c in _houseControllers.values) {
      total += int.tryParse(c.text.trim()) ?? 0;
    }
    return total;
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _collectionDate,
      firstDate: widget.flock.entryDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _collectionDate = picked);
  }

  Future<void> _save() async {
    final gradeId = _gradeId;
    final eggCount = int.tryParse(_eggCountController.text.trim());
    if (gradeId == null) {
      setState(() => _error = 'Select an egg grade');
      return;
    }
    if (eggCount == null || eggCount < 0) {
      setState(() => _error = 'Enter a non-negative egg count');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final sources = <EggBatchHouseSourceInput>[
        for (final entry in _houseControllers.entries)
          if ((int.tryParse(entry.value.text.trim()) ?? 0) > 0)
            EggBatchHouseSourceInput(
              houseId: entry.key,
              eggCount: int.parse(entry.value.text.trim()),
            ),
      ];
      await _service.createBatch(
        flockId: widget.flock.id,
        collectionDate: _collectionDate,
        gradeId: gradeId,
        eggCount: eggCount,
        houseSources: sources,
      );
      if (!mounted) return;
      Navigator.pop(context, true);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(title: 'New egg batch'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFormCard(),
                  const SizedBox(height: AppSizes.cardPadding),
                  if (_houses.isNotEmpty) _buildHouseSourcesCard(),
                  const SizedBox(height: AppSizes.cardPadding),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: AppColors.statusError)),
                    const SizedBox(height: AppSizes.cardPadding),
                  ],
                  ElevatedButton(
                    key: const Key('egg_batch_save_button'),
                    onPressed: _saving ? null : _save,
                    child: Text(context.tr('Create batch')),
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFormCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Batch'), style: AppTextStyles.sectionTitle),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('egg_batch_grade_dropdown'),
            initialValue: _gradeId,
            decoration: InputDecoration(labelText: context.tr('Egg grade')),
            items: _grades
                .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                .toList(),
            onChanged: (value) => setState(() => _gradeId = value),
          ),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('egg_batch_date_field'),
            onTap: _pickDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          context.tr('Collection date'),
                          style: const TextStyle(fontSize: 12, color: Colors.grey),
                        ),
                        Text(
                          '${_collectionDate.year}-${_collectionDate.month.toString().padLeft(2, '0')}-${_collectionDate.day.toString().padLeft(2, '0')}',
                        ),
                      ],
                    ),
                  ),
                  const Icon(Icons.calendar_today, size: 18),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('egg_batch_count_field'),
            controller: _eggCountController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('Total eggs collected')),
          ),
        ],
      ),
    );
  }

  Widget _buildHouseSourcesCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr('Per-house contribution (optional)'),
            style: AppTextStyles.sectionTitle,
          ),
          const SizedBox(height: 8),
          for (final house in _houses)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: TextField(
                key: Key('egg_batch_house_field_${house.id}'),
                controller: _houseControllers[house.id],
                keyboardType: TextInputType.number,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(labelText: house.name),
              ),
            ),
          Text(
            '${context.tr('House total')}: ${_houseTotal()}',
            style: const TextStyle(fontSize: 12, color: Colors.grey),
          ),
        ],
      ),
    );
  }
}
