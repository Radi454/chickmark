import 'package:flutter/foundation.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';
import 'package:hatchaudit/data/models/bmk_operational_standard_model.dart';
import 'package:hatchaudit/data/repositories/bmk_repository.dart';

enum EbType { fresh, candled, residue }

class BmkProvider extends ChangeNotifier {
  final BmkRepository _repository;

  String _selectedBreed = 'Ross308';
  int _selectedBreedAge = 25;
  List<int> _breedAges = [];
  BmkBreedModel? _breedRow;
  EbType _selectedEbType = EbType.fresh;
  int _selectedEbAge = 25;
  List<int> _ebAges = [];
  BmkEggBreakoutModel? _ebRow;
  String? _selectedHatcheryId;
  List<BmkOperationalHatcheryOption> _operationalHatcheries = [];
  List<BmkOperationalStandardModel> _operationalStandards = [];
  String? _selectedOperationalMetricKey;

  String get selectedBreed => _selectedBreed;
  int get selectedBreedAge => _selectedBreedAge;
  List<int> get breedAges => _breedAges;
  BmkBreedModel? get breedRow => _breedRow;
  EbType get selectedEbType => _selectedEbType;
  int get selectedEbAge => _selectedEbAge;
  List<int> get ebAges => _ebAges;
  BmkEggBreakoutModel? get ebRow => _ebRow;
  String? get selectedHatcheryId => _selectedHatcheryId;
  List<BmkOperationalHatcheryOption> get operationalHatcheries =>
      List.unmodifiable(_operationalHatcheries);
  List<BmkOperationalStandardModel> get operationalStandards =>
      List.unmodifiable(_operationalStandards);
  BmkOperationalStandardModel? get selectedOperationalStandard {
    if (_operationalStandards.isEmpty) return null;
    final selectedKey = _selectedOperationalMetricKey;
    if (selectedKey == null) return _operationalStandards.first;
    for (final row in _operationalStandards) {
      if (row.metricKey == selectedKey) return row;
    }
    return _operationalStandards.first;
  }

  static const List<String> breeds = [
    'Ross308',
    'Arbo',
    'Avian',
    'Cobb500',
    'Hubbard',
    'IR',
  ];

  bool _isInitialized = false;

  BmkProvider({BmkRepository? repository})
    : _repository = repository ?? BmkRepository();

  Future<void> ensureInitialized() async {
    if (_isInitialized) return;
    _isInitialized = true;
    await loadBreedBenchmarks();
    await loadEbAges();
    await loadEggBreakout();
    await loadOperationalHatcheries(notify: false);
    await loadOperationalStandards();
  }

  Future<void> loadBreedBenchmarks({bool resetSelectedAge = false}) async {
    _breedAges = await _repository.getBreedAges(_selectedBreed);
    if (_breedAges.isNotEmpty) {
      if (resetSelectedAge || !_breedAges.contains(_selectedBreedAge)) {
        _selectedBreedAge = _breedAges.first;
      }
      await loadBreedRow(notify: false);
    } else {
      _breedRow = null;
    }
    notifyListeners();
  }

  Future<void> loadBreedRow({bool notify = true}) async {
    _breedRow = await _repository.getBreedBenchmark(
      _selectedBreed,
      _selectedBreedAge,
    );
    if (notify) notifyListeners();
  }

  Future<void> loadEbAges() async {
    _ebAges = await _repository.getEggBreakoutAges();
    if (_ebAges.isNotEmpty && !_ebAges.contains(_selectedEbAge)) {
      _selectedEbAge = _ebAges.first;
    }
    notifyListeners();
  }

  Future<void> loadEggBreakout({bool notify = true}) async {
    _ebRow = await _repository.getEggBreakoutBenchmark(_selectedEbAge);
    if (notify) notifyListeners();
  }

