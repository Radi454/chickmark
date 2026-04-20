class BmkBreedModel {
  final String id;
  final String breed;
  final int ageWeek;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double productionPct;
  final double eggWeightG;
  final double chickWeightG;

  BmkBreedModel({
    required this.id,
    required this.breed,
    required this.ageWeek,
    this.hatchabilityPct = 0.0,
    this.fertilityPct = 0.0,
    this.hofPct = 0.0,
    this.productionPct = 0.0,
    this.eggWeightG = 0.0,
    this.chickWeightG = 0.0,
  });

  factory BmkBreedModel.fromMap(Map<String, dynamic> map) {
    return BmkBreedModel(
      id: map['id'],
      breed: map['breed'],
      ageWeek: map['ageWeek'],
      hatchabilityPct: map['hatchabilityPct']?.toDouble() ?? 0.0,
      fertilityPct: map['fertilityPct']?.toDouble() ?? 0.0,
      hofPct: map['hofPct']?.toDouble() ?? 0.0,
      productionPct: map['productionPct']?.toDouble() ?? 0.0,
      eggWeightG: map['eggWeightG']?.toDouble() ?? 0.0,
      chickWeightG: map['chickWeightG']?.toDouble() ?? 0.0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'breed': breed,
      'ageWeek': ageWeek,
      'hatchabilityPct': hatchabilityPct,
      'fertilityPct': fertilityPct,
      'hofPct': hofPct,
      'productionPct': productionPct,
      'eggWeightG': eggWeightG,
      'chickWeightG': chickWeightG,
    };
  }
}
