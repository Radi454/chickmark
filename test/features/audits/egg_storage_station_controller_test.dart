import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/features/audits/screens/egg_storage_screen.dart';

void main() {
  test(
    'station controller can prepare for exit when no screen is attached',
    () async {
      final controller = EggStorageStationController();

      final result = await controller.prepareForStationExit();

      expect(result, isTrue);
    },
  );
}
