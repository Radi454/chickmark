// Breed reference benchmarks — dense per age week (25-65; Cobb500 from 24).
//
// The cloud `bmk_breeds` table is the source of truth; sync pulls cloud -> local
// and overwrites these rows. These seeds are the offline-first baseline and are
// kept byte-for-byte identical to cloud so a fresh (un-synced) install already
// shows the correct values.
//
// Encoded as piecewise-constant age segments shared across breeds. Row ids are
// `${breed.toLowerCase()}-$ageWeek`, matching the cloud ids so a pull replaces
// each local row in place (ConflictAlgorithm.replace on the `id` primary key).

class _BreedBmkSegment {
  final int startAge;
  final int endAge;
  final double hatchabilityPct;
  final double fertilityPct;
  final double hofPct;
  final double productionPct;
  final double eggWeightG;
  final double chickWeightG;

  const _BreedBmkSegment(
    this.startAge,
    this.endAge,
    this.hatchabilityPct,
    this.fertilityPct,
    this.hofPct,
    this.productionPct,
    this.eggWeightG,
    this.chickWeightG,
  );
}

// Shared age segments: [start-28], [29-33], [34-38], [39-48], [49-58], [59-65].
// Every breed starts at week 25 except Cobb500, whose first segment starts at 24.
const Map<String, List<_BreedBmkSegment>> _breedBmkSegments = {
  'Ross308': [
    _BreedBmkSegment(25, 28, 89.0, 95.0, 85.0, 82.0, 62.0, 45.0),
    _BreedBmkSegment(29, 33, 91.0, 96.0, 87.0, 84.0, 65.0, 47.0),
    _BreedBmkSegment(34, 38, 90.0, 95.0, 86.0, 83.0, 67.0, 48.0),
    _BreedBmkSegment(39, 48, 88.0, 94.0, 84.0, 81.0, 68.0, 49.0),
    _BreedBmkSegment(49, 58, 85.0, 92.0, 81.0, 78.0, 70.0, 50.0),
    _BreedBmkSegment(59, 65, 82.0, 90.0, 78.0, 75.0, 71.0, 51.0),
  ],
  'Arbo': [
    _BreedBmkSegment(25, 28, 88.0, 94.0, 84.0, 80.0, 60.0, 43.0),
    _BreedBmkSegment(29, 33, 90.0, 95.0, 86.0, 82.0, 63.0, 45.0),
    _BreedBmkSegment(34, 38, 89.0, 94.0, 85.0, 81.0, 65.0, 46.0),
    _BreedBmkSegment(39, 48, 87.0, 93.0, 83.0, 79.0, 66.0, 47.0),
    _BreedBmkSegment(49, 58, 84.0, 91.0, 80.0, 76.0, 68.0, 48.0),
    _BreedBmkSegment(59, 65, 81.0, 89.0, 77.0, 73.0, 69.0, 49.0),
  ],
  'Avian': [
    _BreedBmkSegment(25, 28, 87.0, 93.0, 83.0, 79.0, 58.0, 42.0),
    _BreedBmkSegment(29, 33, 89.0, 94.0, 85.0, 81.0, 61.0, 44.0),
    _BreedBmkSegment(34, 38, 88.0, 93.0, 84.0, 80.0, 63.0, 45.0),
    _BreedBmkSegment(39, 48, 86.0, 92.0, 82.0, 78.0, 64.0, 46.0),
    _BreedBmkSegment(49, 58, 83.0, 90.0, 79.0, 75.0, 66.0, 47.0),
    _BreedBmkSegment(59, 65, 80.0, 88.0, 76.0, 72.0, 67.0, 48.0),
  ],
  'Cobb500': [
    _BreedBmkSegment(24, 28, 90.0, 96.0, 86.0, 83.0, 63.0, 46.0),
    _BreedBmkSegment(29, 33, 92.0, 97.0, 88.0, 85.0, 66.0, 48.0),
    _BreedBmkSegment(34, 38, 91.0, 96.0, 87.0, 84.0, 68.0, 49.0),
    _BreedBmkSegment(39, 48, 89.0, 95.0, 85.0, 82.0, 69.0, 50.0),
    _BreedBmkSegment(49, 58, 86.0, 93.0, 82.0, 79.0, 71.0, 51.0),
    _BreedBmkSegment(59, 65, 83.0, 91.0, 79.0, 76.0, 72.0, 52.0),
  ],
  'Hubbard': [
    _BreedBmkSegment(25, 28, 86.0, 92.0, 82.0, 78.0, 59.0, 42.0),
    _BreedBmkSegment(29, 33, 88.0, 94.0, 84.0, 80.0, 62.0, 44.0),
    _BreedBmkSegment(34, 38, 87.0, 93.0, 83.0, 79.0, 64.0, 45.0),
    _BreedBmkSegment(39, 48, 85.0, 91.0, 81.0, 77.0, 65.0, 46.0),
    _BreedBmkSegment(49, 58, 82.0, 89.0, 78.0, 74.0, 67.0, 47.0),
    _BreedBmkSegment(59, 65, 79.0, 87.0, 75.0, 71.0, 68.0, 48.0),
  ],
  'IR': [
    _BreedBmkSegment(25, 28, 85.0, 91.0, 81.0, 77.0, 57.0, 41.0),
    _BreedBmkSegment(29, 33, 87.0, 93.0, 83.0, 79.0, 60.0, 43.0),
    _BreedBmkSegment(34, 38, 86.0, 92.0, 82.0, 78.0, 62.0, 44.0),
    _BreedBmkSegment(39, 48, 84.0, 90.0, 80.0, 76.0, 63.0, 45.0),
    _BreedBmkSegment(49, 58, 81.0, 88.0, 77.0, 73.0, 65.0, 46.0),
    _BreedBmkSegment(59, 65, 78.0, 86.0, 74.0, 70.0, 66.0, 47.0),
  ],
};

