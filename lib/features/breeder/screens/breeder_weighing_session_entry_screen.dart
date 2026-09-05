import 'package:hatchaudit/localized_material.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/breeder_weighing_session_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/poultry_hierarchy_models.dart';
import '../../../data/repositories/breeder_weighing_sample_repository.dart';
import '../../../data/repositories/poultry_hierarchy_repository.dart';
import '../../../services/breeder/breeder_weighing_service.dart';
import '../../../widgets/section_card.dart';

/// A documented, non-exhaustive list of common weighing methods offered by
/// the entry UI. `breeder_weighing_sessions.method` is free text (see
/// `createBreederWeighingSessionsTable`'s doc comment for why), so this is
/// a convenience list, not a closed set — the field also accepts custom
/// text.
const List<String> kBreederWeighingMethodSuggestions = [
  'Individual bird scale',
  'Batch/platform scale',
  'Walk-over scale',
];

/// Create/view a periodic weighing session (breeder-flock-performance
/// ticket 13, design doc section 5.1 and 9). Records flock, house, sex,
/// date, method, and sample size; individual bird weights are optional.
/// Derived mean weight, uniformity, and coefficient of variation are shown
/// alongside the official body-weight target for the flock's age and sex,
/// with uniformity/CV shown without a target since the Ross 308 source
/// publishes neither (ticket 03).
class BreederWeighingSessionEntryScreen extends StatefulWidget {
  final FlockModel flock;
  final BreederWeighingSession? session;
  final BreederWeighingService? service;
  final PoultryHierarchyRepository? houseRepository;
  final BreederWeighingSampleRepository? sampleRepository;

  const BreederWeighingSessionEntryScreen({
    super.key,
    required this.flock,
    this.session,
    this.service,
    this.houseRepository,
    this.sampleRepository,
  });

  @override
  State<BreederWeighingSessionEntryScreen> createState() =>
      _BreederWeighingSessionEntryScreenState();
}