  Future<void> loadOperationalStandards({bool notify = true}) async {
    _operationalStandards = await _repository.getOperationalStandards(
      hatcheryId: _selectedHatcheryId,
    );
    if (_operationalStandards.isNotEmpty &&
        !_operationalStandards.any(
          (row) => row.metricKey == _selectedOperationalMetricKey,
        )) {
      _selectedOperationalMetricKey = _operationalStandards.first.metricKey;
    }
    if (notify) notifyListeners();
  }

  Future<void> loadOperationalHatcheries({bool notify = true}) async {
    _operationalHatcheries = await _repository.getOperationalHatcheries();
    if (_selectedHatcheryId != null &&
        !_operationalHatcheries.any((row) => row.id == _selectedHatcheryId)) {
      _selectedHatcheryId = null;
    }
    if (notify) notifyListeners();
  }

  Future<void> saveSelectedBreedBenchmark({
    required double hatchabilityPct,
    required double fertilityPct,
    required double hofPct,
    required double productionPct,
    required double eggWeightG,
    required double chickWeightG,
  }) async {
    final row = BmkBreedModel(
      id: '$_selectedBreed-$_selectedBreedAge',
      breed: _selectedBreed,
      ageWeek: _selectedBreedAge,
      hatchabilityPct: hatchabilityPct,
      fertilityPct: fertilityPct,
      hofPct: hofPct,
      productionPct: productionPct,
      eggWeightG: eggWeightG,
      chickWeightG: chickWeightG,
    );
    await _repository.upsertBmkBreed(row.toMap());
    await loadBreedRow();
  }

  Future<void> saveSelectedEggBreakoutBenchmark({
    required double infertilePct,
    required double early24hPct,
    required double early48hPct,
    required double bloodRingPct,
    required double blackEyePct,
    required double earlyDeadPct,
    required double midDeadPct,
    required double lateDeadPct,
    required double externalPipPct,
    required double crackedPct,
    required double contamPct,
  }) async {
    final row = BmkEggBreakoutModel(
      id: 'eb-$_selectedEbAge',
      ageWeek: _selectedEbAge,
      infertilePct: infertilePct,
      early24hPct: early24hPct,
      early48hPct: early48hPct,
      bloodRingPct: bloodRingPct,
      blackEyePct: blackEyePct,
      earlyDeadPct: earlyDeadPct,
      midDeadPct: midDeadPct,
      lateDeadPct: lateDeadPct,
      externalPipPct: externalPipPct,
      crackedPct: crackedPct,
      contamPct: contamPct,
    );
    await _repository.upsertBmkEggBreakout(row.toMap());
    await loadEggBreakout();
  }

  Future<void> saveSelectedOperationalStandard({
    double? minValue,
    double? maxValue,
    double? targetValue,
    String? notes,
  }) async {
    final selected = selectedOperationalStandard;
    if (selected == null) return;
    final hatcheryId = _selectedHatcheryId;
    final id = hatcheryId == null || hatcheryId.isEmpty
        ? 'global-${selected.metricKey}'
        : '$hatcheryId-${selected.metricKey}';
    await _repository.upsertOperationalStandard(
      selected.copyWith(
        id: id,
        hatcheryId: hatcheryId,
        minValue: minValue,
        maxValue: maxValue,
        targetValue: targetValue,
        notes: notes,
      ),
    );
    await loadOperationalStandards();
  }

  void setBreed(String breed) {
    _selectedBreed = breed;
    loadBreedBenchmarks(resetSelectedAge: true);
  }

  void setBreedAge(int age) {
    _selectedBreedAge = age;
    loadBreedRow();
  }

  void setEbType(EbType type) {
    _selectedEbType = type;
    notifyListeners();
  }

  void setEbAge(int age) {
    _selectedEbAge = age;
    loadEggBreakout();
  }

  void setOperationalMetric(String metricKey) {
    _selectedOperationalMetricKey = metricKey;
    notifyListeners();
  }

  void setOperationalHatchery(String? hatcheryId) {
    _selectedHatcheryId = hatcheryId;
    loadOperationalStandards();
  }
}
