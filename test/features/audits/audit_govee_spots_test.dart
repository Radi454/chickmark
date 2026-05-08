import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/audits/utils/audit_govee_spots.dart';

void main() {
  group('goveeSpotForStationKey', () {
    test('maps walk-through stations to hatchery temperature places', () {
      expect(
        goveeSpotForStationKey('egg')?.place,
        TemperaturePlace.eggStorageRoom,
      );
      expect(
        goveeSpotForStationKey('chicks')?.place,
        TemperaturePlace.chickHoldingArea,
      );
      expect(
        goveeSpotForStationKey('setters')?.place,
        TemperaturePlace.setterRoom,
      );
      expect(
        goveeSpotForStationKey('setters')?.insideMachinePlace,
        TemperaturePlace.insideSetter,
      );
      expect(
        goveeSpotForStationKey('hatchers')?.place,
        TemperaturePlace.hatcherRoom,
      );
      expect(
        goveeSpotForStationKey('hatchers')?.insideMachinePlace,
        TemperaturePlace.insideHatcher,
      );
    });

    test('omits stations without a clear room-level Govee spot', () {
      expect(goveeSpotForStationKey('hatch_analysis_egg_breakouts'), isNull);
    });
  });
}
