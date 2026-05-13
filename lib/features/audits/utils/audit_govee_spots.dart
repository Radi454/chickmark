import '../../../data/models/temperature_rh_model.dart';

class AuditGoveeSpot {
  final TemperaturePlace place;
  final TemperaturePlace? insideMachinePlace;
  final String label;

  const AuditGoveeSpot({
    required this.place,
    required this.label,
    this.insideMachinePlace,
  });
}

AuditGoveeSpot? goveeSpotForStationKey(String stationKey) {
  return switch (stationKey) {
    'egg' => const AuditGoveeSpot(
      place: TemperaturePlace.eggStorageRoom,
      label: 'Egg storage room',
    ),
    'chicks' => const AuditGoveeSpot(
      place: TemperaturePlace.chickHoldingArea,
      label: 'Chick holding area',
    ),
    'setters' => const AuditGoveeSpot(
      place: TemperaturePlace.setterRoom,
      label: 'Setter room',
      insideMachinePlace: TemperaturePlace.insideSetter,
    ),
    'hatchers' => const AuditGoveeSpot(
      place: TemperaturePlace.hatcherRoom,
      label: 'Hatcher room',
      insideMachinePlace: TemperaturePlace.insideHatcher,
    ),
    _ => null,
  };
}
