import 'package:characters/characters.dart';

class PasswordPolicy {
  const PasswordPolicy._();

  static const minLength = 12;
  static const allowedSymbols = r'''!@#$%^&*()_+-=[]{};'\:"|<>?,./`~''';

  static bool hasLowercase(String password) =>
      password.contains(RegExp(r'[a-z]'));

  static bool hasUppercase(String password) =>
      password.contains(RegExp(r'[A-Z]'));

  static bool hasNumber(String password) => password.contains(RegExp(r'\d'));

  static int characterCount(String password) => password.characters.length;

  static bool hasSymbol(String password) {
    return password.runes.any(
      (rune) => allowedSymbols.contains(String.fromCharCode(rune)),
    );
  }

  static bool isValid(String password) {
    return characterCount(password) >= minLength &&
        hasLowercase(password) &&
        hasUppercase(password) &&
        hasNumber(password) &&
        hasSymbol(password);
  }

  static String? validationMessage(String? password) {
    if (password == null || password.isEmpty) {
      return 'Please enter a password';
    }
    if (characterCount(password) < minLength) {
      return 'Password must be at least 12 characters';
    }
    if (!hasLowercase(password)) {
      return 'Password must contain a lowercase letter';
    }
    if (!hasUppercase(password)) {
      return 'Password must contain an uppercase letter';
    }
    if (!hasNumber(password)) {
      return 'Password must contain at least one number';
    }
    if (!hasSymbol(password)) {
      return 'Password must contain at least one symbol';
    }
    return null;
  }

  static int strengthScore(String password) {
    if (password.isEmpty) return 0;
    final checks = [
      characterCount(password) >= minLength,
      hasLowercase(password),
      hasUppercase(password),
      hasNumber(password),
      hasSymbol(password),
    ];
    final met = checks.where((check) => check).length;
    if (met <= 1) return 1;
    if (met <= 3) return 2;
    if (met == 4) return 3;
    return 4;
  }
}
