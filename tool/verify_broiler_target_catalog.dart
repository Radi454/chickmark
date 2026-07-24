import 'dart:io';

import 'package:hatchaudit/data/database/seeds/broiler_target_seeds.dart';

void main() {
  final profileIds = <String>{};
  var rowCount = 0;

  for (final entry in officialBroilerTargetCatalogue) {
    final profile = entry.profile;
    if (!profileIds.add(profile.id)) {
      throw StateError('Duplicate profile id: ${profile.id}');
    }
    if (!profile.isOfficial) {
      throw StateError(
        'Official catalogue contains a custom profile: ${profile.id}',
      );
    }
    if (!Uri.parse(profile.sourceUrl).isScheme('https')) {
      throw StateError('Non-HTTPS source URL in ${profile.id}');
    }
    if (profile.breed.contains('Ross 308 AP')) {
      throw StateError('Ross 308 AP is outside the approved initial catalogue');
    }

    final ages = entry.rows.map((row) => row.ageDay).toSet();
    if (ages.length != entry.rows.length) {
      throw StateError('Duplicate age in ${profile.id}');
    }
    final expectedAges = Set<int>.from(
      List<int>.generate(57, (index) => index),
    );
    if (ages.length != 57 || !ages.containsAll(expectedAges)) {
      throw StateError('Incomplete day 0-56 objective rows in ${profile.id}');
    }

    for (final row in entry.rows) {
      final hasWaterMethod =
          row.metricMethodNotes?.contains('feed objective × 1.70') ?? false;
      if (row.waterMlPerLivingBird != null) {
        if (profile.brand != 'Hubbard' ||
            row.dailyFeedIntakeGPerLivingBird == null ||
            !hasWaterMethod) {
          throw StateError('Undocumented water objective in ${row.id}');
        }
        final expectedWater = row.dailyFeedIntakeGPerLivingBird! * 1.70;
        if ((row.waterMlPerLivingBird! - expectedWater).abs() > 0.0001) {
          throw StateError('Incorrect Hubbard water objective in ${row.id}');
        }
      } else if (hasWaterMethod) {
        throw StateError(
          'Water method note without a water target in ${row.id}',
        );
      }
    }
    rowCount += entry.rows.length;
  }

  if (profileIds.length != 15) {
    throw StateError(
      'Expected 15 official breed/sex profiles, found ${profileIds.length}',
    );
  }

  stdout.writeln(
    'Verified ${profileIds.length} official Broiler profiles '
    'and $rowCount day-level objective rows.',
  );
}
