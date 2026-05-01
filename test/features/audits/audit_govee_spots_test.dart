import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/models/temperature_rh_model.dart';
import 'package:hatchaudit/features/audits/utils/audit_govee_spots.dart';

void main() {
  group('goveeSpotForStationKey', () {
    test('maps walk-through stations to hatchery temperature places', () {
      expect(
        goveeSpotForStationKey('egg_storage')?.place,
        TemperaturePlace.eggStorageRoom,
      );
      expect(
        goveeSpotForStationKey('chick_quality')?.place,
        TemperaturePlace.chickHoldingArea,
      );
      expect(
        goveeSpotForStationKey('setter_optimizing')?.place,
        TemperaturePlace.incubatorRoom,
      );
      expect(
        goveeSpotForStationKey('hatcher_optimizing')?.place,
        TemperaturePlace.hatcherRoom,
      );
    });

    test('omits stations without a clear room-level Govee spot', () {
      expect(goveeSpotForStationKey('hatch_analysis'), isNull);
    });
  });
}
