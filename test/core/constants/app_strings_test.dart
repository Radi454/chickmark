import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/constants/app_strings.dart';

void main() {
  test('common action labels stay centralized', () {
    expect(AppStrings.cancel, 'Cancel');
    expect(AppStrings.save, 'Save');
    expect(AppStrings.retry, 'Retry');
    expect(AppStrings.signOut, 'Sign Out');
  });
}
