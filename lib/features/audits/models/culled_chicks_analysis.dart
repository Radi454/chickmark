import 'dart:convert';

const int kDefaultCulledChicksTotalEggSet = 19200;

class CulledChickSource {
  final String label;
  final String url;

  const CulledChickSource({required this.label, required this.url});

  Map<String, Object?> toJson() => {'label': label, 'url': url};
}

class CulledChickDefect {
  final String id;
  final String category;
  final String subtype;
  final String description;
  final List<String> commonCauses;
  final List<CulledChickSource> sources;

  const CulledChickDefect({
    required this.id,
    required this.category,
    required this.subtype,
    required this.description,
    required this.commonCauses,
    required this.sources,
  });

  Map<String, Object?> toJson({required double pct}) {
    return {
      'id': id,
      'category': category,
      'subtype': subtype,
      'description': description,
      'commonCauses': commonCauses,
      'sourceRefs': sources.map((source) => source.toJson()).toList(),
      'pct': pct,
    };
  }
}

class CulledChicksAnalysisEntry {
  final CulledChickDefect defect;
  final double pct;

  const CulledChicksAnalysisEntry({required this.defect, required this.pct});
}

class CulledChicksAnalysisSummary {
  final int totalEggSet;
  final List<CulledChicksAnalysisEntry> entries;
  final Map<String, double> categoryPcts;
  final double affectedPct;
  final CulledChickDefect? topDefect;
  final String? topCategory;

  const CulledChicksAnalysisSummary({
    required this.totalEggSet,
    required this.entries,
    required this.categoryPcts,
    required this.affectedPct,
    required this.topDefect,
    required this.topCategory,
  });

  bool get hasData => affectedPct > 0 || entries.isNotEmpty;

  String? get topSubtype => topDefect?.subtype;

  String? get encodedJson {
    if (entries.isEmpty) return null;
    return jsonEncode([
      for (final entry in entries) entry.defect.toJson(pct: entry.pct),
    ]);
  }

  double categoryPct(String category) => categoryPcts[category] ?? 0.0;

  double defectPct(String defectId) {
    for (final entry in entries) {
      if (entry.defect.id == defectId) return entry.pct;
    }
    return 0.0;
  }

  factory CulledChicksAnalysisSummary.fromJson(
    String? source, {
    int? totalEggSet,
  }) {
    final entries = CulledChicksAnalysisCodec.decode(
      source,
      totalEggSet: totalEggSet,
    );
    return CulledChicksAnalysisSummary.fromEntries(
      entries,
      totalEggSet: totalEggSet,
    );
  }

  factory CulledChicksAnalysisSummary.fromCounts(
    Map<String, int> countsById, {
    required int totalEggSet,
  }) {
    final entries = <CulledChicksAnalysisEntry>[];
    if (totalEggSet <= 0) {
      return CulledChicksAnalysisSummary.fromEntries(
        entries,
        totalEggSet: totalEggSet,
      );
    }
    for (final defect in kCulledChickDefects) {
      final count = countsById[defect.id] ?? 0;
      if (count <= 0) continue;
      entries.add(
        CulledChicksAnalysisEntry(
          defect: defect,
          pct: (count / totalEggSet) * 100,
        ),
      );
    }
    return CulledChicksAnalysisSummary.fromEntries(
      entries,
      totalEggSet: totalEggSet,
    );
  }

