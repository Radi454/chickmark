import 'package:hatchaudit/localized_material.dart';

import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../data/models/breeder_egg_grade_definition_model.dart';
import '../../../data/models/flock_model.dart';
import '../../../data/models/hatchery_model.dart';
import '../../../data/repositories/breeder_egg_grade_definition_repository.dart';
import '../../../data/repositories/hatchery_repository.dart';
import '../../../services/breeder/egg_batch_dispatch_service.dart';
import '../../../widgets/section_card.dart';
import 'egg_shipment_detail_screen.dart';

/// Creates a Draft hatchery-dispatch shipment for one flock
/// (breeder-flock-performance ticket 14, design doc section 8 and 12).
/// Batches are attached afterward, in [EggShipmentDetailScreen].
class EggShipmentEntryScreen extends StatefulWidget {
  final FlockModel flock;
  final EggBatchDispatchService? service;
  final BreederEggGradeDefinitionRepository? gradeRepository;
  final HatcheryRepository? hatcheryRepository;

  /// Test-only override forwarded to the [EggShipmentDetailScreen] this
  /// screen navigates to on save, so a widget test can avoid wiring a real
  /// `AuthProvider` just to read the signed-in user's id (which this
  /// screen itself never needs — creating a Draft shipment records no
  /// actor).
  final String? actorUserIdOverride;

  const EggShipmentEntryScreen({
    super.key,
    required this.flock,
    this.service,
    this.gradeRepository,
    this.hatcheryRepository,
    this.actorUserIdOverride,
  });

  @override
  State<EggShipmentEntryScreen> createState() => _EggShipmentEntryScreenState();
}

class _EggShipmentEntryScreenState extends State<EggShipmentEntryScreen> {
  late final EggBatchDispatchService _service =
      widget.service ?? EggBatchDispatchService();
  late final BreederEggGradeDefinitionRepository _gradeRepository =
      widget.gradeRepository ?? BreederEggGradeDefinitionRepository();
  late final HatcheryRepository _hatcheryRepository =
      widget.hatcheryRepository ?? HatcheryRepository();

  List<BreederEggGradeDefinition> _grades = [];
  List<HatcheryModel> _hatcheries = [];
  String? _gradeId;
  String? _hatcheryId;
  DateTime _shipmentDate = DateTime.now();
  final _notesController = TextEditingController();

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
    _notesController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final grades = await _gradeRepository.listActiveGrades();
    final hatcheries = await _hatcheryRepository.getHatcheriesByCustomer(
      widget.flock.customerId,
    );
    if (!mounted) return;
    setState(() {
      _grades = grades;
      _gradeId ??= grades.isNotEmpty ? grades.first.id : null;
      _hatcheries = hatcheries;
      _hatcheryId ??= hatcheries.isNotEmpty ? hatcheries.first.id : null;
      _loading = false;
    });
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _shipmentDate,
      firstDate: widget.flock.entryDate,
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _shipmentDate = picked);
  }

  Future<void> _save() async {
    final gradeId = _gradeId;
    final hatcheryId = _hatcheryId;
    if (gradeId == null) {
      setState(() => _error = 'Select an egg grade');
      return;
    }
    if (hatcheryId == null) {
      setState(() => _error = 'Select a hatchery');
      return;
    }

    setState(() {
      _saving = true;
      _error = null;
    });

    try {
      final shipment = await _service.createShipment(
        flockId: widget.flock.id,
        hatcheryId: hatcheryId,
        gradeId: gradeId,
        shipmentDate: _shipmentDate,
        notes: _notesController.text.trim().isEmpty
            ? null
            : _notesController.text.trim(),
      );
      if (!mounted) return;
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => EggShipmentDetailScreen(
            flock: widget.flock,
            shipment: shipment,
            service: _service,
            actorUserIdOverride: widget.actorUserIdOverride,
          ),
        ),
      );
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
      appBar: GradientAppBar(title: 'New shipment'),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(AppSizes.cardPadding),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SectionCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(context.tr('Shipment'), style: AppTextStyles.sectionTitle),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const Key('egg_shipment_hatchery_dropdown'),
                          initialValue: _hatcheryId,
                          decoration: InputDecoration(labelText: context.tr('Hatchery')),
                          items: _hatcheries
                              .map((h) => DropdownMenuItem(value: h.id, child: Text(h.name)))
                              .toList(),
                          onChanged: (value) => setState(() => _hatcheryId = value),
                        ),
                        const SizedBox(height: 12),
                        DropdownButtonFormField<String>(
                          key: const Key('egg_shipment_grade_dropdown'),
                          initialValue: _gradeId,
                          decoration: InputDecoration(labelText: context.tr('Egg grade')),
                          items: _grades
                              .map((g) => DropdownMenuItem(value: g.id, child: Text(g.name)))
                              .toList(),
                          onChanged: (value) => setState(() => _gradeId = value),
                        ),
                        const SizedBox(height: 12),
                        InkWell(
                          key: const Key('egg_shipment_date_field'),
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
                                        context.tr('Shipment date'),
                                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                                      ),
                                      Text(
                                        '${_shipmentDate.year}-${_shipmentDate.month.toString().padLeft(2, '0')}-${_shipmentDate.day.toString().padLeft(2, '0')}',
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
                          key: const Key('egg_shipment_notes_field'),
                          controller: _notesController,
                          decoration: InputDecoration(labelText: context.tr('Notes (optional)')),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSizes.cardPadding),
                  if (_error != null) ...[
                    Text(_error!, style: TextStyle(color: AppColors.statusError)),
                    const SizedBox(height: AppSizes.cardPadding),
                  ],
                  ElevatedButton(
                    key: const Key('egg_shipment_save_button'),
                    onPressed: _saving ? null : _save,
                    child: Text(context.tr('Create shipment')),
                  ),
                ],
              ),
            ),
    );
  }
}
