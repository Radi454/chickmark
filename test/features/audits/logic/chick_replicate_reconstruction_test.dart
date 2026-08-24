import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';

void main() {
  test('reconstructs every same-scope Chick replicate by persisted id', () {
    final reconstruction = reconstructStation(
      stationKey: 'chicks',
      sessionId: 'session-1',
      context: AuditContextData(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-08-24',
      ),
      rowsByPanel: {
        'chick_quality': [
          _row('quality-1', 'chicks.legacy_combined', 1),
          _row('quality-2', 'chicks.legacy_combined', 2),
        ],
        'chick_weights': [
          _row('weight-1', 'chicks.weights', 1),
          _row('weight-2', 'chicks.weights', 2),
        ],
      },
    );

    expect(reconstruction.stationAudits.map((draft) => draft.id), [
      'quality-1',
      'quality-2',
    ]);
    expect(reconstruction.stationSamples.map((sample) => sample.id), [
      'quality-1',
      'quality-2',
      'weight-1',
      'weight-2',
    ]);
    expect(
      reconstruction.stationSamples.map((sample) => sample.legacyAuditId),
      ['quality-1', 'quality-2', null, null],
    );
    expect(reconstruction.stationSamples.map((sample) => sample.sampleKey), [
      'key-quality-1',
      'key-quality-2',
      'key-weight-1',
      'key-weight-2',
    ]);
  });
}

Map<String, dynamic> _row(String id, String domain, int replicate) => {
  'id': id,
  'sessionId': 'session-1',
  'customerId': 'customer-1',
  'flockId': 'flock-1',
  'date': '2026-08-24',
  'house': 'House A',
  'scopeType': 'house',
  'scopeKey': '{"house":"House A"}',
  'domain': domain,
  'replicate': replicate,
  'sampleKey': 'key-$id',
  'sampleIndex': replicate,
  'sampleMode': 'comparison',
  'createdAt': '2026-08-24T00:00:0${replicate}Z',
  'updatedAt': '2026-08-24T00:00:0${replicate}Z',
};
