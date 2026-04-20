class AuditModel {
  // --- Common ---
  final String id;
  final String auditType;
  final String customerId;
  final String? flockId;
  final String? setterId;
  final String? hatcherId;
  final DateTime date;
  final int hatchNumber;
  final String status;
  final String createdBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final String? notes;

  // --- Chick Quality: CHA Environmental ---
  final bool? chaGoveeConnected;
  final double? chaCo2;
  final String? chaCo2Photo;
  final double? chaPm10;
  final String? chaPm10Photo;
  final double? chaPm25;
  final String? chaPm25Photo;
  final double? chaAirVelocitySpot1;
  final String? chaAirVelocitySpot1Photo;
  final double? chaAirVelocitySpot2;
  final String? chaAirVelocitySpot2Photo;
  final double? chaAirVelocitySpot3;
  final String? chaAirVelocitySpot3Photo;
  final double? chaAirInlet;
  final String? chaAirInletPhoto;
  final double? chaAirOutlet;
  final String? chaAirOutletPhoto;
  final double? chaNoiseLevel;
  final String? chaNoiseLevelPhoto;

  // --- Chick Quality: Pasgar ---
  final int? pasgarSampleSize;
  final int? pasgarReflexes;
  final String? pasgarReflexesPhoto;
  final int? pasgarBeak;
  final String? pasgarBeakPhoto;
  final int? pasgarNavel;
  final String? pasgarNavelPhoto;
  final int? pasgarBelly;
  final String? pasgarBellyPhoto;
  final int? pasgarLeg;
  final String? pasgarLegPhoto;
  final int? pasgarFeatherDev;
  final String? pasgarFeatherDevPhoto;
  final double? pasgarFinalScore;

  // --- Chick Quality: Weights ---
  final int? chickStorageDays;
  final int? chickSampleSize;
  final String? chickWeights;
  final double? chickAvgWeight;
  final double? chickUniformityPct;
  final double? chickCvPct;
  final int? chickBmkAge;
  final double? chickBmkWeight;

  // --- Chick Quality: YFBM ---
  final String? yfbmPhoto;
  final String? yfbmEntries;
  final double? yfbmAvgPct;
  final double? yfbmCvPct;

  // --- Chick Quality: CVT ---
  final int? cvtSampleSize;
  final String? cvtTopBasket;
  final double? cvtTopTemp;
  final String? cvtTopPhoto;
  final String? cvtMiddleBasket;
  final double? cvtMiddleTemp;
  final String? cvtMiddlePhoto;
  final String? cvtBottomBasket;
  final double? cvtBottomTemp;
  final String? cvtBottomPhoto;
  final double? cvtAvg;
  final double? cvtCvPct;

  // --- Hatch Analysis: Hatch Results ---
  final int? haStorageDays;
  final int? haTotalEggsSet;
  final int? haHatched;
  final int? haCulled;
  final int? haDead;
  final double? haHatchability;
  final double? haFertility;
  final double? haHof;
  final String? haTrays;
  final int? haBmkAge;

  // --- Hatch Analysis: Egg Breakout ---
  final int? ebTraySize;
  final String? ebBreakoutType;
  final int? ebBreakoutAgeDays;
  final int? ebStorageDays;
  final String? ebTrays;
  final int? ebBmkAge;
  final int? ebInfertileCount;
  final int? ebEarlyDeadCount;
  final int? ebMidDeadCount;
  final int? ebLateDeadCount;
  final int? ebInternalPipCount;
  final int? ebExternalPipCount;
  final int? ebCrackedCount;
  final int? ebContaminatedCount;
  final int? ebMalpositionCount;
  final int? ebExposedBrainCount;
  final int? ebCrossedBeakCount;
  final int? ebCulledDeadCount;

  // --- Setter Optimizing ---
  final String? soBreed;
  final String? soSetterId;
  final int? soIncubationAge;
  final bool? soGoveeConnected;
  final double? soGoveeTemp;
  final double? soGoveeHumidity;
  final double? soCo2;
  final String? soCo2Photo;
  final String? soEstReadings;
  final String? soEstPhotos;
  final double? soEstAvg;
  final double? soEstCv;

  // --- Hatcher Optimizing ---
  final String? hoBreed;
  final String? hoHatcherId;
  final int? hoIncubationAge;
  final bool? hoGoveeConnected;
  final double? hoGoveeTemp;
  final double? hoGoveeHumidity;
  final double? hoCo2;
  final String? hoCo2Photo;
  final String? hoCvtReadings;
  final String? hoCvtPhotos;
  final double? hoCvtAvg;
  final double? hoCvtCv;
  final bool? hoChickPanting;
  final String? hoChickPantingPhoto;

  // --- Egg Storage ---
  final bool? esGoveeConnected;
  final double? esGoveeTemp;
  final double? esGoveeHumidity;
  final double? esCo2;
  final String? esCo2Photo;
  final double? esShellTemp;
  final String? esShellTempPhoto;
  final int? esTurningTimes;
  final String? esUvTrays;
  final int? esEggStorageDays;
  final int? esEggSampleSize;
  final String? esEggWeights;
  final double? esEggAvgWeight;
  final double? esEggUniformityPct;
  final double? esEggCvPct;
  final int? esEggBmkAge;
  final double? esEggBmkWeight;

  AuditModel({
    required this.id,
    required this.auditType,
    required this.customerId,
    required this.flockId,
    required this.date,
    required this.status,
    required this.createdBy,
    required this.createdAt,
    required this.updatedAt,
    this.setterId,
    this.hatcherId,
    this.hatchNumber = 1,
    this.notes,
    // --- Chick Quality: CHA Environmental ---
    this.chaGoveeConnected,
    this.chaCo2,
    this.chaCo2Photo,
    this.chaPm10,
    this.chaPm10Photo,
    this.chaPm25,
    this.chaPm25Photo,
    this.chaAirVelocitySpot1,
    this.chaAirVelocitySpot1Photo,
    this.chaAirVelocitySpot2,
    this.chaAirVelocitySpot2Photo,
    this.chaAirVelocitySpot3,
    this.chaAirVelocitySpot3Photo,
    this.chaAirInlet,
    this.chaAirInletPhoto,
    this.chaAirOutlet,
    this.chaAirOutletPhoto,
    this.chaNoiseLevel,
    this.chaNoiseLevelPhoto,
    // --- Chick Quality: Pasgar ---
    this.pasgarSampleSize,
    this.pasgarReflexes,
    this.pasgarReflexesPhoto,
    this.pasgarBeak,
    this.pasgarBeakPhoto,
    this.pasgarNavel,
    this.pasgarNavelPhoto,
    this.pasgarBelly,
    this.pasgarBellyPhoto,
    this.pasgarLeg,
    this.pasgarLegPhoto,
    this.pasgarFeatherDev,
    this.pasgarFeatherDevPhoto,
    this.pasgarFinalScore,
    // --- Chick Quality: Weights ---
    this.chickStorageDays,
    this.chickSampleSize,
    this.chickWeights,
    this.chickAvgWeight,
    this.chickUniformityPct,
    this.chickCvPct,
    this.chickBmkAge,
    this.chickBmkWeight,
    // --- Chick Quality: YFBM ---
    this.yfbmPhoto,
    this.yfbmEntries,
    this.yfbmAvgPct,
    this.yfbmCvPct,
    // --- Chick Quality: CVT ---
    this.cvtSampleSize,
    this.cvtTopBasket,
    this.cvtTopTemp,
    this.cvtTopPhoto,
    this.cvtMiddleBasket,
    this.cvtMiddleTemp,
    this.cvtMiddlePhoto,
    this.cvtBottomBasket,
    this.cvtBottomTemp,
    this.cvtBottomPhoto,
    this.cvtAvg,
    this.cvtCvPct,
    // --- Hatch Analysis: Hatch Results ---
    this.haStorageDays,
    this.haTotalEggsSet,
    this.haHatched,
    this.haCulled,
    this.haDead,
    this.haHatchability,
    this.haFertility,
    this.haHof,
    this.haTrays,
    this.haBmkAge,
    // --- Hatch Analysis: Egg Breakout ---
    this.ebTraySize,
    this.ebBreakoutType,
    this.ebBreakoutAgeDays,
    this.ebStorageDays,
    this.ebTrays,
    this.ebBmkAge,
    this.ebInfertileCount,
    this.ebEarlyDeadCount,
    this.ebMidDeadCount,
    this.ebLateDeadCount,
    this.ebInternalPipCount,
    this.ebExternalPipCount,
    this.ebCrackedCount,
    this.ebContaminatedCount,
    this.ebMalpositionCount,
    this.ebExposedBrainCount,
    this.ebCrossedBeakCount,
    this.ebCulledDeadCount,
    // --- Setter Optimizing ---
    this.soBreed,
    this.soSetterId,
    this.soIncubationAge,
    this.soGoveeConnected,
    this.soGoveeTemp,
    this.soGoveeHumidity,
    this.soCo2,
    this.soCo2Photo,
    this.soEstReadings,
    this.soEstPhotos,
    this.soEstAvg,
    this.soEstCv,
    // --- Hatcher Optimizing ---
    this.hoBreed,
    this.hoHatcherId,
    this.hoIncubationAge,
    this.hoGoveeConnected,
    this.hoGoveeTemp,
    this.hoGoveeHumidity,
    this.hoCo2,
    this.hoCo2Photo,
    this.hoCvtReadings,
    this.hoCvtPhotos,
    this.hoCvtAvg,
    this.hoCvtCv,
    this.hoChickPanting,
    this.hoChickPantingPhoto,
    // --- Egg Storage ---
    this.esGoveeConnected,
    this.esGoveeTemp,
    this.esGoveeHumidity,
    this.esCo2,
    this.esCo2Photo,
    this.esShellTemp,
    this.esShellTempPhoto,
    this.esTurningTimes,
    this.esUvTrays,
    this.esEggStorageDays,
    this.esEggSampleSize,
    this.esEggWeights,
    this.esEggAvgWeight,
    this.esEggUniformityPct,
    this.esEggCvPct,
    this.esEggBmkAge,
    this.esEggBmkWeight,
  });

  factory AuditModel.fromMap(Map<String, dynamic> map) {
    return AuditModel(
      id: map['id'],
      auditType: map['auditType'],
      customerId: map['customerId'],
      flockId: map['flockId'],
      date: DateTime.tryParse(map['date'] ?? '') ?? DateTime.now(),
      hatchNumber: map['hatchNumber'] as int? ?? 1,
      status: map['status'] ?? 'active',
      createdBy: map['createdBy'] ?? 'unknown',
      createdAt: DateTime.tryParse(map['createdAt'] ?? '') ?? DateTime.now(),
      updatedAt: DateTime.tryParse(map['updatedAt'] ?? '') ?? DateTime.now(),
      setterId: map['setterId'],
      hatcherId: map['hatcherId'],
      notes: map['notes'],
      // --- Chick Quality: CHA Environmental ---
      chaGoveeConnected: map['chaGoveeConnected'] == 1,
      chaCo2: map['chaCo2']?.toDouble(),
      chaCo2Photo: map['chaCo2Photo'],
      chaPm10: map['chaPm10']?.toDouble(),
      chaPm10Photo: map['chaPm10Photo'],
      chaPm25: map['chaPm25']?.toDouble(),
      chaPm25Photo: map['chaPm25Photo'],
      chaAirVelocitySpot1: map['chaAirVelocitySpot1']?.toDouble(),
      chaAirVelocitySpot1Photo: map['chaAirVelocitySpot1Photo'],
      chaAirVelocitySpot2: map['chaAirVelocitySpot2']?.toDouble(),
      chaAirVelocitySpot2Photo: map['chaAirVelocitySpot2Photo'],
      chaAirVelocitySpot3: map['chaAirVelocitySpot3']?.toDouble(),
      chaAirVelocitySpot3Photo: map['chaAirVelocitySpot3Photo'],
      chaAirInlet: map['chaAirInlet']?.toDouble(),
      chaAirInletPhoto: map['chaAirInletPhoto'],
      chaAirOutlet: map['chaAirOutlet']?.toDouble(),
      chaAirOutletPhoto: map['chaAirOutletPhoto'],
      chaNoiseLevel: map['chaNoiseLevel']?.toDouble(),
      chaNoiseLevelPhoto: map['chaNoiseLevelPhoto'],
      // --- Chick Quality: Pasgar ---
      pasgarSampleSize: map['pasgarSampleSize'],
      pasgarReflexes: map['pasgarReflexes'],
      pasgarReflexesPhoto: map['pasgarReflexesPhoto'],
      pasgarBeak: map['pasgarBeak'],
      pasgarBeakPhoto: map['pasgarBeakPhoto'],
      pasgarNavel: map['pasgarNavel'],
      pasgarNavelPhoto: map['pasgarNavelPhoto'],
      pasgarBelly: map['pasgarBelly'],
      pasgarBellyPhoto: map['pasgarBellyPhoto'],
      pasgarLeg: map['pasgarLeg'],
      pasgarLegPhoto: map['pasgarLegPhoto'],
      pasgarFeatherDev: map['pasgarFeatherDev'],
      pasgarFeatherDevPhoto: map['pasgarFeatherDevPhoto'],
      pasgarFinalScore: map['pasgarFinalScore']?.toDouble(),
      // --- Chick Quality: Weights ---
      chickStorageDays: map['chickStorageDays'],
      chickSampleSize: map['chickSampleSize'],
      chickWeights: map['chickWeights'],
      chickAvgWeight: map['chickAvgWeight']?.toDouble(),
      chickUniformityPct: map['chickUniformityPct']?.toDouble(),
      chickCvPct: map['chickCvPct']?.toDouble(),
      chickBmkAge: map['chickBmkAge'],
      chickBmkWeight: map['chickBmkWeight']?.toDouble(),
      // --- Chick Quality: YFBM ---
      yfbmPhoto: map['yfbmPhoto'],
      yfbmEntries: map['yfbmEntries'],
      yfbmAvgPct: map['yfbmAvgPct']?.toDouble(),
      yfbmCvPct: map['yfbmCvPct']?.toDouble(),
      // --- Chick Quality: CVT ---
      cvtSampleSize: map['cvtSampleSize'],
      cvtTopBasket: map['cvtTopBasket'],
      cvtTopTemp: map['cvtTopTemp']?.toDouble(),
      cvtTopPhoto: map['cvtTopPhoto'],
      cvtMiddleBasket: map['cvtMiddleBasket'],
      cvtMiddleTemp: map['cvtMiddleTemp']?.toDouble(),
      cvtMiddlePhoto: map['cvtMiddlePhoto'],
      cvtBottomBasket: map['cvtBottomBasket'],
      cvtBottomTemp: map['cvtBottomTemp']?.toDouble(),
      cvtBottomPhoto: map['cvtBottomPhoto'],
      cvtAvg: map['cvtAvg']?.toDouble(),
      cvtCvPct: map['cvtCvPct']?.toDouble(),
      // --- Hatch Analysis: Hatch Results ---
      haStorageDays: map['haStorageDays'],
      haTotalEggsSet: map['haTotalEggsSet'],
      haHatched: map['haHatched'],
      haCulled: map['haCulled'],
      haDead: map['haDead'],
      haHatchability: map['haHatchability']?.toDouble(),
      haFertility: map['haFertility']?.toDouble(),
      haHof: map['haHof']?.toDouble(),
      haTrays: map['haTrays'],
      haBmkAge: map['haBmkAge'],
      // --- Hatch Analysis: Egg Breakout ---
      ebTraySize: map['ebTraySize'],
      ebBreakoutType: map['ebBreakoutType'],
      ebBreakoutAgeDays: map['ebBreakoutAgeDays'],
      ebStorageDays: map['ebStorageDays'],
      ebTrays: map['ebTrays'],
      ebBmkAge: map['ebBmkAge'],
      ebInfertileCount: map['ebInfertileCount'],
      ebEarlyDeadCount: map['ebEarlyDeadCount'],
      ebMidDeadCount: map['ebMidDeadCount'],
      ebLateDeadCount: map['ebLateDeadCount'],
      ebInternalPipCount: map['ebInternalPipCount'],
      ebExternalPipCount: map['ebExternalPipCount'],
      ebCrackedCount: map['ebCrackedCount'],
      ebContaminatedCount: map['ebContaminatedCount'],
      ebMalpositionCount: map['ebMalpositionCount'],
      ebExposedBrainCount: map['ebExposedBrainCount'],
      ebCrossedBeakCount: map['ebCrossedBeakCount'],
      ebCulledDeadCount: map['ebCulledDeadCount'],
      // --- Setter Optimizing ---
      soBreed: map['soBreed'],
      soSetterId: map['soSetterId'],
      soIncubationAge: map['soIncubationAge'],
      soGoveeConnected: map['soGoveeConnected'] == 1,
      soGoveeTemp: map['soGoveeTemp']?.toDouble(),
      soGoveeHumidity: map['soGoveeHumidity']?.toDouble(),
      soCo2: map['soCo2']?.toDouble(),
      soCo2Photo: map['soCo2Photo'],
      soEstReadings: map['soEstReadings'],
      soEstPhotos: map['soEstPhotos'],
      soEstAvg: map['soEstAvg']?.toDouble(),
      soEstCv: map['soEstCv']?.toDouble(),
      // --- Hatcher Optimizing ---
      hoBreed: map['hoBreed'],
      hoHatcherId: map['hoHatcherId'],
      hoIncubationAge: map['hoIncubationAge'],
      hoGoveeConnected: map['hoGoveeConnected'] == 1,
      hoGoveeTemp: map['hoGoveeTemp']?.toDouble(),
      hoGoveeHumidity: map['hoGoveeHumidity']?.toDouble(),
      hoCo2: map['hoCo2']?.toDouble(),
      hoCo2Photo: map['hoCo2Photo'],
      hoCvtReadings: map['hoCvtReadings'],
      hoCvtPhotos: map['hoCvtPhotos'],
      hoCvtAvg: map['hoCvtAvg']?.toDouble(),
      hoCvtCv: map['hoCvtCv']?.toDouble(),
      hoChickPanting: map['hoChickPanting'] == 1,
      hoChickPantingPhoto: map['hoChickPantingPhoto'],
      // --- Egg Storage ---
      esGoveeConnected: map['esGoveeConnected'] == 1,
      esGoveeTemp: map['esGoveeTemp']?.toDouble(),
      esGoveeHumidity: map['esGoveeHumidity']?.toDouble(),
      esCo2: map['esCo2']?.toDouble(),
      esCo2Photo: map['esCo2Photo'],
      esShellTemp: map['esShellTemp']?.toDouble(),
      esShellTempPhoto: map['esShellTempPhoto'],
      esTurningTimes: map['esTurningTimes'],
      esUvTrays: map['esUvTrays'],
      esEggStorageDays: map['esEggStorageDays'],
      esEggSampleSize: map['esEggSampleSize'],
      esEggWeights: map['esEggWeights'],
      esEggAvgWeight: map['esEggAvgWeight']?.toDouble(),
      esEggUniformityPct: map['esEggUniformityPct']?.toDouble(),
      esEggCvPct: map['esEggCvPct']?.toDouble(),
      esEggBmkAge: map['esEggBmkAge'],
      esEggBmkWeight: map['esEggBmkWeight']?.toDouble(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'id': id,
      'auditType': auditType,
      'customerId': customerId,
      'flockId': flockId,
      'date': date.toIso8601String(),
      'hatchNumber': hatchNumber,
      'status': status,
      'createdBy': createdBy,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
      'setterId': setterId,
      'hatcherId': hatcherId,
      'notes': notes,
      // --- Chick Quality: CHA Environmental ---
      'chaGoveeConnected': chaGoveeConnected == null
          ? null
          : (chaGoveeConnected! ? 1 : 0),
      'chaCo2': chaCo2,
      'chaCo2Photo': chaCo2Photo,
      'chaPm10': chaPm10,
      'chaPm10Photo': chaPm10Photo,
      'chaPm25': chaPm25,
      'chaPm25Photo': chaPm25Photo,
      'chaAirVelocitySpot1': chaAirVelocitySpot1,
      'chaAirVelocitySpot1Photo': chaAirVelocitySpot1Photo,
      'chaAirVelocitySpot2': chaAirVelocitySpot2,
      'chaAirVelocitySpot2Photo': chaAirVelocitySpot2Photo,
      'chaAirVelocitySpot3': chaAirVelocitySpot3,
      'chaAirVelocitySpot3Photo': chaAirVelocitySpot3Photo,
      'chaAirInlet': chaAirInlet,
      'chaAirInletPhoto': chaAirInletPhoto,
      'chaAirOutlet': chaAirOutlet,
      'chaAirOutletPhoto': chaAirOutletPhoto,
      'chaNoiseLevel': chaNoiseLevel,
      'chaNoiseLevelPhoto': chaNoiseLevelPhoto,
      // --- Chick Quality: Pasgar ---
      'pasgarSampleSize': pasgarSampleSize,
      'pasgarReflexes': pasgarReflexes,
      'pasgarReflexesPhoto': pasgarReflexesPhoto,
      'pasgarBeak': pasgarBeak,
      'pasgarBeakPhoto': pasgarBeakPhoto,
      'pasgarNavel': pasgarNavel,
      'pasgarNavelPhoto': pasgarNavelPhoto,
      'pasgarBelly': pasgarBelly,
      'pasgarBellyPhoto': pasgarBellyPhoto,
      'pasgarLeg': pasgarLeg,
      'pasgarLegPhoto': pasgarLegPhoto,
      'pasgarFeatherDev': pasgarFeatherDev,
      'pasgarFeatherDevPhoto': pasgarFeatherDevPhoto,
      'pasgarFinalScore': pasgarFinalScore,
      // --- Chick Quality: Weights ---
      'chickStorageDays': chickStorageDays,
      'chickSampleSize': chickSampleSize,
      'chickWeights': chickWeights,
      'chickAvgWeight': chickAvgWeight,
      'chickUniformityPct': chickUniformityPct,
      'chickCvPct': chickCvPct,
      'chickBmkAge': chickBmkAge,
      'chickBmkWeight': chickBmkWeight,
      // --- Chick Quality: YFBM ---
      'yfbmPhoto': yfbmPhoto,
      'yfbmEntries': yfbmEntries,
      'yfbmAvgPct': yfbmAvgPct,
      'yfbmCvPct': yfbmCvPct,
      // --- Chick Quality: CVT ---
      'cvtSampleSize': cvtSampleSize,
      'cvtTopBasket': cvtTopBasket,
      'cvtTopTemp': cvtTopTemp,
      'cvtTopPhoto': cvtTopPhoto,
      'cvtMiddleBasket': cvtMiddleBasket,
      'cvtMiddleTemp': cvtMiddleTemp,
      'cvtMiddlePhoto': cvtMiddlePhoto,
      'cvtBottomBasket': cvtBottomBasket,
      'cvtBottomTemp': cvtBottomTemp,
      'cvtBottomPhoto': cvtBottomPhoto,
      'cvtAvg': cvtAvg,
      'cvtCvPct': cvtCvPct,
      // --- Hatch Analysis: Hatch Results ---
      'haStorageDays': haStorageDays,
      'haTotalEggsSet': haTotalEggsSet,
      'haHatched': haHatched,
      'haCulled': haCulled,
      'haDead': haDead,
      'haHatchability': haHatchability,
      'haFertility': haFertility,
      'haHof': haHof,
      'haTrays': haTrays,
      'haBmkAge': haBmkAge,
      // --- Hatch Analysis: Egg Breakout ---
      'ebTraySize': ebTraySize,
      'ebBreakoutType': ebBreakoutType,
      'ebBreakoutAgeDays': ebBreakoutAgeDays,
      'ebStorageDays': ebStorageDays,
      'ebTrays': ebTrays,
      'ebBmkAge': ebBmkAge,
      'ebInfertileCount': ebInfertileCount,
      'ebEarlyDeadCount': ebEarlyDeadCount,
      'ebMidDeadCount': ebMidDeadCount,
      'ebLateDeadCount': ebLateDeadCount,
      'ebInternalPipCount': ebInternalPipCount,
      'ebExternalPipCount': ebExternalPipCount,
      'ebCrackedCount': ebCrackedCount,
      'ebContaminatedCount': ebContaminatedCount,
      'ebMalpositionCount': ebMalpositionCount,
      'ebExposedBrainCount': ebExposedBrainCount,
      'ebCrossedBeakCount': ebCrossedBeakCount,
      'ebCulledDeadCount': ebCulledDeadCount,
      // --- Setter Optimizing ---
      'soBreed': soBreed,
      'soSetterId': soSetterId,
      'soIncubationAge': soIncubationAge,
      'soGoveeConnected': soGoveeConnected == null
          ? null
          : (soGoveeConnected! ? 1 : 0),
      'soGoveeTemp': soGoveeTemp,
      'soGoveeHumidity': soGoveeHumidity,
      'soCo2': soCo2,
      'soCo2Photo': soCo2Photo,
      'soEstReadings': soEstReadings,
      'soEstPhotos': soEstPhotos,
      'soEstAvg': soEstAvg,
      'soEstCv': soEstCv,
      // --- Hatcher Optimizing ---
      'hoBreed': hoBreed,
      'hoHatcherId': hoHatcherId,
      'hoIncubationAge': hoIncubationAge,
      'hoGoveeConnected': hoGoveeConnected == null
          ? null
          : (hoGoveeConnected! ? 1 : 0),
      'hoGoveeTemp': hoGoveeTemp,
      'hoGoveeHumidity': hoGoveeHumidity,
      'hoCo2': hoCo2,
      'hoCo2Photo': hoCo2Photo,
      'hoCvtReadings': hoCvtReadings,
      'hoCvtPhotos': hoCvtPhotos,
      'hoCvtAvg': hoCvtAvg,
      'hoCvtCv': hoCvtCv,
      'hoChickPanting': hoChickPanting == null
          ? null
          : (hoChickPanting! ? 1 : 0),
      'hoChickPantingPhoto': hoChickPantingPhoto,
      // --- Egg Storage ---
      'esGoveeConnected': esGoveeConnected == null
          ? null
          : (esGoveeConnected! ? 1 : 0),
      'esGoveeTemp': esGoveeTemp,
      'esGoveeHumidity': esGoveeHumidity,
      'esCo2': esCo2,
      'esCo2Photo': esCo2Photo,
      'esShellTemp': esShellTemp,
      'esShellTempPhoto': esShellTempPhoto,
      'esTurningTimes': esTurningTimes,
      'esUvTrays': esUvTrays,
      'esEggStorageDays': esEggStorageDays,
      'esEggSampleSize': esEggSampleSize,
      'esEggWeights': esEggWeights,
      'esEggAvgWeight': esEggAvgWeight,
      'esEggUniformityPct': esEggUniformityPct,
      'esEggCvPct': esEggCvPct,
      'esEggBmkAge': esEggBmkAge,
      'esEggBmkWeight': esEggBmkWeight,
    };
  }
}