  factory CulledChicksAnalysisSummary.fromEntries(
    List<CulledChicksAnalysisEntry> entries, {
    int? totalEggSet,
  }) {
    final orderedEntries = [...entries]
      ..sort(
        (a, b) => culledChickDefectIndex(
          a.defect.id,
        ).compareTo(culledChickDefectIndex(b.defect.id)),
      );
    final categoryPcts = <String, double>{};
    var affectedPct = 0.0;
    CulledChickDefect? topDefect;
    var topPct = 0.0;

    for (final entry in orderedEntries) {
      if (entry.pct <= 0) continue;
      affectedPct += entry.pct;
      categoryPcts.update(
        entry.defect.category,
        (value) => value + entry.pct,
        ifAbsent: () => entry.pct,
      );
      if (entry.pct > topPct) {
        topPct = entry.pct;
        topDefect = entry.defect;
      }
    }

    String? topCategory;
    var topCategoryPct = 0.0;
    for (final defect in kCulledChickDefects) {
      final pct = categoryPcts[defect.category] ?? 0.0;
      if (pct > topCategoryPct) {
        topCategoryPct = pct;
        topCategory = defect.category;
      }
    }

    return CulledChicksAnalysisSummary(
      totalEggSet: totalEggSet ?? 0,
      entries: [
        for (final entry in orderedEntries)
          if (entry.pct > 0) entry,
      ],
      categoryPcts: categoryPcts,
      affectedPct: affectedPct,
      topDefect: topDefect,
      topCategory: topCategory,
    );
  }
}

class CulledChicksAnalysisCodec {
  const CulledChicksAnalysisCodec._();

  static List<CulledChicksAnalysisEntry> decode(
    String? source, {
    int? totalEggSet,
  }) {
    if (source == null || source.trim().isEmpty) return const [];
    try {
      final decoded = jsonDecode(source);
      if (decoded is! List) return const [];
      final entries = <CulledChicksAnalysisEntry>[];
      final denominator = totalEggSet ?? kDefaultCulledChicksTotalEggSet;
      for (final item in decoded.whereType<Map>()) {
        final map = Map<String, Object?>.from(item);
        final id = map['id']?.toString();
        final defect = id == null ? null : culledChickDefectById(id);
        if (defect == null) continue;
        final pct = map.containsKey('pct')
            ? _asDouble(map['pct'])
            : _pctFromLegacyCount(map['count'], denominator);
        if (pct <= 0) continue;
        entries.add(CulledChicksAnalysisEntry(defect: defect, pct: pct));
      }
      return entries;
    } catch (_) {
      return const [];
    }
  }

  static String? encodeCounts(
    Map<String, int> countsById, {
    int totalEggSet = kDefaultCulledChicksTotalEggSet,
  }) {
    if (totalEggSet <= 0) return null;
    final entries = <Map<String, Object?>>[];
    for (final defect in kCulledChickDefects) {
      final count = countsById[defect.id] ?? 0;
      if (count <= 0) continue;
      entries.add(defect.toJson(pct: (count / totalEggSet) * 100));
    }
    if (entries.isEmpty) return null;
    return jsonEncode(entries);
  }

  static Map<String, int> countsFromPercentages(
    String? source, {
    required int totalEggSet,
  }) {
    if (totalEggSet <= 0) return const {};
    final countsById = <String, int>{};
    for (final entry in decode(source, totalEggSet: totalEggSet)) {
      final count = (entry.pct / 100 * totalEggSet).round();
      if (count <= 0) continue;
      countsById[entry.defect.id] = count;
    }
    return countsById;
  }

  static double _asDouble(Object? value) {
    if (value == null) return 0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString()) ?? 0;
  }

  static double _pctFromLegacyCount(Object? value, int totalEggSet) {
    if (totalEggSet <= 0) return 0;
    final count = _asDouble(value);
    if (count <= 0) return 0;
    return (count / totalEggSet) * 100;
  }
}

CulledChickDefect? culledChickDefectById(String id) {
  for (final defect in kCulledChickDefects) {
    if (defect.id == id) return defect;
  }
  return null;
}

int culledChickDefectIndex(String id) {
  for (var i = 0; i < kCulledChickDefects.length; i++) {
    if (kCulledChickDefects[i].id == id) return i;
  }
  return kCulledChickDefects.length;
}