final List<Map<String, dynamic>> kBmkBreedSeeds = [
  for (final entry in _breedBmkSegments.entries)
    for (final segment in entry.value)
      for (var ageWeek = segment.startAge; ageWeek <= segment.endAge; ageWeek++)
        {
          'id': '${entry.key.toLowerCase()}-$ageWeek',
          'breed': entry.key,
          'ageWeek': ageWeek,
          'hatchabilityPct': segment.hatchabilityPct,
          'fertilityPct': segment.fertilityPct,
          'hofPct': segment.hofPct,
          'productionPct': segment.productionPct,
          'eggWeightG': segment.eggWeightG,
          'chickWeightG': segment.chickWeightG,
        },
];

final List<Map<String, dynamic>> kBmkEggBreakoutSeeds = [
  for (final ageWeek in _bmkEggBreakoutAgeWeeks)
    {
      'id': 'eb-$ageWeek',
      'ageWeek': ageWeek,
      ..._freshCandledBreakoutBmkForAge(ageWeek),
      ..._residueBreakoutBmkForAge(ageWeek),
    },
];

const List<int> _bmkEggBreakoutAgeWeeks = [
  25,
  26,
  27,
  28,
  29,
  30,
  31,
  32,
  33,
  34,
  35,
  36,
  37,
  38,
  39,
  40,
  41,
  42,
  43,
  44,
  45,
  46,
  47,
  48,
  49,
  50,
  51,
  52,
  53,
  54,
  55,
  56,
  57,
  58,
  59,
  60,
  61,
  62,
  63,
  64,
  65,
];

