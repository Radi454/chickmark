import '../../../data/models/temperature_rh_model.dart';

class AuditGoveeSpot {
  final TemperaturePlace place;
  final String label;

  const AuditGoveeSpot({required this.place, required this.label});
}

AuditGoveeSpot? goveeSpotForStationKey(String stationKey) {
  return switch (stationKey) {
    'egg_storage' => const AuditGoveeSpot(
      place: TemperaturePlace.eggStorageRoom,
      label: 'Egg storage room',
    ),
    'chick_quality' => const AuditGoveeSpot(
      place: TemperaturePlace.chickHoldingArea,
      label: 'Chick holding area',
    ),
    'setter_optimizing' => const AuditGoveeSpot(
      place: TemperaturePlace.incubatorRoom,
      label: 'Incubator room',
    ),
    'hatcher_optimizing' => const AuditGoveeSpot(
      place: TemperaturePlace.hatcherRoom,
      label: 'Hatcher room',
    ),
    _ => null,
  };
}