const _aviagenTips = CulledChickSource(
  label: 'Aviagen Hatchery Tips',
  url:
      'https://aviagen.com/assets/Tech_Center/BB_Resources_Tools/Hatchery_Tips/HatcheryTips-EN.pdf',
);
const _hnGuide = CulledChickSource(
  label: 'H&N International Chick Quality Guide',
  url:
      'https://hn-int.com/wp-content/uploads/2024/02/1223-Chick-quality-ENG-1-1.pdf',
);
const _cobbGuide = CulledChickSource(
  label: 'Cobb Hatchery Guide',
  url: 'https://www.cobbgenetics.com/assets/Cobb-Files/Hatchery-Guide.pdf',
);
const _petersimeQuality = CulledChickSource(
  label: 'Petersime Chick Quality Control',
  url:
      'https://www.petersime.com/expertise/chick-quality-control-assessing-the-quality-of-day-old-chicks-at-the-hatchery/',
);
const _cabiDefects = CulledChickSource(
  label: 'CABI chick defects research',
  url: 'https://www.cabidigitallibrary.org/doi/pdf/10.5555/20193409511',
);
const _researchGateDefects = CulledChickSource(
  label: 'ResearchGate chick defects research',
  url:
      'https://www.researchgate.net/publication/334672313_Breeder_line_and_age_affects_the_occurrence_of_developmental_defects_the_number_of_culled_one-day_old_broiler_chicks_and_their_body_mass',
);
const _aviagenPocketGuide = CulledChickSource(
  label: 'Aviagen Ross Pocket Guide',
  url:
      'https://aviagen.com/assets/Tech_Center/Ross_Broiler/Aviagen-ROSS-Broiler-PocketGuide-EN.pdf',
);
const _lohmannQuality = CulledChickSource(
  label: 'Lohmann Chick Quality',
  url: 'https://lohmann-breeders.com/chick-quality/',
);
const _aviagenPractice = CulledChickSource(
  label: 'Aviagen Investigating Hatchery Practice',
  url:
      'https://en.aviagen.com/assets/Tech_Center/Ross_Tech_Articles/RossTechInvestigatingHatcheryPractice.pdf',
);
const _pasReformRedHocks = CulledChickSource(
  label: 'Pas Reform red hocks',
  url:
      'https://www.thepoultrysite.com/articles/red-hocks-in-dayold-chicks-or-poults',
);
const _abnormalitiesSlides = CulledChickSource(
  label: 'Abnormalities in hatching chicks',
  url:
      'https://www.slideshare.net/slideshow/abnormalities-in-hatching-chicks-73286545/73286545',
);

