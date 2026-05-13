enum TemperaturePlace {
  outsideHatchery('Outside hatchery'),
  eggStorageRoom('Egg storage room'),
  chickHoldingArea('Chick holding area'),
  setterRoom('Setter room'),
  insideSetter('Inside setter'),
  hatcherRoom('Hatcher room'),
  insideHatcher('Inside hatcher');

  final String label;
  const TemperaturePlace(this.label);
}

TemperaturePlace temperaturePlaceFromName(String? name) {
  if (name == 'incubatorRoom') return TemperaturePlace.setterRoom;
  if (name == 'insideIncubator') return TemperaturePlace.insideSetter;
  return TemperaturePlace.values.firstWhere(
    (place) => place.name == name,
    orElse: () => TemperaturePlace.outsideHatchery,
  );
}

String goveeStationKeyForTemperaturePlace(TemperaturePlace place) {
  return switch (place) {
    TemperaturePlace.eggStorageRoom => 'egg',
    TemperaturePlace.chickHoldingArea => 'chicks',
    TemperaturePlace.setterRoom || TemperaturePlace.insideSetter => 'setters',
    TemperaturePlace.hatcherRoom ||
    TemperaturePlace.insideHatcher => 'hatchers',
    TemperaturePlace.outsideHatchery => '',
  };
}
