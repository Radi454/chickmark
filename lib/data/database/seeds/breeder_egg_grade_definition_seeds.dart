import 'package:sqflite/sqflite.dart';

import '../../models/breeder_egg_grade_definition_model.dart';

/// System-defined egg grades (breeder-flock-performance ticket 10, design
/// doc section 5.2: "first grade, second grade, sort or reject, double
/// yolk, cracked, and damaged"). `priority` fixes the highest-priority
/// grade an egg counts under when it matches more than one description
/// (e.g. a cracked double-yolk egg).
///
/// Judgment call (not specified by the design doc, which only requires the
/// priority to exist and be unique): priorities are ordered from most
/// severe physical defect to best-quality default, on the reasoning that a
/// physically compromised egg (damaged, then cracked) is unsellable/
/// unhatchable regardless of any other trait it also has, so that
/// classification should win over a merely cosmetic/biological trait like
/// double yolk, which itself should win over a size/shape sort-reject that
/// does not by itself compromise the shell. "First grade" is the catch-all
/// default and therefore holds the lowest priority: an egg only lands
/// there when it matches none of the more specific descriptions.
final List<BreederEggGradeDefinition> kBreederEggGradeDefinitionSeeds = [
  BreederEggGradeDefinition(
    id: 'breeder-egg-grade-damaged',
    code: BreederEggGradeCode.damaged,
    name: 'Damaged',
    priority: 1,
  ),
  BreederEggGradeDefinition(
    id: 'breeder-egg-grade-cracked',
    code: BreederEggGradeCode.cracked,
    name: 'Cracked',
    priority: 2,
  ),
  BreederEggGradeDefinition(
    id: 'breeder-egg-grade-double-yolk',
    code: BreederEggGradeCode.doubleYolk,
    name: 'Double yolk',
    priority: 3,
  ),
  BreederEggGradeDefinition(
    id: 'breeder-egg-grade-sort-reject',
    code: BreederEggGradeCode.sortReject,
    name: 'Sort/Reject',
    priority: 4,
  ),
  BreederEggGradeDefinition(
    id: 'breeder-egg-grade-second-grade',
    code: BreederEggGradeCode.secondGrade,
    name: 'Second grade',
    priority: 5,
  ),
  BreederEggGradeDefinition(
    id: 'breeder-egg-grade-first-grade',
    code: BreederEggGradeCode.firstGrade,
    name: 'First grade',
    priority: 6,
  ),
];

/// Seeds `breeder_egg_grade_definitions` from [kBreederEggGradeDefinitionSeeds].
/// Idempotent and re-run on every database open (mirrors
/// `seedEggDefectTypes`/`importBreederBenchmarks`): re-running it refreshes
/// name/priority but never removes a code, because saved production entries
/// join on `gradeId` and must keep resolving.
Future<void> seedBreederEggGradeDefinitions(DatabaseExecutor db) async {
  final now = DateTime.now().toIso8601String();
  final batch = db.batch();
  for (final grade in kBreederEggGradeDefinitionSeeds) {
    batch.insert(
      'breeder_egg_grade_definitions',
      {
        ...grade.toMap(),
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'synced',
      },
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }
  await batch.commit(noResult: true);
}
