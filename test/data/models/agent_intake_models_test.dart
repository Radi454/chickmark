import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/agent_intake_models.dart';

void main() {
  test('session round-trips structured JSON and known enum values', () {
    final session = AgentIntakeSession.fromMap({
      'id': 'intake-1',
      'staffLinkId': 'staff-1',
      'telegramChatId': 'chat-1',
      'schemaKey': 'chicks.pasgar',
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
      'scope': 'setter_hatcher',
      'setterIdentity': 'S-14',
      'hatcherIdentity': 'H-08',
      'workingValuesJson': jsonEncode(_values),
      'pendingClarificationJson': null,
      'summaryVersion': 2,
      'summarySnapshotJson': jsonEncode({
        'version': 2,
        'values': _values,
        'generatedAt': '2026-07-28T10:00:00.000Z',
      }),
      'userConfirmedAt': '2026-07-28T10:01:00.000Z',
      'approvedSessionId': null,
      'approvedPanelRowId': null,
      'reviewedBy': null,
      'reviewedAt': null,
      'rejectionReason': null,
      'createdAt': '2026-07-28T09:55:00.000Z',
      'updatedAt': '2026-07-28T10:01:00.000Z',
    });

    expect(session.state, AgentIntakeState.awaitingAdminReview);
    expect(session.language, AgentIntakeLanguage.mixed);
    expect(session.scope, AgentIntakeScope.setterHatcher);
    expect(session.workingValues['pasgarNavelCount'], 1);
    expect(session.summary!.score, 9.8);
    expect(session.summary!.percentageFor('pasgarLegCount'), 5);
    expect(session.toMap()['workingValuesJson'], jsonEncode(_values));
    expect(
      () => session.workingValues['pasgarNavelCount'] = 9,
      throwsUnsupportedError,
    );
  });

  test('detail graph owns immutable values and conversation turns', () {
    final session = AgentIntakeSession.fromMap(_minimalSessionMap);
    final details = AgentIntakeDetails(
      session: session,
      values: [
        AgentIntakeValue.fromMap({
          'id': 'value-1',
          'intakeSessionId': 'intake-1',
          'fieldKey': 'pasgarSampleSize',
          'valueJson': '40',
          'sourcePhrase': 'sample 40',
          'confidence': 0.99,
          'createdAt': '2026-07-28T10:00:00.000Z',
          'updatedAt': '2026-07-28T10:00:00.000Z',
        }),
      ],
      turns: [
        AgentIntakeTurn.fromMap({
          'id': 'turn-1',
          'intakeSessionId': 'intake-1',
          'direction': 'inbound',
          'telegramUpdateId': 'update-1',
          'telegramMessageId': 'message-1',
          'text': 'sample 40',
          'language': 'en',
          'intent': 'provide_data',
          'createdAt': '2026-07-28T10:00:00.000Z',
        }),
      ],
    );

    expect(details.valueFor('pasgarSampleSize')!.intValue, 40);
    expect(details.turns.single.direction, AgentIntakeTurnDirection.inbound);
    expect(() => details.values.clear(), throwsUnsupportedError);
    expect(() => details.turns.clear(), throwsUnsupportedError);
  });

  test('supports non-Pasgar values, calculations, and station scopes', () {
    final session = AgentIntakeSession.fromMap({
      ..._minimalSessionMap,
      'schemaKey': 'chicks.weights',
      'scope': 'house',
      'workingValuesJson': jsonEncode({
        'weightsJson': [39.5, 40, 41.25],
      }),
      'summaryVersion': 3,
      'summarySnapshotJson': jsonEncode({
        'version': 3,
        'schemaKey': 'chicks.weights',
        'schemaVersion': 1,
        'values': {
          'weightsJson': [39.5, 40, 41.25],
        },
        'calculations': {
          'sampleSize': 3,
          'avgWeight': 40.25,
          'uniformityPct': 100.0,
          'cvPct': 1.8,
        },
        'generatedAt': '2026-07-28T10:00:00.000Z',
      }),
    });

    expect(session.scope, AgentIntakeScope.house);
    expect(session.workingValues['weightsJson'], [39.5, 40, 41.25]);
    expect(session.summary!.schemaKey, 'chicks.weights');
    expect(session.summary!.schemaVersion, 1);
    expect(session.summary!.values['weightsJson'], [39.5, 40, 41.25]);
    expect(session.summary!.calculations['avgWeight'], 40.25);
    expect(
      () => (session.workingValues['weightsJson']! as List<Object?>).add(42),
      throwsUnsupportedError,
    );
    expect(
      () => session.summary!.calculations['avgWeight'] = 99,
      throwsUnsupportedError,
    );
  });
}

const _values = <String, int>{
  'pasgarSampleSize': 40,
  'pasgarReflexesCount': 2,
  'pasgarBeakCount': 1,
  'pasgarNavelCount': 1,
  'pasgarBellyCount': 1,
  'pasgarLegCount': 2,
  'pasgarFeatherDevCount': 3,
};

final _minimalSessionMap = <String, Object?>{
  'id': 'intake-1',
  'staffLinkId': 'staff-1',
  'telegramChatId': 'chat-1',
  'schemaKey': 'chicks.pasgar',
  'schemaVersion': 1,
  'state': 'collecting',
  'language': 'en',
  'auditDate': '2026-07-28',
  'workingValuesJson': '{}',
  'summaryVersion': 0,
  'createdAt': '2026-07-28T09:55:00.000Z',
  'updatedAt': '2026-07-28T10:01:00.000Z',
};
