import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/database/database_helper.dart';
import 'package:hatchaudit/data/models/agent_intake_models.dart';
import 'package:hatchaudit/data/repositories/agent_intake_repository.dart';
import 'package:sqflite/sqflite.dart';

import '../../support/test_database.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory databaseDirectory;
  late AgentIntakeRepository repository;

  setUpAll(() async {
    databaseDirectory = await useIsolatedAppDatabase();
  });

  setUp(() async {
    await resetAppDatabase();
    repository = AgentIntakeRepository();
    await _seedDependencies();
  });

  tearDownAll(() async {
    await resetAppDatabase();
    if (databaseDirectory.existsSync()) {
      await databaseDirectory.delete(recursive: true);
    }
  });

  test('lists only confirmed review sessions newest first', () async {
    await _insertSession('review-old', 'awaiting_admin_review', 8);
    await _insertSession('collecting', 'collecting', 10);
    await _insertSession('review-new', 'awaiting_admin_review', 12);

    final rows = await repository.listAwaitingReview();

    expect(rows.map((row) => row.id), ['review-new', 'review-old']);
    expect(rows.every((row) => row.userConfirmedAt != null), isTrue);
  });

  test('loads the normalized values and conversation evidence graph', () async {
    await _insertSession('intake-1', 'awaiting_admin_review', 12);
    final db = await DatabaseHelper().db;
    await db.insert('agent_intake_values', {
      'id': 'intake-1:pasgarSampleSize',
      'intakeSessionId': 'intake-1',
      'fieldKey': 'pasgarSampleSize',
      'valueJson': '40',
      'sourcePhrase': 'sample 40',
      'confidence': 0.99,
      'createdAt': _time(11),
      'updatedAt': _time(11),
      'syncStatus': 'synced',
    });
    await db.insert('agent_intake_turns', {
      'id': 'turn-1',
      'intakeSessionId': 'intake-1',
      'direction': 'inbound',
      'telegramUpdateId': 'update-1',
      'telegramMessageId': 'message-1',
      'text': 'sample 40',
      'language': 'en',
      'intent': 'provide_data',
      'createdAt': _time(11),
      'syncStatus': 'synced',
    });

    final details = await repository.loadDetails('intake-1');

    expect(details, isNotNull);
    expect(details!.valueFor('pasgarSampleSize')!.intValue, 40);
    expect(details.turns.single.text, 'sample 40');
  });

  test(
    'admin edit preserves confirmed evidence and updates working values',
    () async {
      await _insertSession('intake-1', 'awaiting_admin_review', 12);

      await repository.updateValue(
        intakeId: 'intake-1',
        fieldKey: 'pasgarNavelCount',
        value: 3,
        updatedAt: DateTime.utc(2026, 7, 28, 13),
      );

      final db = await DatabaseHelper().db;
      final value = (await db.query(
        'agent_intake_values',
        where: 'id = ?',
        whereArgs: ['intake-1:pasgarNavelCount'],
      )).single;
      final session = (await db.query(
        'agent_intake_sessions',
        where: 'id = ?',
        whereArgs: ['intake-1'],
      )).single;
      final snapshot =
          jsonDecode(session['summarySnapshotJson']! as String)
              as Map<String, dynamic>;
      final workingValues =
          jsonDecode(session['workingValuesJson']! as String)
              as Map<String, dynamic>;

      expect(value['valueJson'], '3');
      expect(value['syncStatus'], 'pending');
      expect(session['summaryVersion'], 1);
      expect(session['syncStatus'], 'pending');
      expect((snapshot['values'] as Map)['pasgarNavelCount'], 1);
      expect(workingValues['pasgarNavelCount'], 3);

      await expectLater(
        repository.updateValue(
          intakeId: 'intake-1',
          fieldKey: 'pasgarBellyCount',
          value: 41,
        ),
        throwsArgumentError,
      );
    },
  );

  test('reviews and validates a non-Pasgar station with list values', () async {
    await _insertWeightSession('weights-1');

    final session = (await repository.listAwaitingReview()).single;
    expect(session.schemaKey, 'chicks.weights');
    expect(session.scope, AgentIntakeScope.house);

    await repository.updateValue(
      intakeId: session.id,
      fieldKey: 'weightsJson',
      value: [40.0, 41.5, 42.0],
      updatedAt: DateTime.utc(2026, 7, 28, 13),
    );

    final details = await repository.loadDetails(session.id);
    expect(details!.session.workingValues['weightsJson'], [40.0, 41.5, 42.0]);
    expect(
      details.session.summary!.values['weightsJson'],
      [39.5, 40.0, 41.0],
      reason: 'the customer-confirmed evidence remains unchanged',
    );

    await expectLater(
      repository.updateValue(
        intakeId: session.id,
        fieldKey: 'weightsJson',
        value: [0],
      ),
      throwsArgumentError,
    );
  });

  test('rejection requires a reason and records review state', () async {
    await _insertSession('intake-1', 'awaiting_admin_review', 12);

    await expectLater(
      repository.reject(
        intakeId: 'intake-1',
        reason: '   ',
        reviewedBy: 'admin-1',
      ),
      throwsArgumentError,
    );
    await repository.reject(
      intakeId: 'intake-1',
      reason: 'Customer identity does not match',
      reviewedBy: 'admin-1',
      reviewedAt: DateTime.utc(2026, 7, 28, 13),
    );

    final details = await repository.loadDetails('intake-1');
    expect(details!.session.state, AgentIntakeState.rejected);
    expect(details.session.rejectionReason, 'Customer identity does not match');
    final db = await DatabaseHelper().db;
    final row = (await db.query('agent_intake_sessions')).single;
    expect(row['syncStatus'], 'pending');
  });

  test('mirrors authenticated RPC approval without re-pushing it', () async {
    await _insertSession('intake-1', 'awaiting_admin_review', 12);

    await repository.markApproved(
      intakeId: 'intake-1',
      auditSessionId: 'audit-1',
      panelRowId: 'panel-1',
      reviewedBy: 'admin-1',
      reviewedAt: DateTime.utc(2026, 7, 28, 13),
    );

    final details = await repository.loadDetails('intake-1');
    expect(details!.session.state, AgentIntakeState.approved);
    expect(details.session.approvedSessionId, 'audit-1');
    expect(details.session.approvedPanelRowId, 'panel-1');
    final db = await DatabaseHelper().db;
    final row = (await db.query('agent_intake_sessions')).single;
    expect(row['syncStatus'], 'synced');
  });

  test('suggests only audit sessions with the same intake context', () async {
    await _insertSession('intake-1', 'awaiting_admin_review', 12);
    final db = await DatabaseHelper().db;
    await db.insert('audit_sessions', {
      'id': 'matching',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'hatcheryId': 'hatchery-1',
      'date': '2026-07-28',
      'status': 'in_progress',
      'createdAt': _time(10),
      'updatedAt': _time(10),
    });
    await db.insert('audit_sessions', {
      'id': 'wrong-date',
      'customerId': 'customer-1',
      'flockId': 'flock-1',
      'hatcheryId': 'hatchery-1',
      'date': '2026-07-27',
      'status': 'in_progress',
      'createdAt': _time(9),
      'updatedAt': _time(9),
    });
    final intake = (await repository.listAwaitingReview()).single;

    final matches = await repository.listMatchingAuditSessions(intake);

    expect(matches.map((session) => session.id), ['matching']);
  });
}

