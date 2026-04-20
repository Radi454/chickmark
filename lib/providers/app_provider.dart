import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../data/models/user_model.dart';

enum TempUnit { fahrenheit, celsius }

class AppProvider extends ChangeNotifier {
  UserModel? _currentUser;
  TempUnit _tempUnit = TempUnit.fahrenheit;
  static const String _tempUnitKey = 'temp_unit';

  UserModel? get currentUser => _currentUser;
  TempUnit get tempUnit => _tempUnit;

  AppProvider() {
    _loadTempUnit();
  }

  Future<void> _loadTempUnit() async {
    final prefs = await SharedPreferences.getInstance();
    final tempUnitIndex = prefs.getInt(_tempUnitKey) ?? 0;
    _tempUnit = TempUnit.values[tempUnitIndex];
    notifyListeners();
  }

  void setCurrentUser(UserModel? user) {
    _currentUser = user;
    notifyListeners();
  }

  Future<void> setTempUnit(TempUnit unit) async {
    _tempUnit = unit;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_tempUnitKey, unit.index);
    notifyListeners();
  }
}
