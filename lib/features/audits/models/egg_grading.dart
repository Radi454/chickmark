import 'dart:convert';

class EggDefectType {
  const EggDefectType({
    required this.code,
    required this.name,
    required this.category,
    required this.isReject,
    required this.description,
    required this.sortOrder,
    this.imageAsset,
  });

  final String code;
  final String name;
  final String category;
  final bool isReject;
  final String description;
  final int sortOrder;
  final String? imageAsset;
}

const String kEggDefectCategoryContamination = 'Shell contamination';
const String kEggDefectCategoryIntegrity = 'Shell integrity';
const String kEggDefectCategoryQuality = 'Shell quality';
const String kEggDefectCategoryShape = 'Shape and size';
const String kEggDefectCategoryOther = 'Other';

const List<EggDefectType> kEggDefectTypes = [
  EggDefectType(
    code: 'dirty',
    name: 'Dirty',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Faecal or litter contamination on the shell.',
    sortOrder: 10,
  ),
  EggDefectType(
    code: 'yolk_stained',
    name: 'Yolk stained',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Yolk from a broken egg dried onto the shell.',
    sortOrder: 20,
  ),
  EggDefectType(
    code: 'blood_stained',
    name: 'Blood stained',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Blood smeared on the shell at lay.',
    sortOrder: 30,
  ),
  EggDefectType(
    code: 'stained',
    name: 'Stained',
    category: kEggDefectCategoryContamination,
    isReject: true,
    description: 'Any other surface staining.',
    sortOrder: 40,
  ),
  EggDefectType(
    code: 'cracked',
    name: 'Cracked',
    category: kEggDefectCategoryIntegrity,
    isReject: true,
    description: 'Visible shell fracture.',
    sortOrder: 50,
  ),
  EggDefectType(
    code: 'hairline_crack',
    name: 'Hairline crack',
    category: kEggDefectCategoryIntegrity,
    isReject: true,
    description: 'Fine crack, usually only visible when candled.',
    sortOrder: 60,
  ),
  EggDefectType(
    code: 'toe_hole',
    name: 'Toe hole',
    category: kEggDefectCategoryIntegrity,
    isReject: true,
    description: 'Puncture from a hen treading on the egg.',
    sortOrder: 70,
  ),
  EggDefectType(
    code: 'thin_shell',
    name: 'Thin shell',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Translucent, weak shell.',
    sortOrder: 80,
  ),
  EggDefectType(
    code: 'wrinkled',
    name: 'Wrinkled',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Corrugated shell surface.',
    sortOrder: 90,
  ),
  EggDefectType(
    code: 'ridged',
    name: 'Ridged',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Raised band or ridge around the shell.',
    sortOrder: 100,
  ),
  EggDefectType(
    code: 'calcium_deposit',
    name: 'Calcium deposit',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Chalky calcium lumps on the shell.',
    sortOrder: 110,
  ),
  EggDefectType(
    code: 'membrane',
    name: 'Membrane',
    category: kEggDefectCategoryQuality,
    isReject: true,
    description: 'Exposed membrane where shell is missing.',
    sortOrder: 120,
  ),
  EggDefectType(
    code: 'round',
    name: 'Round',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Round rather than oval; hatches less well.',
    sortOrder: 130,
  ),
  EggDefectType(
    code: 'elongated',
    name: 'Elongated',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Abnormally long egg.',
    sortOrder: 140,
  ),
  EggDefectType(
    code: 'slab_sided',
    name: 'Slab sided',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Flattened side from pressure before shell set.',
    sortOrder: 150,
  ),
  EggDefectType(
    code: 'small',
    name: 'Small',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Below the acceptable weight range.',
    sortOrder: 160,
  ),
  EggDefectType(
    code: 'double_yolk',
    name: 'Double yolk',
    category: kEggDefectCategoryShape,
    isReject: true,
    description: 'Oversized egg with two yolks.',
    sortOrder: 170,
  ),
  EggDefectType(
    code: 'other',
    name: 'Other',
    category: kEggDefectCategoryOther,
    isReject: true,
    description: 'Any defect not listed above; use the note field.',
    sortOrder: 180,
  ),
];

