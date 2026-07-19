import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/security/password_policy.dart';

void main() {
  test('accepts the live Supabase password requirements', () {
    expect(PasswordPolicy.isValid('StrongPass1!'), isTrue);
    expect(PasswordPolicy.validationMessage('StrongPass1!'), isNull);
  });

  test('rejects every missing password requirement', () {
    expect(
      PasswordPolicy.validationMessage('Short1!'),
      contains('12 characters'),
    );
    expect(
      PasswordPolicy.validationMessage('ALLUPPERCASE1!'),
      contains('lowercase'),
    );
    expect(
      PasswordPolicy.validationMessage('alllowercase1!'),
      contains('uppercase'),
    );
    expect(
      PasswordPolicy.validationMessage('NoNumberHere!'),
      contains('number'),
    );
    expect(
      PasswordPolicy.validationMessage('NoSymbolHere1'),
      contains('symbol'),
    );
  });

  test('strength is full only when all server requirements are met', () {
    expect(PasswordPolicy.strengthScore(''), 0);
    expect(PasswordPolicy.strengthScore('short'), lessThan(4));
    expect(PasswordPolicy.strengthScore('StrongPass12'), 3);
    expect(PasswordPolicy.strengthScore('StrongPass1!'), 4);
  });

  test('counts Unicode grapheme clusters instead of UTF-16 code units', () {
    const elevenCharacters = 'Aa1!123456😀';
    const twelveCharacters = 'Aa1!1234567😀';

    expect(elevenCharacters.length, PasswordPolicy.minLength);
    expect(PasswordPolicy.characterCount(elevenCharacters), 11);
    expect(PasswordPolicy.isValid(elevenCharacters), isFalse);
    expect(
      PasswordPolicy.validationMessage(elevenCharacters),
      contains('12 characters'),
    );
    expect(PasswordPolicy.strengthScore(elevenCharacters), 3);

    expect(PasswordPolicy.characterCount(twelveCharacters), 12);
    expect(PasswordPolicy.isValid(twelveCharacters), isTrue);
  });
}
