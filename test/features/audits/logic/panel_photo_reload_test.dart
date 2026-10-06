import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/features/audits/logic/egg_station_reconstruction.dart';
import 'package:hatchaudit/features/audits/logic/panel_photo_identity.dart';
import 'package:hatchaudit/features/audits/screens/audit_context_screen.dart';

void main() {
  test('sanitized direct and managed panel photo fields hydrate by row id', () {
    const rowId = 'session-1:chick_quality:sample-1';
    final panelRows = <String, List<Map<String, dynamic>>>{
      'chick_quality': [
        {
          'id': rowId,
          'sessionId': 'session-1',
          'customerId': 'customer-1',
          'date': '2026-08-23',
          'sampleIndex': 1,
          'createdAt': '2026-08-23T08:00:00.000',
          'updatedAt': '2026-08-23T08:00:00.000',
          'cvtTopPhoto': null,
        },
      ],
      'chick_weights': const [],
    };
    final hydratedRows = hydratePanelPhotoRows(panelRows, [
      PhotoModel(
        id: 'photo-cvt',
        filePath: 'supabase://photos/session-1/chick_quality/$rowId/photo.jpg',
        createdAt: DateTime(2026, 8, 23, 10),
        sessionId: 'session-1',
        panelName: 'chick_quality',
        panelRowId: rowId,
        fieldKey: 'cvtTopPhoto',
      ),
    ]);
    final reconstruction = reconstructStation(
      stationKey: 'chicks',
      sessionId: 'session-1',
      context: AuditContextData(
        auditType: 'Chicks',
        customerId: 'customer-1',
        flockId: 'flock-1',
        date: '2026-08-23',
      ),
      rowsByPanel: hydratedRows,
    );

    expect(
      hydratedRows['chick_quality']!.single['cvtTopPhoto'],
      startsWith('supabase://'),
    );
    expect(
      reconstruction.stationAudits.single.cvtTopPhoto,
      startsWith('supabase://'),
    );
    expect(
      reconstruction
          .samplingDraftsByPanel['chick_quality']![rowId]!
          .cvtTopPhoto,
      startsWith('supabase://'),
    );
    expect(panelRows['chick_quality']!.single['cvtTopPhoto'], isNull);
  });

  test('setter turning-angle and EST collection photo keys rehydrate', () {
    const rowId = 'session-2:setter_optimizing:sample-2';
    final rows = hydratePanelPhotoRows(
      {
        'setter_optimizing': [
          {
            'id': rowId,
            'sessionId': 'session-2',
            'machineScreenPhoto': null,
            'estPhotosJson': '{"front_top":null}',
          },
        ],
      },
      [
        PhotoModel(
          id: 'machine-screen',
          filePath: 'supabase://photos/machine-screen.jpg',
          createdAt: DateTime(2026, 8, 23, 9),
          sessionId: 'session-2',
          panelName: 'setter_optimizing',
          panelRowId: rowId,
          fieldKey: 'turning_angle',
        ),
        PhotoModel(
          id: 'est-front-top',
          filePath: 'supabase://photos/front-top.jpg',
          createdAt: DateTime(2026, 8, 23, 10),
          sessionId: 'session-2',
          panelName: 'setter_optimizing',
          panelRowId: rowId,
          fieldKey: 'setter_est_front_top',
        ),
      ],
    );
    final row = rows['setter_optimizing']!.single;

    expect(row['machineScreenPhoto'], 'supabase://photos/machine-screen.jpg');
    expect(jsonDecode(row['estPhotosJson'] as String), {
      'front_top': 'supabase://photos/front-top.jpg',
    });
  });

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
