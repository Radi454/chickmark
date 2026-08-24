import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/features/audits/logic/panel_photo_identity.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';

void main() {
  test(
    'a panel photo still resolves after station reload regenerates draft id',
    () {
      const sessionId = 'session-1';
      const rowId = 'session-1:chick_quality:original-draft:sample-1';
      final reconstruction = reconstructStation(
        stationKey: 'chicks',
        sessionId: sessionId,
        context: AuditContextData(
          auditType: 'Chicks',
          customerId: 'customer-1',
          flockId: 'flock-1',
          date: '2026-08-23',
        ),
        rowsByPanel: {
          'chick_quality': [
            {
              'id': rowId,
              'sessionId': sessionId,
              'customerId': 'customer-1',
              'date': '2026-08-23',
              'sampleIndex': 1,
              'createdAt': '2026-08-23T08:00:00.000',
              'updatedAt': '2026-08-23T08:00:00.000',
            },
          ],
          'chick_weights': const [],
        },
      );

      final reloadedDraft = reconstruction.stationAudits.single;
      final reloadedSample = reconstruction.stationSamples.single;
      expect(reloadedDraft.id, isNot('original-draft'));
      expect(reloadedSample.id, rowId);
      expect(
        panelRowIdForPhoto(
          sessionId: sessionId,
          panelName: 'chick_quality',
          draftId: reloadedDraft.id,
          stationSampleId: reloadedSample.id,
        ),
        rowId,
      );

      final hydrated = overlayPanelPhotos(reconstruction, [
        PhotoModel(
          id: 'photo-1',
          filePath: '/tmp/pasgar-beak.jpg',
          createdAt: DateTime(2026, 8, 23, 9),
          sessionId: sessionId,
          panelName: 'chick_quality',
          panelRowId: rowId,
          fieldKey: 'pasgarBeakPhoto',
        ),
      ]);

      expect(
        hydrated.stationAudits.single.pasgarBeakPhoto,
        '/tmp/pasgar-beak.jpg',
      );
    },
  );
}
