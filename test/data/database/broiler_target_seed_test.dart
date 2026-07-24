import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/seeds/broiler_target_seeds.dart';
import 'package:hatchaudit/data/models/poultry_hierarchy_models.dart';

void main() {
  const expectedBodyWeights = <String, List<num?>>{
    'ross-308-2022-as-hatched': [44, 213, 1012, 2296, 2998, 4318],
    'ross-308-2022-male': [44, 213, 1046, 2441, 3222, 4714],
    'ross-308-2022-female': [44, 214, 978, 2150, 2774, 3922],
    'indian-river-2022-as-hatched': [44, 211, 1010, 2295, 2995, 4297],
    'indian-river-2022-male': [44, 211, 1044, 2441, 3219, 4692],
    'indian-river-2022-female': [44, 212, 976, 2149, 2770, 3903],
    'arbor-acres-plus-2022-as-hatched': [44, 209, 1006, 2287, 2981, 4263],
    'arbor-acres-plus-2022-male': [44, 209, 1040, 2432, 3204, 4654],
    'arbor-acres-plus-2022-female': [44, 210, 972, 2142, 2758, 3872],
    'hubbard-efficiency-plus-v-2025-06-as-hatched': [
      43,
      216,
      1035,
      2330,
      3028,
      4324,
    ],
    'hubbard-efficiency-plus-v-2025-06-male': [
      null,
      null,
      1074,
      2490,
      3272,
      4719,
    ],
    'hubbard-efficiency-plus-v-2025-06-female': [
      null,
      null,
      995,
      2169,
      2784,
      3928,
    ],
    'cobb500-2022-as-hatched': [42, 202, 1116, 2521, 3278, 4641],
    'cobb500-2022-male': [42, 205, 1188, 2694, 3503, 4953],
    'cobb500-2022-female': [42, 199, 1043, 2348, 3052, 4329],
  };
  const sampledAges = [0, 7, 21, 35, 42, 56];

  test(
    'official catalogue has complete versioned breed and sex identities',
    () {
      expect(officialBroilerTargetCatalogue, hasLength(15));
      expect(
        officialBroilerTargetCatalogue.map((entry) => entry.profile.id).toSet(),
        expectedBodyWeights.keys.toSet(),
      );
      expect(
        officialBroilerTargetCatalogue
            .map((entry) => entry.profile.sexProfile)
            .toSet(),
        {
          FlockSexProfile.asHatched,
          FlockSexProfile.male,
          FlockSexProfile.female,
        },
      );
      expect(
        officialBroilerTargetCatalogue.any(
          (entry) => entry.profile.breed.contains('AP'),
        ),
        isFalse,
      );

      for (final entry in officialBroilerTargetCatalogue) {
        expect(entry.profile.isOfficial, isTrue, reason: entry.profile.id);
        expect(entry.profile.sourceTitle, isNotEmpty, reason: entry.profile.id);
        expect(
          Uri.parse(entry.profile.sourceUrl).isScheme('https'),
          isTrue,
          reason: entry.profile.id,
        );
        expect(entry.rows, hasLength(57), reason: entry.profile.id);
        expect(
          entry.rows.map((row) => row.ageDay).toSet(),
          Set<int>.from(List<int>.generate(57, (index) => index)),
          reason: entry.profile.id,
        );
      }
    },
  );

  test('representative source body weights match every official profile', () {
    for (final entry in officialBroilerTargetCatalogue) {
      final expected = expectedBodyWeights[entry.profile.id]!;
      for (var index = 0; index < sampledAges.length; index += 1) {
        final row = entry.rows.singleWhere(
          (candidate) => candidate.ageDay == sampledAges[index],
        );
        expect(
          row.bodyWeightG,
          expected[index],
          reason: '${entry.profile.id} day ${sampledAges[index]}',
        );
      }
    }
  });

  test(
    'source-absent values stay null and Hubbard water documents its method',
    () {
      final hubbardMale = officialBroilerTargetCatalogue.singleWhere(
        (entry) => entry.profile.id == 'hubbard-efficiency-plus-v-2025-06-male',
      );
      expect(hubbardMale.rows[7].bodyWeightG, isNull);
      expect(hubbardMale.rows[21].dailyFeedIntakeGPerLivingBird, isNull);
      expect(hubbardMale.rows[21].waterMlPerLivingBird, isNull);

      final hubbardAsHatched = officialBroilerTargetCatalogue.singleWhere(
        (entry) =>
            entry.profile.id == 'hubbard-efficiency-plus-v-2025-06-as-hatched',
      );
      final day35 = hubbardAsHatched.rows[35];
      expect(day35.waterMlPerLivingBird, closeTo(183 * 1.70, 0.0001));
      expect(day35.metricMethodNotes, contains('feed objective × 1.70'));

      final ross = officialBroilerTargetCatalogue.first;
      expect(ross.rows[35].waterMlPerLivingBird, isNull);
      expect(ross.rows[35].metricMethodNotes, isNot(contains('1.70')));
    },
  );
}
