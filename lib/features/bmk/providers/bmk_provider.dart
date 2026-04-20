import 'package:flutter/foundation.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/bmk_breed_model.dart';
import 'package:hatchaudit/data/models/bmk_egg_breakout_model.dart';

enum EbType { fresh, candled, residue }

class BmkProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  String _selectedBreed = 'Ross308';
  int _selectedBreedAge = 25;
  List<int> _breedAges = [];
  BmkBreedModel? _breedRow;
  EbType _selectedEbType = EbType.fresh;
  int _selectedEbAge = 25;
  List<int> _ebAges = [];
  BmkEggBreakoutModel? _ebRow;

  String get selectedBreed => _selectedBreed;
  int get selectedBreedAge => _selectedBreedAge;
  List<int> get breedAges => _breedAges;
  BmkBreedModel? get breedRow => _breedRow;
  EbType get selectedEbType => _selectedEbType;
  int get selectedEbAge => _selectedEbAge;
  List<int> get ebAges => _ebAges;
  BmkEggBreakoutModel? get ebRow => _ebRow;

  static const List<String> breeds = [
    'Ross308',
    'Arbo',
    'Avian',
    'Cobb500',
    'Hubbard',
    'IR',
  ];

  BmkProvider() {
    loadBreedBenchmarks();
    loadEbAges();
    loadEggBreakout();
  }

  Future<void> loadBreedBenchmarks() async {
    final database = await _db.db;
    final results = await database.rawQuery(
      '''
      SELECT DISTINCT ageWeek
      FROM bmk_breeds
      WHERE breed = ?
      ORDER BY ageWeek ASC
      ''',
      [_selectedBreed],
    );
    _breedAges = results.map((r) => r['ageWeek'] as int).toList();
    if (_breedAges.isNotEmpty) {
      _selectedBreedAge = _breedAges.first;
      await loadBreedRow();
    }
    notifyListeners();
  }

  Future<void> loadBreedRow() async {
    final database = await _db.db;
    final results = await database.query(
      'bmk_breeds',
      where: 'breed = ? AND ageWeek = ?',
      whereArgs: [_selectedBreed, _selectedBreedAge],
      limit: 1,
    );
    if (results.isNotEmpty) {
      _breedRow = BmkBreedModel.fromMap(results.first);
    } else {
      _breedRow = null;
    }
    notifyListeners();
  }

  Future<void> loadEbAges() async {
    final database = await _db.db;
    final results = await database.rawQuery(
      'SELECT DISTINCT ageWeek FROM bmk_egg_breakout ORDER BY ageWeek',
    );
    _ebAges = results.map((r) => r['ageWeek'] as int).toList();
    if (_ebAges.isNotEmpty && !_ebAges.contains(_selectedEbAge)) {
      _selectedEbAge = _ebAges.first;
    }
    notifyListeners();
  }

  Future<void> loadEggBreakout() async {
    final database = await _db.db;
    final results = await database.query(
      'bmk_egg_breakout',
      where: 'ageWeek = ?',
      whereArgs: [_selectedEbAge],
      limit: 1,
    );
    if (results.isNotEmpty) {
      _ebRow = BmkEggBreakoutModel.fromMap(results.first);
    } else {
      _ebRow = null;
    }
    notifyListeners();
  }

  void setBreed(String breed) {
    _selectedBreed = breed;
    loadBreedBenchmarks();
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
}
