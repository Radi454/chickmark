import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite/sqflite.dart';

import 'package:hatchaudit/data/database/database_helper.dart';

import '../../support/test_database.dart';

/// Schema-level guarantees for `breeder_daily_reports`,
/// `breeder_bird_movements`, and `breeder_isolation_areas`
/// (breeder-flock-performance tickets 07 and 08): the database itself, not
/// just the application layer, refuses a duplicate report, a negative
/// quantity, a self-inconsistent closing balance, a movement whose location
/// belongs to a different flock than its report, a movement naming both or
/// neither of house/isolation area, and a duplicate isolation-area name
/// within a flock.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    await useIsolatedAppDatabase();
  });

  tearDownAll(() async {
    await DatabaseHelper().close();
  });

  String iso(DateTime d) => d.toIso8601String();

  Future<void> seedFlock(String flockId) async {
    final db = await DatabaseHelper().db;
    await db.insert('flocks', {
      'id': flockId,
      'flockId': flockId,
    }, conflictAlgorithm: ConflictAlgorithm.ignore);
  }

  Future<void> seedReport(String id, String flockId, String date) async {
    await seedFlock(flockId);
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 1, 1));
    await db.insert('breeder_daily_reports', {
      'id': id,
      'flockId': flockId,
      'reportDate': date,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  Future<void> seedHouse(String id, String flockId) async {
    await seedFlock(flockId);
    final db = await DatabaseHelper().db;
    await db.insert('houses', {'id': id, 'flockId': flockId, 'name': id});
  }

  Future<void> seedIsolationArea(String id, String flockId, {String? name}) async {
    await seedFlock(flockId);
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 1, 1));
    await db.insert('breeder_isolation_areas', {
      'id': id,
      'flockId': flockId,
      'name': name ?? id,
      'createdAt': now,
      'updatedAt': now,
    });
  }

  test('UNIQUE (flockId, reportDate) rejects a duplicate report', () async {
    await seedFlock('flock-dup');
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 1, 1));
    await db.insert('breeder_daily_reports', {
      'id': 'report-dup-1',
      'flockId': 'flock-dup',
      'reportDate': '2026-01-01',
      'createdAt': now,
      'updatedAt': now,
    });
    await expectLater(
      db.insert('breeder_daily_reports', {
        'id': 'report-dup-2',
        'flockId': 'flock-dup',
        'reportDate': '2026-01-01',
        'createdAt': now,
        'updatedAt': now,
      }),
      throwsA(anything),
    );
  });

  test('state CHECK rejects a value outside draft/submitted/approved', () async {
    await seedFlock('flock-bad-state');
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 1, 1));
    await expectLater(
      db.insert('breeder_daily_reports', {
        'id': 'report-bad-state',
        'flockId': 'flock-bad-state',
        'reportDate': '2026-01-02',
        'state': 'not_a_real_state',
        'createdAt': now,
        'updatedAt': now,
      }),
      throwsA(anything),
    );
  });

  test('a negative quantity is rejected by CHECK', () async {
    await seedReport('report-neg-1', 'flock-neg', '2026-02-01');
    await seedHouse('house-neg-1', 'flock-neg');
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 2, 1));
    await expectLater(
      db.insert('breeder_bird_movements', {
        'id': 'mv-neg-1',
        'reportId': 'report-neg-1',
        'houseId': 'house-neg-1',
        'sex': 'female',
        'opening': 10,
        'mortality': -1,
        'closing': 11,
        'createdAt': now,
        'updatedAt': now,
      }),
      throwsA(anything),
    );
  });

  test(
    'the closing-consistency CHECK rejects a self-inconsistent row',
    () async {
      await seedReport('report-inconsistent-1', 'flock-inconsistent', '2026-02-02');
      await seedHouse('house-inconsistent-1', 'flock-inconsistent');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 2));
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-inconsistent-1',
          'reportId': 'report-inconsistent-1',
          'houseId': 'house-inconsistent-1',
          'sex': 'female',
          'opening': 10,
          'mortality': 1,
          'closing': 10, // should be 9
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the sex-specific-removal CHECK rejects euthanasia on a female row',
    () async {
      await seedReport('report-sexcheck-1', 'flock-sexcheck', '2026-02-03');
      await seedHouse('house-sexcheck-1', 'flock-sexcheck');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 3));
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-sexcheck-1',
          'reportId': 'report-sexcheck-1',
          'houseId': 'house-sexcheck-1',
          'sex': 'female',
          'opening': 10,
          'euthanasia': 1,
          'closing': 9,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the house-scope trigger rejects a movement whose house belongs to a '
    'different flock',
    () async {
      await seedReport('report-scope-1', 'flock-scope-x', '2026-02-04');
      await seedHouse('house-scope-1', 'flock-scope-y'); // different flock
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 4));
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-scope-1',
          'reportId': 'report-scope-1',
          'houseId': 'house-scope-1',
          'sex': 'female',
          'opening': 10,
          'closing': 10,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the house-scope trigger accepts a movement whose house belongs to the '
    'same flock',
    () async {
      await seedReport('report-scope-2', 'flock-scope-z', '2026-02-05');
      await seedHouse('house-scope-2', 'flock-scope-z'); // same flock
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 5));
      await db.insert('breeder_bird_movements', {
        'id': 'mv-scope-2',
        'reportId': 'report-scope-2',
        'houseId': 'house-scope-2',
        'sex': 'female',
        'opening': 10,
        'closing': 10,
        'createdAt': now,
        'updatedAt': now,
      });
      final rows = await db.query(
        'breeder_bird_movements',
        where: 'id = ?',
        whereArgs: ['mv-scope-2'],
      );
      expect(rows, hasLength(1));
    },
  );

  test(
    'UNIQUE (reportId, houseId, sex) rejects a duplicate movement row',
    () async {
      await seedReport('report-mvunique-1', 'flock-mvunique', '2026-02-06');
      await seedHouse('house-mvunique-1', 'flock-mvunique');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 6));
      await db.insert('breeder_bird_movements', {
        'id': 'mv-unique-a',
        'reportId': 'report-mvunique-1',
        'houseId': 'house-mvunique-1',
        'sex': 'female',
        'opening': 10,
        'closing': 10,
        'createdAt': now,
        'updatedAt': now,
      });
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-unique-b',
          'reportId': 'report-mvunique-1',
          'houseId': 'house-mvunique-1',
          'sex': 'female',
          'opening': 20,
          'closing': 20,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  // -------------------------------------------------------------------
  // Isolation areas (breeder-flock-performance ticket 08).
  // -------------------------------------------------------------------

  test(
    'UNIQUE (flockId, name COLLATE NOCASE) rejects a duplicate isolation '
    'area name within a flock',
    () async {
      await seedIsolationArea('area-dup-1', 'flock-area-dup', name: 'Sick Pen');
      final db = await DatabaseHelper().db;
      await expectLater(
        db.insert('breeder_isolation_areas', {
          'id': 'area-dup-2',
          'flockId': 'flock-area-dup',
          'name': 'sick pen', // same name, different case
          'createdAt': iso(DateTime(2026, 1, 1)),
          'updatedAt': iso(DateTime(2026, 1, 1)),
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the same isolation area name is allowed across two different flocks',
    () async {
      await seedIsolationArea(
        'area-samename-1',
        'flock-samename-a',
        name: 'Quarantine Zone',
      );
      await seedIsolationArea(
        'area-samename-2',
        'flock-samename-b',
        name: 'Quarantine Zone',
      );
      final db = await DatabaseHelper().db;
      final rows = await db.query(
        'breeder_isolation_areas',
        where: 'name = ?',
        whereArgs: ['Quarantine Zone'],
      );
      expect(rows, hasLength(2));
    },
  );

  test(
    'a movement naming both a house and an isolation area is rejected',
    () async {
      await seedReport('report-both-1', 'flock-both', '2026-02-07');
      await seedHouse('house-both-1', 'flock-both');
      await seedIsolationArea('area-both-1', 'flock-both');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 7));
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-both-1',
          'reportId': 'report-both-1',
          'houseId': 'house-both-1',
          'isolationAreaId': 'area-both-1',
          'sex': 'female',
          'opening': 10,
          'closing': 10,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'a movement naming neither a house nor an isolation area is rejected',
    () async {
      await seedReport('report-neither-1', 'flock-neither', '2026-02-08');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 8));
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-neither-1',
          'reportId': 'report-neither-1',
          'sex': 'female',
          'opening': 10,
          'closing': 10,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the location-scope trigger rejects a movement whose isolation area '
    'belongs to a different flock',
    () async {
      await seedReport('report-isoscope-1', 'flock-isoscope-x', '2026-02-09');
      await seedIsolationArea('area-isoscope-1', 'flock-isoscope-y'); // different flock
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 9));
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-isoscope-1',
          'reportId': 'report-isoscope-1',
          'isolationAreaId': 'area-isoscope-1',
          'sex': 'female',
          'opening': 10,
          'closing': 10,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the location-scope trigger accepts a movement whose isolation area '
    'belongs to the same flock',
    () async {
      await seedReport('report-isoscope-2', 'flock-isoscope-z', '2026-02-10');
      await seedIsolationArea('area-isoscope-2', 'flock-isoscope-z'); // same flock
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 10));
      await db.insert('breeder_bird_movements', {
        'id': 'mv-isoscope-2',
        'reportId': 'report-isoscope-2',
        'isolationAreaId': 'area-isoscope-2',
        'sex': 'female',
        'opening': 10,
        'closing': 10,
        'createdAt': now,
        'updatedAt': now,
      });
      final rows = await db.query(
        'breeder_bird_movements',
        where: 'id = ?',
        whereArgs: ['mv-isoscope-2'],
      );
      expect(rows, hasLength(1));
    },
  );

  test(
    'UNIQUE (reportId, isolationAreaId, sex) rejects a duplicate isolation '
    'movement row',
    () async {
      await seedReport('report-isounique-1', 'flock-isounique', '2026-02-11');
      await seedIsolationArea('area-isounique-1', 'flock-isounique');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 2, 11));
      await db.insert('breeder_bird_movements', {
        'id': 'mv-isounique-a',
        'reportId': 'report-isounique-1',
        'isolationAreaId': 'area-isounique-1',
        'sex': 'female',
        'opening': 10,
        'closing': 10,
        'createdAt': now,
        'updatedAt': now,
      });
      await expectLater(
        db.insert('breeder_bird_movements', {
          'id': 'mv-isounique-b',
          'reportId': 'report-isounique-1',
          'isolationAreaId': 'area-isounique-1',
          'sex': 'female',
          'opening': 20,
          'closing': 20,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  // -------------------------------------------------------------------
  // Feed entries (breeder-flock-performance ticket 09).
  // -------------------------------------------------------------------

  test('a negative feedKg is rejected by CHECK', () async {
    await seedReport('report-feedneg-1', 'flock-feedneg', '2026-03-01');
    await seedHouse('house-feedneg-1', 'flock-feedneg');
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 3, 1));
    await expectLater(
      db.insert('breeder_feed_entries', {
        'id': 'feed-neg-1',
        'reportId': 'report-feedneg-1',
        'houseId': 'house-feedneg-1',
        'sex': 'female',
        'feedKg': -1,
        'createdAt': now,
        'updatedAt': now,
      }),
      throwsA(anything),
    );
  });

  test(
    'a feed entry naming both a house and an isolation area is rejected',
    () async {
      await seedReport('report-feedboth-1', 'flock-feedboth', '2026-03-02');
      await seedHouse('house-feedboth-1', 'flock-feedboth');
      await seedIsolationArea('area-feedboth-1', 'flock-feedboth');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 3, 2));
      await expectLater(
        db.insert('breeder_feed_entries', {
          'id': 'feed-both-1',
          'reportId': 'report-feedboth-1',
          'houseId': 'house-feedboth-1',
          'isolationAreaId': 'area-feedboth-1',
          'sex': 'female',
          'feedKg': 1,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'a feed entry naming neither a house nor an isolation area is rejected',
    () async {
      await seedReport('report-feedneither-1', 'flock-feedneither', '2026-03-03');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 3, 3));
      await expectLater(
        db.insert('breeder_feed_entries', {
          'id': 'feed-neither-1',
          'reportId': 'report-feedneither-1',
          'sex': 'female',
          'feedKg': 1,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the location-scope trigger rejects a feed entry whose house belongs '
    'to a different flock',
    () async {
      await seedReport('report-feedscope-1', 'flock-feedscope-x', '2026-03-04');
      await seedHouse('house-feedscope-1', 'flock-feedscope-y'); // different flock
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 3, 4));
      await expectLater(
        db.insert('breeder_feed_entries', {
          'id': 'feed-scope-1',
          'reportId': 'report-feedscope-1',
          'houseId': 'house-feedscope-1',
          'sex': 'female',
          'feedKg': 1,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'the location-scope trigger accepts a feed entry whose house belongs '
    'to the same flock',
    () async {
      await seedReport('report-feedscope-2', 'flock-feedscope-z', '2026-03-05');
      await seedHouse('house-feedscope-2', 'flock-feedscope-z'); // same flock
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 3, 5));
      await db.insert('breeder_feed_entries', {
        'id': 'feed-scope-2',
        'reportId': 'report-feedscope-2',
        'houseId': 'house-feedscope-2',
        'sex': 'female',
        'feedKg': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      final rows = await db.query(
        'breeder_feed_entries',
        where: 'id = ?',
        whereArgs: ['feed-scope-2'],
      );
      expect(rows, hasLength(1));
    },
  );

  test(
    'UNIQUE (reportId, houseId, sex) rejects a duplicate feed entry row',
    () async {
      await seedReport('report-feedunique-1', 'flock-feedunique', '2026-03-06');
      await seedHouse('house-feedunique-1', 'flock-feedunique');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 3, 6));
      await db.insert('breeder_feed_entries', {
        'id': 'feed-unique-a',
        'reportId': 'report-feedunique-1',
        'houseId': 'house-feedunique-1',
        'sex': 'female',
        'feedKg': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      await expectLater(
        db.insert('breeder_feed_entries', {
          'id': 'feed-unique-b',
          'reportId': 'report-feedunique-1',
          'houseId': 'house-feedunique-1',
          'sex': 'female',
          'feedKg': 2,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test(
    'UNIQUE (reportId, isolationAreaId, sex) rejects a duplicate isolation '
    'feed entry row',
    () async {
      await seedReport('report-feediso-1', 'flock-feediso', '2026-03-07');
      await seedIsolationArea('area-feediso-1', 'flock-feediso');
      final db = await DatabaseHelper().db;
      final now = iso(DateTime(2026, 3, 7));
      await db.insert('breeder_feed_entries', {
        'id': 'feed-iso-a',
        'reportId': 'report-feediso-1',
        'isolationAreaId': 'area-feediso-1',
        'sex': 'female',
        'feedKg': 1,
        'createdAt': now,
        'updatedAt': now,
      });
      await expectLater(
        db.insert('breeder_feed_entries', {
          'id': 'feed-iso-b',
          'reportId': 'report-feediso-1',
          'isolationAreaId': 'area-feediso-1',
          'sex': 'female',
          'feedKg': 2,
          'createdAt': now,
          'updatedAt': now,
        }),
        throwsA(anything),
      );
    },
  );

  test('breeder_daily_reports.lightHours persists a value', () async {
    await seedFlock('flock-light-1');
    final db = await DatabaseHelper().db;
    final now = iso(DateTime(2026, 3, 8));
    await db.insert('breeder_daily_reports', {
      'id': 'report-light-1',
      'flockId': 'flock-light-1',
      'reportDate': '2026-03-08',
      'lightHours': 16.5,
      'createdAt': now,
      'updatedAt': now,
    });
    final rows = await db.query(
      'breeder_daily_reports',
      where: 'id = ?',
      whereArgs: ['report-light-1'],
    );
    expect(rows.single['lightHours'], 16.5);
  });
}
