import '../../../data/models/temperature_rh_model.dart';

const List<TemperaturePlace> goveePlaceFlow = [
  TemperaturePlace.eggStorageRoom,
  TemperaturePlace.chickHoldingArea,
  TemperaturePlace.incubatorRoom,
  TemperaturePlace.hatcherRoom,
];

TemperaturePlace? nextGoveePlace(TemperaturePlace place) {
  final index = goveePlaceFlow.indexOf(place);
  if (index < 0 || index == goveePlaceFlow.length - 1) return null;
  return goveePlaceFlow[index + 1];
}