EggDefectType? eggDefectTypeForCode(String code) {
  for (final defect in kEggDefectTypes) {
    if (defect.code == code) return defect;
  }
  return null;
}

class EggGradingSummary {
  const EggGradingSummary({
    required this.sampleSize,
    required this.rejectedCount,
    required this.counts,
  });

  final int sampleSize;
  final int rejectedCount;
  final Map<String, int> counts;

  int get acceptableCount => (sampleSize - rejectedCount).clamp(0, sampleSize);
  double get rejectedPct => _pct(rejectedCount);
  double get acceptablePct => _pct(acceptableCount);

  String? get topDefectCode {
    String? top;
    var best = 0;
    for (final entry in counts.entries) {
      if (entry.value > best) {
        best = entry.value;
        top = entry.key;
      }
    }
    return top;
  }

  double? get topDefectPct {
    final code = topDefectCode;
    return code == null ? null : _pct(counts[code] ?? 0);
  }

  double pctFor(String code) => _pct(counts[code] ?? 0);

  bool get hasData => sampleSize > 0 || counts.values.any((v) => v > 0);

  double _pct(int value) => sampleSize <= 0 ? 0 : (value * 100) / sampleSize;

  String? get encodedJson {
    final positive = {
      for (final entry in counts.entries)
        if (entry.value > 0) entry.key: entry.value,
    };
    if (positive.isEmpty) return null;
    return jsonEncode([
      for (final entry in positive.entries)
        {
          'code': entry.key,
          'name': eggDefectTypeForCode(entry.key)?.name ?? entry.key,
          'category': eggDefectTypeForCode(entry.key)?.category,
          'isReject': eggDefectTypeForCode(entry.key)?.isReject ?? true,
          'count': entry.value,
        },
    ]);
  }

  factory EggGradingSummary.fromCounts({
    required int sampleSize,
    required int rejectedCount,
    required Map<String, int> counts,
  }) {
    return EggGradingSummary(
      sampleSize: sampleSize,
      rejectedCount: rejectedCount,
      counts: {
        for (final entry in counts.entries)
          if (entry.value > 0) entry.key: entry.value,
      },
    );
  }

  factory EggGradingSummary.fromJson(
    String? source, {
    int? sampleSize,
    int? rejectedCount,
  }) {
    final counts = <String, int>{};
    if (source != null && source.isNotEmpty) {
      try {
        final decoded = jsonDecode(source);
        if (decoded is List) {
          for (final item in decoded) {
            if (item is! Map) continue;
            final code = item['code']?.toString();
            final count = item['count'];
            if (code == null || count is! num) continue;
            if (count.toInt() > 0) counts[code] = count.toInt();
          }
        }
      } on FormatException {
        // A stale or partially written JSON mirror must not prevent the
        // station from reopening. Supplied totals remain authoritative.
      }
    }
    return EggGradingSummary(
      sampleSize: sampleSize ?? 0,
      rejectedCount: rejectedCount ?? 0,
      counts: counts,
    );
  }
}

class EggGradingValidation {
  const EggGradingValidation._();

  /// One egg may carry several defects, so the defect counts are occurrences
  /// and their sum may legitimately exceed the sample size. Only per-defect
  /// and rejected-count ceilings are enforced.
  static List<String> validate({
    required int sampleSize,
    required int rejectedCount,
    required Map<String, int> counts,
  }) {
    final errors = <String>[];
    if (sampleSize < 0) errors.add('Eggs inspected cannot be negative.');
    if (rejectedCount < 0) errors.add('Eggs rejected cannot be negative.');
    if (rejectedCount > sampleSize) {
      errors.add('Eggs rejected cannot exceed eggs inspected.');
    }
    for (final entry in counts.entries) {
      final name = eggDefectTypeForCode(entry.key)?.name ?? entry.key;
      if (entry.value < 0) {
        errors.add('$name count cannot be negative.');
      } else if (entry.value > sampleSize) {
        errors.add('$name count cannot exceed eggs inspected.');
      }
    }
    return errors;
  }
}
