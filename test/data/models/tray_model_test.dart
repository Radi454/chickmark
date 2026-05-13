import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/tray_model.dart';

void main() {
  group('HatchResultsTray', () {
    test('calculates fertility from fertile eggs over tray size', () {
      final tray = HatchResultsTray(
        trayId: 'tray-1',
        position: 'top',
        traySize: 150,
        infertile: 15,
      );

      expect(tray.fertilityPct, 90.0);
    });

    test('does not produce impossible fertility percentages', () {
      final tray = HatchResultsTray(
        trayId: 'tray-1',
        position: 'top',
        traySize: 150,
        infertile: 151,
      );

      expect(tray.fertilityPct, 0.0);
    });
  });
}
