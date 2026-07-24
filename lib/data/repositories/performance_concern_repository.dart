import 'dart:convert';

import 'package:sqflite/sqflite.dart';
import 'package:uuid/uuid.dart';

import '../database/database_helper.dart';
import '../database/seeds/performance_rule_seeds.dart';
import '../models/performance_concern_models.dart';

class PerformanceConcernRepository {
  PerformanceConcernRepository({
    DatabaseHelper? databaseHelper,
    Uuid uuid = const Uuid(),
  }) : _databaseHelper = databaseHelper ?? DatabaseHelper(),
       _uuid = uuid;

  final DatabaseHelper _databaseHelper;
  final Uuid _uuid;

  Future<void> ensureDefaultRulesSeeded() async {
    final db = await _databaseHelper.db;
    final batch = db.batch();
    for (final rule in defaultPerformanceAlertRules) {
      batch.insert('performance_alert_rules', {
        ...rule.toMap(),
        'syncStatus': 'synced',
      }, conflictAlgorithm: ConflictAlgorithm.ignore);
    }
    await batch.commit(noResult: true);
  }

  Future<void> saveRule(PerformanceAlertRule rule) async {
    if (rule.scopeLevel == AlertRuleScope.customer &&
        (rule.customerId == null || rule.customerId!.isEmpty)) {
      throw ArgumentError('Customer rules require a customer id');
    }
    final db = await _databaseHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    final values = {
      ...rule.toMap(),
      'updatedAt': now,
      'syncStatus': 'pending',
      'dirtyAt': now,
      'syncError': null,
    };
    final existing = await db.query(
      'performance_alert_rules',
      columns: ['id'],
      where: 'id = ?',
      whereArgs: [rule.id],
      limit: 1,
    );
    if (existing.isEmpty) {
      await db.insert('performance_alert_rules', {...values, 'createdAt': now});
    } else {
      await db.update(
        'performance_alert_rules',
        values,
        where: 'id = ?',
        whereArgs: [rule.id],
      );
    }
  }

  Future<List<PerformanceAlertRule>> listEffectiveRules(
    String customerId,
  ) async {
    final db = await _databaseHelper.db;
    final rows = await db.query(
      'performance_alert_rules',
      where:
          "isEnabled = 1 AND (scopeLevel = 'global' "
          "OR (scopeLevel = 'customer' AND customerId = ?))",
      whereArgs: [customerId],
      orderBy: 'metricKey, scopeLevel',
    );
    final effective = <String, PerformanceAlertRule>{};
    for (final row in rows) {
      final rule = PerformanceAlertRule.fromMap(row);
      final existing = effective[rule.metricKey];
      if (existing == null || rule.scopeLevel == AlertRuleScope.customer) {
        effective[rule.metricKey] = rule;
      }
    }
    final result = effective.values.toList()
      ..sort((left, right) => left.metricKey.compareTo(right.metricKey));
    return result;
  }

