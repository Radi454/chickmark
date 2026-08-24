import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/agent/station_registry.dart';
import 'package:hatchaudit/data/models/panel_sample_schema.dart';

/// Safety net for the agent station registry against the stored panel schema.
///
/// The registry is what the conversational agents use to decide where a value
/// they collected gets written. It is authored by hand in
/// `tool/agent_schema/station_registry.json` and code-generated into Dart, so
/// nothing stops it naming a column the panel tables do not have — the agent
/// would then write into nowhere. These tests bind the chick schemas to
/// [PanelSampleSchema], which is what actually creates the tables.

/// Columns the panel save coordinator puts on every panel table, so a registry
/// mapping may legitimately target one of them instead of a measurement
/// column.
const _panelCommonColumns = {
  'id',
  'sessionId',
  'customerId',
  'flockId',
  'hatcheryId',
  'date',
  'breed',
  'flockAgeWeeks',
  'house',
  'setter',
  'hatcher',
  'trolley',
  'tray',
  'position',
  'storagePeriodDays',
  'bmkAgeWeeks',
  'notes',
  'createdAt',
  'updatedAt',
};

/// Measurement columns on the chick panel tables that no registry field or
/// calculation claims. Every entry is a deliberate omission, not an oversight,
/// and each line says why. Anything new appearing here means a column was
/// added without teaching the agent about it.
const _unclaimedColumns = {
  'chick_quality': {
    // Photo attachments: captured by the camera UI, never by a conversation.
    'yfbmPhoto',
    'cvtPhotosJson',
    'pmPhotosJson',
    // Legacy pre-readings CVT capture (three fixed baskets). Superseded by
    // `cvtReadingsJson`, kept only so old rows still render.
    'cvtTopBasket',
    'cvtTopTemp',
    'cvtTopPhoto',
    'cvtMiddleBasket',
    'cvtMiddleTemp',
    'cvtMiddlePhoto',
    'cvtBottomBasket',
    'cvtBottomTemp',
    'cvtBottomPhoto',
    // Free-form post-mortem extras: an open-ended lesion list and two cause
    // notes, none of which map to a typed registry field.
    'pmOtherLesionsJson',
    'pmSuspectedCauseAuto',
    'pmSuspectedCauseManual',
  },
  'chick_weights': {
    // Benchmark weight looked up from the BMK tables at save time, not
    // something an agent collects or computes.
    'bmkWeight',
  },
};

String supabaseSnakeCase(String key) {
  final buffer = StringBuffer();
  for (var i = 0; i < key.length; i++) {
    final char = key[i];
    final isUpper = char.toUpperCase() == char && char.toLowerCase() != char;
    if (isUpper && i > 0) buffer.write('_');
    buffer.write(char.toLowerCase());
  }
  return buffer.toString();
}

Set<String> _measurementColumnNames(String table) {
  return PanelSampleSchema.byTable(table).measurementColumns
      .map((definition) => definition.trim().split(RegExp(r'\s+')).first)
      .toSet();
}

List<AgentStationSchema> get _chickSchemas => AgentStationRegistry.schemas
    .where((schema) => schema.schemaKey.startsWith('chicks.'))
    .toList(growable: false);

void main() {
  test('the chick schemas the rest of this suite relies on are present', () {
    expect(
      _chickSchemas.map((schema) => schema.schemaKey).toSet(),
      {
        'chicks.pasgar',
        'chicks.yfbm',
        'chicks.cvt',
        'chicks.postmortem',
        'chicks.culled_analysis',
        'chicks.weights',
      },
    );
  });

  for (final schema in _chickSchemas) {
    group(schema.schemaKey, () {
      test('persists into a real panel table', () {
        expect(schema.persistence, hasLength(1));
        final mapping = schema.persistence.single;
        // Does not throw only if the table is one PanelSampleSchema creates.
        PanelSampleSchema.byTable(mapping.localTable);
        expect(mapping.remoteTable, mapping.localTable);
      });

      test('every mapped column exists on that panel table', () {
        final table = schema.persistence.single.localTable;
        final columns = {
          ..._measurementColumnNames(table),
          ..._panelCommonColumns,
        };

        for (final field in schema.fields) {
          expect(
            columns,
            contains(field.persistence['localColumn']),
            reason: 'field ${field.fieldKey} of ${schema.schemaKey}',
          );
        }
        for (final calculation in schema.calculations) {
          expect(
            columns,
            contains(calculation.persistence['localColumn']),
            reason: 'calculation ${calculation.fieldKey} of '
                '${schema.schemaKey}',
          );
        }
      });

      test('remote columns are the snake_case of the local ones', () {
        for (final field in schema.fields) {
          expect(
            field.persistence['remoteColumn'],
            supabaseSnakeCase(field.persistence['localColumn']! as String),
            reason: 'field ${field.fieldKey} of ${schema.schemaKey}',
          );
        }
        for (final calculation in schema.calculations) {
          expect(
            calculation.persistence['remoteColumn'],
            supabaseSnakeCase(
              calculation.persistence['localColumn']! as String,
            ),
            reason: 'calculation ${calculation.fieldKey} of '
                '${schema.schemaKey}',
          );
        }
      });

      test('allowed layers match the panel definition', () {
        final panel = PanelSampleSchema.byTable(
          schema.persistence.single.localTable,
        );
        expect(
          schema.allowedLayers,
          panel.allowedLayers.map((layer) => layer.dbValue).toList(),
        );
      });
    });
  }

  for (final table in _unclaimedColumns.keys) {
    test('$table columns are each claimed by at most one registry entry', () {
      final claims = <String, List<String>>{};
      for (final schema in _chickSchemas) {
        if (schema.persistence.single.localTable != table) continue;
        for (final field in schema.fields) {
          (claims[field.persistence['localColumn']! as String] ??= [])
              .add('${schema.schemaKey}.${field.fieldKey}');
        }
        for (final calculation in schema.calculations) {
          (claims[calculation.persistence['localColumn']! as String] ??= [])
              .add('${schema.schemaKey}.${calculation.fieldKey}');
        }
      }

      final doubleClaimed = Map.of(claims)
        ..removeWhere((_, owners) => owners.length == 1);
      expect(doubleClaimed, isEmpty, reason: 'two schemas writing one column');

      expect(
        _measurementColumnNames(table).difference(claims.keys.toSet()),
        _unclaimedColumns[table],
        reason: 'unclaimed columns changed — update the allowlist knowingly',
      );
    });
  }
}