const List<CulledChickDefect> kCulledChickDefects = [
  CulledChickDefect(
    id: 'navel_open_unhealed',
    category: 'Navel',
    subtype: 'Open / unhealed navel',
    description: 'Belly not fully closed, wet or inflamed navel',
    commonCauses: [
      'High eggshell temperature',
      'Poor ventilation',
      'Early pull',
      'Poor humidity',
    ],
    sources: [_aviagenTips],
  ),
  CulledChickDefect(
    id: 'navel_string',
    category: 'Navel',
    subtype: 'String navel',
    description: 'Dry yolk/string attached to navel',
    commonCauses: ['Poor yolk utilization', 'Incubation stress'],
    sources: [_hnGuide],
  ),
  CulledChickDefect(
    id: 'navel_black_button',
    category: 'Navel',
    subtype: 'Black button',
    description: 'Dark dry scab on navel',
    commonCauses: ['Poor healing', 'Contamination'],
    sources: [_hnGuide],
  ),
  CulledChickDefect(
    id: 'navel_residual_yolk_large_abdomen',
    category: 'Belly',
    subtype: 'Residual yolk / large abdomen',
    description: 'Enlarged abdomen with excess yolk',
    commonCauses: ['Low EST', 'Poor yolk absorption', 'Excessive humidity'],
    sources: [_cobbGuide, _petersimeQuality],
  ),
  CulledChickDefect(
    id: 'sticky_sticky_chick',
    category: 'Sticky',
    subtype: 'Sticky chick',
    description: 'Sticky glued down feathers',
    commonCauses: [
      'High humidity',
      'Low temperature',
      'Poor drying',
      'Improper turning',
    ],
    sources: [_cabiDefects],
  ),
  CulledChickDefect(
    id: 'sticky_dehydrated_burned_chick',
    category: 'Dehydrated',
    subtype: 'Dehydrated / burned chick',
    description: 'Dry dark chick with rough legs/hocks',
    commonCauses: ['Overheating', 'Wide hatch window', 'Long holding'],
    sources: [_aviagenPocketGuide, _aviagenTips],
  ),
  CulledChickDefect(
    id: 'legs_spraddle_leg',
    category: 'Legs',
    subtype: 'Spraddle leg',
    description: 'Legs spread sideways, unable to stand properly',
    commonCauses: ['Weak legs', 'Poor muscle strength', 'Incubation issues'],
    sources: [_petersimeQuality, _lohmannQuality],
  ),
  CulledChickDefect(
    id: 'legs_curled_toes',
    category: 'Legs',
    subtype: 'Curled toes',
    description: 'Toes curled inward',
    commonCauses: ['Nutritional deficiencies', 'Overheating'],
    sources: [_lohmannQuality],
  ),
  CulledChickDefect(
    id: 'legs_twisted_legs_feet',
    category: 'Legs',
    subtype: 'Twisted legs / feet',
    description: 'Bent or twisted legs/feet',
    commonCauses: ['Biotin deficiency', 'Incubation stress'],
    sources: [_aviagenPractice],
  ),
  CulledChickDefect(
    id: 'legs_red_hocks',
    category: 'Legs',
    subtype: 'Red hocks',
    description: 'Red swollen hock joints',
    commonCauses: ['High temperature', 'Poor weight loss', 'Excess humidity'],
    sources: [_petersimeQuality, _pasReformRedHocks],
  ),
  CulledChickDefect(
    id: 'head_crossed_crooked_beak',
    category: 'Head',
    subtype: 'Crossed beak / crooked beak',
    description: 'Upper and lower beak misaligned',
    commonCauses: ['Biotin deficiency', 'Overheating', 'Developmental defects'],
    sources: [_aviagenPractice],
  ),
  CulledChickDefect(
    id: 'head_missing_eye_one_eye',
    category: 'Head',
    subtype: 'Missing eye / one eye',
    description: 'Eye absent or malformed',
    commonCauses: ['Congenital developmental defects'],
    sources: [_abnormalitiesSlides],
  ),
  CulledChickDefect(
    id: 'head_exposed_brain',
    category: 'Head',
    subtype: 'Exposed brain',
    description: 'Skull not closed with exposed brain tissue',
    commonCauses: ['Severe overheating', 'Embryonic developmental failure'],
    sources: [_abnormalitiesSlides],
  ),
  CulledChickDefect(
    id: 'neuro_stargazer_nervous_signs',
    category: 'Neuro',
    subtype: 'Stargazer / nervous signs',
    description: 'Head tilted upward, neurological posture',
    commonCauses: ['Nutritional deficiency', 'Neurological damage'],
    sources: [_lohmannQuality],
  ),
  CulledChickDefect(
    id: 'neuro_wry_neck',
    category: 'Neuro',
    subtype: 'Wry neck',
    description: 'Twisted neck/spine',
    commonCauses: ['Parent flock age', 'Incubation stress'],
    sources: [_researchGateDefects],
  ),
  CulledChickDefect(
    id: 'small_weak_small_chick',
    category: 'Small/Weak',
    subtype: 'Small chick',
    description: 'Chick significantly undersized',
    commonCauses: ['Long hatch window', 'Breeder age', 'Poor incubation'],
    sources: [_cobbGuide],
  ),
  CulledChickDefect(
    id: 'hair_chick_sparse_down',
    category: 'Hair Chick',
    subtype: 'Hair chick / sparse down',
    description: 'Hair-like sparse down instead of fluffy feathers',
    commonCauses: ['Developmental defect', 'Incubation stress'],
    sources: [_researchGateDefects],
  ),
];
