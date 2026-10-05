import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';

void main() {
  test('reopen keeps immutable sample id separate from the row id', () {
    final reopened = reconstructStation(
      stationKey: 'egg',
      sessionId: 'session-1',
      context: AuditContextData(
        auditType: 'Egg',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-10-05',
      ),
      rowsByPanel: {
        'egg_quality': [
          {
            'id': 'session-1:egg_quality:draft:row-1',
            'sampleId': 'leaf-1',
            'sampleNumber': 8,
            'samplingPathJson': '{"sampleId":"leaf-1","sampleNumber":8}',
            'sessionId': 'session-1',
            'customerId': 'customer-1',
            'flockId': 'flock-1',
            'date': '2026-10-05',
            'sampleIndex': 1,
            'eggSampleSize': 12,
            'eggAvgWeight': 60.0,
          },
        ],
      },
    );

    expect(reopened.stationSamples.single.id, 'session-1:egg_quality:draft:row-1');
    expect(reopened.stationSamples.single.sampleId, 'leaf-1');
    expect(reopened.stationAudits.single.esEggSampleSize, 12);
    expect(
      reopened.samplingDraftsByPanel['egg_quality']!['leaf-1']!.esEggSampleSize,
      12,
    );
  });
}