class _BreederWeighingSessionEntryScreenState
    extends State<BreederWeighingSessionEntryScreen> {
  late final BreederWeighingService _service =
      widget.service ?? BreederWeighingService();
  late final PoultryHierarchyRepository _houseRepository =
      widget.houseRepository ?? PoultryHierarchyRepository();
  late final BreederWeighingSampleRepository _sampleRepository =
      widget.sampleRepository ?? BreederWeighingSampleRepository();

  List<HouseModel> _houses = [];
  String? _houseId;
  String _sex = BreederWeighingSessionSex.female;
  DateTime _sessionDate = DateTime.now();
  final _methodController = TextEditingController();
  final _sampleSizeController = TextEditingController();
  final _weightControllers = <TextEditingController>[];

  BreederWeighingSession? _session;
  bool _loading = true;
  bool _saving = false;
  String? _error;

  bool get _isNew => widget.session == null;

  @override
  void initState() {
    super.initState();
    _session = widget.session;
    if (_session != null) {
      _houseId = _session!.houseId;
      _sex = _session!.sex;
      _sessionDate = _session!.sessionDate;
      _methodController.text = _session!.method;
      _sampleSizeController.text = _session!.sampleSize.toString();
    }
    _load();
  }

  @override
  void dispose() {
    _methodController.dispose();
    _sampleSizeController.dispose();
    for (final c in _weightControllers) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final houses = await _houseRepository.listHouses(widget.flock.id);
    List<double> existingWeights = const [];
    if (_session != null) {
      final samples = await _sampleRepository.getForSession(_session!.id);
      existingWeights = samples.map((s) => s.weightGrams).toList();
    }
    if (!mounted) return;
    setState(() {
      _houses = houses;
      _houseId ??= houses.isNotEmpty ? houses.first.id : null;
      for (final weight in existingWeights) {
        _weightControllers.add(
          TextEditingController(text: _formatWeight(weight)),
        );
      }
      _loading = false;
    });
  }

  String _formatWeight(double weight) =>
      weight == weight.roundToDouble() ? weight.toInt().toString() : weight.toString();

  void _addWeightField() {
    setState(() => _weightControllers.add(TextEditingController()));
  }

  void _removeWeightField(int index) {
    setState(() => _weightControllers.removeAt(index).dispose());
  }

  List<double> _parsedWeights() {
    return _weightControllers
        .map((c) => double.tryParse(c.text.trim()))
        .whereType<double>()
        .toList();
  }

  Future<void> _save() async {
    final houseId = _houseId;
    final method = _methodController.text.trim();
    final sampleSize = int.tryParse(_sampleSizeController.text.trim());

    if (houseId == null) {
      setState(() => _error = 'Select a house');
      return;
    }
    if (method.isEmpty) {
      setState(() => _error = 'Enter a weighing method');
      return;
    }
    if (sampleSize == null || sampleSize <= 0) {
      setState(() => _error = 'Enter a positive sample size');
      return;
    }
    final weights = _parsedWeights();
    if (weights.any((w) => w < 0)) {
      setState(() => _error = 'Weights cannot be negative');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      BreederWeighingSession saved;
      if (_isNew) {
        saved = await _service.createSession(
          flock: widget.flock,
          houseId: houseId,
          sessionDate: _sessionDate,
          sex: _sex,
          method: method,
          sampleSize: sampleSize,
          weights: weights,
        );
      } else {
        final updatedFields = _session!.copyWith(
          houseId: houseId,
          sex: _sex,
          sessionDate: _sessionDate,
          method: method,
          sampleSize: sampleSize,
        );
        await _service.sessionRepository.update(updatedFields);
        saved = await _service.updateSamples(
          session: updatedFields,
          flock: widget.flock,
          weights: weights,
        );
      }
      if (!mounted) return;
      setState(() {
        _session = saved;
        _saving = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = error.toString();
      });
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _sessionDate,
      firstDate: widget.flock.entryDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _sessionDate = picked);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: GradientAppBar(
        title: _isNew ? 'New weighing session' : 'Weighing session',
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildFormCard(),
                  const SizedBox(height: AppSizes.cardPadding),
                  _buildWeightsCard(),
                  const SizedBox(height: AppSizes.cardPadding),
                  if (_session != null) _buildResultsCard(_session!),
                  const SizedBox(height: AppSizes.cardPadding),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: AppColors.statusError)),
                    const SizedBox(height: AppSizes.cardPadding),
                  ],
                  ElevatedButton(
                    onPressed: _saving ? null : _save,
                    child: Text(context.tr(_isNew ? 'Create session' : 'Save')),
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
          Text(context.tr('Session'), style: AppTextStyles.sectionTitle),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('weighing_house_dropdown'),
            initialValue: _houseId,
            decoration: InputDecoration(labelText: context.tr('House')),
            items: _houses
                .map((h) => DropdownMenuItem(value: h.id, child: Text(h.name)))
                .toList(),
            onChanged: (value) => setState(() => _houseId = value),
          ),
          const SizedBox(height: 12),
          DropdownButtonFormField<String>(
            key: const Key('weighing_sex_dropdown'),
            initialValue: _sex,
            decoration: InputDecoration(labelText: context.tr('Sex')),
            items: BreederWeighingSessionSex.all
                .map(
                  (s) => DropdownMenuItem(
                    value: s,
                    child: Text(
                      s == BreederWeighingSessionSex.female
                          ? context.tr('Female')
                          : context.tr('Male'),
                    ),
                  ),
                )
                .toList(),
            onChanged: (value) => setState(() => _sex = value!),
          ),
          const SizedBox(height: 12),
          InkWell(
            key: const Key('weighing_date_field'),
            onTap: _pickDate,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(context.tr('Date'), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                        Text(
                          '${_sessionDate.year}-${_sessionDate.month.toString().padLeft(2, '0')}-${_sessionDate.day.toString().padLeft(2, '0')}',
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
            key: const Key('weighing_method_field'),
            controller: _methodController,
            decoration: InputDecoration(labelText: context.tr('Weighing method')),
          ),
          Wrap(
            spacing: 8,
            children: kBreederWeighingMethodSuggestions
                .map(
                  (m) => ActionChip(
                    label: Text(m),
                    onPressed: () => setState(() => _methodController.text = m),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 12),
          TextField(
            key: const Key('weighing_sample_size_field'),
            controller: _sampleSizeController,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(labelText: context.tr('Sample size')),
          ),
        ],
      ),
    );
  }

  Widget _buildWeightsCard() {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  context.tr('Individual weights (optional)'),
                  style: AppTextStyles.sectionTitle,
                ),
              ),
              IconButton(
                key: const Key('weighing_add_weight_button'),
                icon: const Icon(Icons.add),
                onPressed: _addWeightField,
              ),
            ],
          ),
          for (var i = 0; i < _weightControllers.length; i++)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: Key('weighing_weight_field_$i'),
                      controller: _weightControllers[i],
                      keyboardType: const TextInputType.numberWithOptions(
                        decimal: true,
                      ),
                      decoration: InputDecoration(
                        labelText: '${context.tr('Weight (g)')} ${i + 1}',
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.remove_circle_outline),
                    onPressed: () => _removeWeightField(i),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildResultsCard(BreederWeighingSession session) {
    return SectionCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(context.tr('Results'), style: AppTextStyles.sectionTitle),
          const SizedBox(height: 8),
          if (!session.hasDerivedFigures)
            Text(context.tr('Summary only — no individual weights recorded.'))
          else ...[
            _resultRow(
              context.tr('Mean weight'),
              '${session.derivedMeanWeightG} g',
              target: session.comparisonTargetWeightG != null
                  ? '${context.tr('Target')}: ${session.comparisonTargetWeightG} g'
                  : context.tr('No official target for this age'),
            ),
            _resultRow(
              context.tr('Uniformity (±10% of mean)'),
              '${session.derivedUniformityPct}%',
              target: context.tr('No official target published'),
            ),
            _resultRow(
              context.tr('Coefficient of variation'),
              session.derivedCvPct != null ? '${session.derivedCvPct}%' : '—',
              target: context.tr('No official target published'),
            ),
          ],
          if (session.comparisonProfileGuideVersion != null) ...[
            const SizedBox(height: 8),
            Text(
              '${context.tr('Benchmark')}: ${session.comparisonProfileGuideVersion}',
              style: AppTextStyles.body.copyWith(fontSize: 12, color: Colors.grey),
            ),
          ],
        ],
      ),
    );
  }

  Widget _resultRow(String label, String value, {required String target}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: AppTextStyles.body),
                Text(target, style: const TextStyle(fontSize: 12, color: Colors.grey)),
              ],
            ),
          ),
          Text(value, style: AppTextStyles.body.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }
}
