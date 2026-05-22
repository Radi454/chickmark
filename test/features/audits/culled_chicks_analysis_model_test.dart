import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/models/culled_chicks_analysis.dart';

void main() {
  test('encodes count inputs as egg-set percentages only', () {
    final encoded = CulledChicksAnalysisCodec.encodeCounts({
      'navel_open_unhealed': 3,
      'navel_string': 2,
    }, totalEggSet: 19200);

    expect(encoded, isNotNull);
    expect(encoded, contains('"pct"'));
    expect(encoded, isNot(contains('"count"')));

    final summary = CulledChicksAnalysisSummary.fromJson(
      encoded,
      totalEggSet: 19200,
    );

    expect(summary.totalEggSet, 19200);
    expect(summary.affectedPct, closeTo(5 / 19200 * 100, 0.000001));
    expect(summary.categoryPct('Navel'), closeTo(5 / 19200 * 100, 0.000001));
    expect(
      summary.entries
          .singleWhere((entry) => entry.defect.id == 'navel_open_unhealed')
          .pct,
      closeTo(3 / 19200 * 100, 0.000001),
    );
    expect(summary.topSubtype, 'Open / unhealed navel');
  });

  test('short beak is not part of culled chicks analysis persistence', () {
    expect(culledChickDefectById('head_short_beak'), isNull);
    expect(
      kCulledChickDefects.map((defect) => defect.subtype),
      isNot(contains('Short beak')),
    );

    final decoded = CulledChicksAnalysisCodec.decode(
      jsonEncode([
        {'id': 'head_short_beak', 'count': 2},
      ]),
    );

    expect(decoded, isEmpty);
    expect(
      CulledChicksAnalysisCodec.encodeCounts({'head_short_beak': 2}),
      isNull,
    );
  });

  test(
    'weak inactive chick is not part of culled chicks analysis persistence',
    () {
      expect(culledChickDefectById('small_weak_weak_inactive_chick'), isNull);
      expect(
        kCulledChickDefects.map((defect) => defect.subtype),
        isNot(contains('Weak / inactive chick')),
      );

      final decoded = CulledChicksAnalysisCodec.decode(
        jsonEncode([
          {'id': 'small_weak_weak_inactive_chick', 'count': 2},
        ]),
      );

      expect(decoded, isEmpty);
      expect(
        CulledChicksAnalysisCodec.encodeCounts({
          'small_weak_weak_inactive_chick': 2,
        }),
        isNull,
      );
    },
  );
}