  Future<PerformanceConcern> upsertDetection(
    PerformanceAlertDetection detection,
  ) async {
    await ensureDefaultRulesSeeded();
    final db = await _databaseHelper.db;
    return db.transaction((txn) async {
      final identity = _scopeWhere(detection);
      final active = await txn.query(
        'performance_concerns',
        where:
            '${identity.where} AND status IN '
            "('open', 'monitoring', 'assigned_to_visit')",
        whereArgs: identity.args,
        orderBy: 'lastObservedAt DESC',
        limit: 1,
      );
      final evidenceJson = jsonEncode({
        ...detection.evidence,
        'investigationKeys': detection.investigationKeys,
      });
      final now = DateTime.now().toUtc().toIso8601String();
      if (active.isNotEmpty) {
        final id = active.single['id']! as String;
        await txn.update(
          'performance_concerns',
          {
            'severity': detection.severity.storageKey,
            'lastObservedAt': detection.observedAt.toIso8601String(),
            'evidenceWindowStart': detection.windowStart.toIso8601String(),
            'evidenceWindowEnd': detection.windowEnd.toIso8601String(),
            'baselineValue': detection.baselineValue,
            'targetValue': detection.targetValue,
            'actualValue': detection.actualValue,
            'evidenceJson': evidenceJson,
            'updatedAt': now,
            'syncStatus': 'pending',
            'dirtyAt': now,
            'syncError': null,
          },
          where: 'id = ?',
          whereArgs: [id],
        );
        return (await _getConcernWithExecutor(txn, id))!;
      }

      final closed = await txn.query(
        'performance_concerns',
        columns: const ['id'],
        where:
            '${identity.where} AND status IN '
            "('resolved', 'dismissed')",
        whereArgs: identity.args,
        orderBy: 'lastObservedAt DESC',
        limit: 1,
      );
      final id = _uuid.v4();
      await txn.insert('performance_concerns', {
        'id': id,
        'ruleId': detection.ruleId,
        'customerId': detection.customerId,
        'farmId': detection.farmId,
        'flockId': detection.flockId,
        'placementId': detection.placementId,
        'houseId': detection.houseId,
        'metricKey': detection.metricKey,
        'severity': detection.severity.storageKey,
        'firstObservedAt': detection.observedAt.toIso8601String(),
        'lastObservedAt': detection.observedAt.toIso8601String(),
        'evidenceWindowStart': detection.windowStart.toIso8601String(),
        'evidenceWindowEnd': detection.windowEnd.toIso8601String(),
        'baselineValue': detection.baselineValue,
        'targetValue': detection.targetValue,
        'actualValue': detection.actualValue,
        'evidenceJson': evidenceJson,
        'status': ConcernStatus.open.storageKey,
        'recurrenceOfId': closed.isEmpty ? null : closed.single['id'],
        'createdAt': now,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
      });
      return (await _getConcernWithExecutor(txn, id))!;
    });
  }

  Future<PerformanceConcern?> getConcern(String id) async {
    final db = await _databaseHelper.db;
    return _getConcernWithExecutor(db, id);
  }

  Future<void> setMonitoring(String id) =>
      _setStatus(id, ConcernStatus.monitoring);

  Future<void> resolve(
    String id, {
    required String resolvedBy,
    required String notes,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _updateConcern(id, {
      'status': ConcernStatus.resolved.storageKey,
      'resolvedAt': now,
      'resolvedBy': resolvedBy,
      'resolutionNotes': notes,
    });
  }

  Future<void> dismiss(
    String id, {
    required String dismissedBy,
    required String reason,
  }) async {
    final now = DateTime.now().toUtc().toIso8601String();
    await _updateConcern(id, {
      'status': ConcernStatus.dismissed.storageKey,
      'dismissedAt': now,
      'dismissedBy': dismissedBy,
      'dismissalReason': reason,
    });
  }

  Future<void> _setStatus(String id, ConcernStatus status) =>
      _updateConcern(id, {'status': status.storageKey});

  Future<void> _updateConcern(String id, Map<String, Object?> changes) async {
    final db = await _databaseHelper.db;
    final now = DateTime.now().toUtc().toIso8601String();
    await db.update(
      'performance_concerns',
      {
        ...changes,
        'updatedAt': now,
        'syncStatus': 'pending',
        'dirtyAt': now,
        'syncError': null,
      },
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<PerformanceConcern?> _getConcernWithExecutor(
    DatabaseExecutor db,
    String id,
  ) async {
    final rows = await db.query(
      'performance_concerns',
      where: 'id = ?',
      whereArgs: [id],
      limit: 1,
    );
    return rows.isEmpty ? null : PerformanceConcern.fromMap(rows.single);
  }

  _Where _scopeWhere(PerformanceAlertDetection detection) {
    final clauses = <String>['ruleId = ?', 'customerId = ?', 'metricKey = ?'];
    final args = <Object?>[
      detection.ruleId,
      detection.customerId,
      detection.metricKey,
    ];
    for (final entry in <String, String?>{
      'farmId': detection.farmId,
      'flockId': detection.flockId,
      'placementId': detection.placementId,
      'houseId': detection.houseId,
    }.entries) {
      if (entry.value == null) {
        clauses.add('${entry.key} IS NULL');
      } else {
        clauses.add('${entry.key} = ?');
        args.add(entry.value);
      }
    }
    return _Where(clauses.join(' AND '), args);
  }
}

class _Where {
  const _Where(this.where, this.args);

  final String where;
  final List<Object?> args;
}