Map<String, double> _freshCandledBreakoutBmkForAge(int ageWeek) {
  if (ageWeek <= 30) {
    return const {
      'infertilePct': 6.0,
      'early24hPct': 1.0,
      'early48hPct': 2.0,
      'bloodRingPct': 2.5,
      'blackEyePct': 1.0,
    };
  }
  if (ageWeek <= 45) {
    return const {
      'infertilePct': 2.5,
      'early24hPct': 0.5,
      'early48hPct': 1.0,
      'bloodRingPct': 2.0,
      'blackEyePct': 0.5,
    };
  }
  if (ageWeek <= 50) {
    return const {
      'infertilePct': 5.0,
      'early24hPct': 0.5,
      'early48hPct': 1.0,
      'bloodRingPct': 2.5,
      'blackEyePct': 1.0,
    };
  }
  return const {
    'infertilePct': 8.0,
    'early24hPct': 0.5,
    'early48hPct': 1.0,
    'bloodRingPct': 3.0,
    'blackEyePct': 1.0,
  };
}

Map<String, double> _residueBreakoutBmkForAge(int ageWeek) {
  if (ageWeek <= 30) {
    return const {
      'earlyDeadPct': 5.5,
      'midDeadPct': 1.0,
      'lateDeadPct': 3.5,
      'externalPipPct': 1.0,
      'crackedPct': 0.5,
      'contamPct': 0.5,
    };
  }
  if (ageWeek <= 45) {
    return const {
      'earlyDeadPct': 3.5,
      'midDeadPct': 0.5,
      'lateDeadPct': 2.5,
      'externalPipPct': 0.5,
      'crackedPct': 0.5,
      'contamPct': 0.5,
    };
  }
  if (ageWeek <= 50) {
    return const {
      'earlyDeadPct': 4.0,
      'midDeadPct': 1.0,
      'lateDeadPct': 2.5,
      'externalPipPct': 0.5,
      'crackedPct': 0.5,
      'contamPct': 0.5,
    };
  }
  return const {
    'earlyDeadPct': 4.5,
    'midDeadPct': 1.0,
    'lateDeadPct': 3.0,
    'externalPipPct': 0.5,
    'crackedPct': 1.0,
    'contamPct': 1.0,
  };
}

const List<Map<String, dynamic>> kTroubleshootingSeeds = [];