Future<void> _seedDependencies() async {
  final db = await DatabaseHelper().db;
  await db.insert('customers', {
    'id': 'customer-1',
    'name': 'Customer One',
    'createdAt': _time(1),
    'createdBy': 'test',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('flocks', {
    'id': 'flock-1',
    'customerId': 'customer-1',
    'flockId': 'Flock One',
    'breed': 'Ross',
    'entryDate': _time(1),
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('hatcheries', {
    'id': 'hatchery-1',
    'customerId': 'customer-1',
    'name': 'Main Hatchery',
    'createdAt': _time(1),
    'createdBy': 'test',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
  await db.insert('telegram_staff_links', {
    'id': 'staff-1',
    'telegramUserId': 'telegram-user-1',
    'telegramChatId': 'chat-1',
    'displayName': 'Staff One',
    'status': 'allowed',
    'accessRole': 'admin',
    'createdAt': _time(1),
    'updatedAt': _time(1),
    'syncStatus': 'synced',
  }, conflictAlgorithm: ConflictAlgorithm.replace);
}

Future<void> _insertSession(String id, String state, int hour) async {
  final values = <String, int>{
    'pasgarSampleSize': 40,
    'pasgarReflexesCount': 2,
    'pasgarBeakCount': 1,
    'pasgarNavelCount': 1,
    'pasgarBellyCount': 1,
    'pasgarLegCount': 2,
    'pasgarFeatherDevCount': 3,
  };
  final confirmed = state == 'awaiting_admin_review';
  final db = await DatabaseHelper().db;
  await db.insert('agent_intake_sessions', {
    'id': id,
    'staffLinkId': 'staff-1',
    'telegramChatId': 'chat-1-$id',
    'schemaKey': 'chicks.pasgar',
    'schemaVersion': 1,
    'state': state,
    'language': 'en',
    'customerId': 'customer-1',
    'customerName': 'Customer One',
    'flockId': 'flock-1',
    'flockName': 'Flock One',
    'hatcheryId': 'hatchery-1',
    'hatcheryName': 'Main Hatchery',
    'auditDate': '2026-07-28',
    'scope': 'pool',
    'workingValuesJson': jsonEncode(values),
    'summaryVersion': 1,
    'summarySnapshotJson': jsonEncode({
      'version': 1,
      'values': values,
      'generatedAt': _time(hour),
    }),
    'userConfirmedAt': confirmed ? _time(hour) : null,
    'createdAt': _time(hour - 1),
    'updatedAt': _time(hour),
    'syncStatus': 'synced',
    'lastSyncedAt': _time(hour),
  });
}

Future<void> _insertWeightSession(String id) async {
  final values = <String, Object?>{
    'weightsJson': [39.5, 40.0, 41.0],
  };
  final db = await DatabaseHelper().db;
  await db.insert('agent_intake_sessions', {
    'id': id,
    'staffLinkId': 'staff-1',
    'telegramChatId': 'chat-weights-$id',
    'schemaKey': 'chicks.weights',
    'schemaVersion': 1,
    'state': 'awaiting_admin_review',
    'language': 'mixed',
    'customerId': 'customer-1',
    'customerName': 'Customer One',
    'flockId': 'flock-1',
    'flockName': 'Flock One',
    'hatcheryId': 'hatchery-1',
    'hatcheryName': 'Main Hatchery',
    'auditDate': '2026-07-28',
    'scope': 'house',
    'workingValuesJson': jsonEncode(values),
    'summaryVersion': 1,
    'summarySnapshotJson': jsonEncode({
      'version': 1,
      'schemaKey': 'chicks.weights',
      'schemaVersion': 1,
      'values': values,
      'calculations': {
        'sampleSize': 3,
        'avgWeight': 40.2,
        'uniformityPct': 100.0,
        'cvPct': 1.9,
      },
      'generatedAt': _time(12),
    }),
    'userConfirmedAt': _time(12),
    'createdAt': _time(11),
    'updatedAt': _time(12),
    'syncStatus': 'synced',
    'lastSyncedAt': _time(12),
  });
}

String _time(int hour) => DateTime.utc(2026, 7, 28, hour).toIso8601String();