const List<Map<String, dynamic>> kBmkOperationalStandardSeeds = [
  {
    'id': 'global-egg_storage_est_short',
    'hatcheryId': null,
    'stationKey': 'egg',
    'sectorKey': 'egg_storage',
    'metricKey': 'egg_storage_est_short',
    'metricLabel': 'Egg storage EST short',
    'unit': '°C',
    'minValue': 19.0,
    'maxValue': 21.0,
    'targetValue': null,
    'source': 'Cobb storage guidance; ChickMark current EST band',
    'notes': 'Storage duration 0-4 days.',
    'sortOrder': 10,
  },
  {
    'id': 'global-egg_storage_est_medium',
    'hatcheryId': null,
    'stationKey': 'egg',
    'sectorKey': 'egg_storage',
    'metricKey': 'egg_storage_est_medium',
    'metricLabel': 'Egg storage EST medium',
    'unit': '°C',
    'minValue': 18.0,
    'maxValue': 20.0,
    'targetValue': null,
    'source': 'Cobb storage guidance; ChickMark current EST band',
    'notes': 'Storage duration 5-7 days.',
    'sortOrder': 20,
  },
  {
    'id': 'global-egg_storage_est_long',
    'hatcheryId': null,
    'stationKey': 'egg',
    'sectorKey': 'egg_storage',
    'metricKey': 'egg_storage_est_long',
    'metricLabel': 'Egg storage EST long',
    'unit': '°C',
    'minValue': 16.0,
    'maxValue': 18.0,
    'targetValue': null,
    'source': 'Cobb storage guidance; ChickMark current EST band',
    'notes': 'Storage duration 8+ days.',
    'sortOrder': 30,
  },
  {
    'id': 'global-egg_storage_rh',
    'hatcheryId': null,
    'stationKey': 'egg',
    'sectorKey': 'egg_storage',
    'metricKey': 'egg_storage_rh',
    'metricLabel': 'Egg storage RH',
    'unit': '%',
    'minValue': 50.0,
    'maxValue': 70.0,
    'targetValue': null,
    'source': 'Cobb storage guidance',
    'notes': 'Operational room RH band; tune by storage duration if needed.',
    'sortOrder': 40,
  },
  {
    'id': 'global-cv_alert',
    'hatcheryId': null,
    'stationKey': 'global',
    'sectorKey': 'uniformity',
    'metricKey': 'cv_alert',
    'metricLabel': 'CV alert',
    'unit': '%',
    'minValue': null,
    'maxValue': 8.0,
    'targetValue': null,
    'source': 'ChickMark operational default',
    'notes': 'Used by EST, CVT, egg weights, and chick weights.',
    'sortOrder': 100,
  },
  {
    'id': 'global-uniformity_good',
    'hatcheryId': null,
    'stationKey': 'global',
    'sectorKey': 'uniformity',
    'metricKey': 'uniformity_good',
    'metricLabel': 'Uniformity good',
    'unit': '%',
    'minValue': 85.0,
    'maxValue': null,
    'targetValue': null,
    'source': 'ChickMark operational default',
    'notes': 'Used by egg and chick weight uniformity.',
    'sortOrder': 110,
  },
  {
    'id': 'global-shell_uv_affected',
    'hatcheryId': null,
    'stationKey': 'egg',
    'sectorKey': 'egg_quality',
    'metricKey': 'shell_uv_affected',
    'metricLabel': 'Shell UV affected',
    'unit': '%',
    'minValue': null,
    'maxValue': 5.0,
    'targetValue': null,
    'source': 'ChickMark operational default',
    'notes': 'Cuticle damage, washed, or dirty total affected percentage.',
    'sortOrder': 120,
  },
  {
    'id': 'global-pasgar_score',
    'hatcheryId': null,
    'stationKey': 'chicks',
    'sectorKey': 'pasgar',
    'metricKey': 'pasgar_score',
    'metricLabel': 'Pasgar score',
    'unit': 'score',
    'minValue': 9.0,
    'maxValue': null,
    'targetValue': 9.5,
    'source': 'Pas Reform Pasgar guidance; ChickMark bands',
    'notes': 'Minimum acceptable 9.0; excellent target 9.5+.',
    'sortOrder': 200,
  },
  {
    'id': 'global-pasgar_defect_alert',
    'hatcheryId': null,
    'stationKey': 'chicks',
    'sectorKey': 'pasgar',
    'metricKey': 'pasgar_defect_alert',
    'metricLabel': 'Pasgar defect alert',
    'unit': '%',
    'minValue': null,
    'maxValue': 20.0,
    'targetValue': null,
    'source': 'ChickMark operational default',
    'notes': 'Per defect category alert cap.',
    'sortOrder': 210,
  },
  {
    'id': 'global-chicks_cvt',
    'hatcheryId': null,
    'stationKey': 'chicks',
    'sectorKey': 'cvt',
    'metricKey': 'chicks_cvt',
    'metricLabel': 'Chicks CVT',
    'unit': '°F',
    'minValue': 103.0,
    'maxValue': 105.0,
    'targetValue': null,
    'source': 'Aviagen chick vent temperature guidance',
    'notes': 'Equivalent to about 39.4-40.6°C.',
    'sortOrder': 220,
  },
  {
    'id': 'global-yfbm_residual_yolk',
    'hatcheryId': null,
    'stationKey': 'chicks',
    'sectorKey': 'yfbm',
    'metricKey': 'yfbm_residual_yolk',
    'metricLabel': 'Residual yolk / chick weight',
    'unit': '%',
    'minValue': 8.0,
    'maxValue': 10.0,
    'targetValue': null,
    'source': 'Petersime chick quality guidance; ChickMark current target',
    'notes': 'Current YFBM panel stores yolk weight divided by chick weight.',
    'sortOrder': 230,
  },
  {
    'id': 'global-culled_chicks',
    'hatcheryId': null,
    'stationKey': 'chicks',
    'sectorKey': 'culled_chicks',
    'metricKey': 'culled_chicks',
    'metricLabel': 'Culled chicks',
    'unit': '%',
    'minValue': null,
    'maxValue': 1.0,
    'targetValue': null,
    'source': 'ChickMark operational default',
    'notes': 'Culled chicks as percent of total eggs set.',
    'sortOrder': 240,
  },
  {
    'id': 'global-dead_chicks',
    'hatcheryId': null,
    'stationKey': 'chicks',
    'sectorKey': 'culled_chicks',
    'metricKey': 'dead_chicks',
    'metricLabel': 'Dead chicks',
    'unit': '%',
    'minValue': null,
    'maxValue': 0.2,
    'targetValue': null,
    'source': 'ChickMark operational default',
    'notes': 'Dead chicks as percent of total eggs set.',
    'sortOrder': 250,
  },
  {
    'id': 'global-setter_est_allowed',
    'hatcheryId': null,
    'stationKey': 'setters',
    'sectorKey': 'est',
    'metricKey': 'setter_est_allowed',
    'metricLabel': 'Setter EST allowed',
    'unit': '°F',
    'minValue': 99.5,
    'maxValue': 102.0,
    'targetValue': null,
    'source': 'Petersime/HatchTech EST guidance; ChickMark current band',
    'notes': 'Allowed range around the optimum band.',
    'sortOrder': 300,
  },
  {
    'id': 'global-setter_est_optimal',
    'hatcheryId': null,
    'stationKey': 'setters',
    'sectorKey': 'est',
    'metricKey': 'setter_est_optimal',
    'metricLabel': 'Setter EST optimal',
    'unit': '°F',
    'minValue': 100.0,
    'maxValue': 101.0,
    'targetValue': null,
    'source': 'Petersime/HatchTech EST guidance; ChickMark current band',
    'notes': 'Primary optimum target for setter EST.',
    'sortOrder': 310,
  },
  {
    'id': 'global-setter_turning_angle',
    'hatcheryId': null,
    'stationKey': 'setters',
    'sectorKey': 'turning',
    'metricKey': 'setter_turning_angle',
    'metricLabel': 'Setter turning angle',
    'unit': '°',
    'minValue': 39.0,
    'maxValue': null,
    'targetValue': 45.0,
    'source': 'Cobb turning guidance',
    'notes': 'Minimum 39°, common operating target 45°.',
    'sortOrder': 320,
  },
  {
    'id': 'global-co2_max',
    'hatcheryId': null,
    'stationKey': 'global',
    'sectorKey': 'environment',
    'metricKey': 'co2_max',
    'metricLabel': 'CO₂ max',
    'unit': 'ppm',
    'minValue': null,
    'maxValue': 3000.0,
    'targetValue': null,
    'source': 'ChickMark operational default',
    'notes': 'Shared setter and hatcher alert cap.',
    'sortOrder': 330,
  },
  {
    'id': 'global-hatcher_cvt',
    'hatcheryId': null,
    'stationKey': 'hatchers',
    'sectorKey': 'cvt',
    'metricKey': 'hatcher_cvt',
    'metricLabel': 'Hatcher CVT',
    'unit': '°F',
    'minValue': 103.0,
    'maxValue': 105.0,
    'targetValue': null,
    'source': 'Aviagen chick vent temperature guidance',
    'notes': 'Equivalent to about 39.4-40.6°C.',
    'sortOrder': 400,
  },
  {
    'id': 'global-hatcher_rh',
    'hatcheryId': null,
    'stationKey': 'hatchers',
    'sectorKey': 'environment',
    'metricKey': 'hatcher_rh',
    'metricLabel': 'Hatcher RH',
    'unit': '%',
    'minValue': 52.0,
    'maxValue': 54.0,
    'targetValue': null,
    'source': 'Cobb hatcher guidance',
    'notes': 'First 24 hours after transfer; hatchery override expected.',
    'sortOrder': 410,
  },
];
