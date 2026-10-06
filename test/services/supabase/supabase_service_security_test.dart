import 'dart:convert';
import 'dart:typed_data';

import 'package:hatchaudit/data/models/photo_model.dart';
import 'package:hatchaudit/services/photo/photo_data_uri.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

void main() {
  test('photo metadata acknowledgement requires the requested remote row', () {
    expect(photoMetadataUpdateAcknowledged(const [], 'photo-1'), isFalse);
    expect(
      photoMetadataUpdateAcknowledged(const [
        {'id': 'another-photo'},
      ], 'photo-1'),
      isFalse,
    );
    expect(
      photoMetadataUpdateAcknowledged(const [
        {'id': 'photo-1'},
      ], 'photo-1'),
      isTrue,
    );
  });

  test('Chick V2 identity and provenance map to cloud snake_case', () {
    final payload = toSupabaseUpsertPayload('chick_weights', {
      'sampleKey': 'key-1',
      'scopeKey': '{"house":"H1"}',
      'schemaVersion': 1,
      'captureMethod': 'manual',
      'createdBy': 'user-1',
      'deviceId': 'device-1',
      'sourceRefId': 'ref-1',
      'observedAt': '2026-08-24T00:00:00Z',
      'qualityStatus': 'WARN',
      'qualityFlags': '[{"tier":"WARN","code":"item_out_of_range"}]',
      'dirtyAt': 'device-only',
    });

    expect(payload, {
      'sample_key': 'key-1',
      'scope_key': '{"house":"H1"}',
      'schema_version': 1,
      'capture_method': 'manual',
      'created_by': 'user-1',
      'device_id': 'device-1',
      'source_ref_id': 'ref-1',
      'observed_at': '2026-08-24T00:00:00Z',
      'quality_status': 'WARN',
      'quality_flags': '[{"tier":"WARN","code":"item_out_of_range"}]',
    });
  });

  test('hatchery machine catalog fields map to cloud snake_case', () {
    final payload = toSupabaseUpsertPayload('hatchery_machines', {
      'id': 'machine-1',
      'hatcheryId': 'hatchery-1',
      'kind': 'setter',
      'code': 'S-01',
      'name': 'Setter 1',
      'batchSize': 120000,
      'trolleyCapacity': 120,
      'traySize': 150,
      'trolleyCount': 80,
      'traysPerTrolley': 100,
      'createdAt': '2026-10-05T00:00:00Z',
      'updatedAt': '2026-10-05T00:00:00Z',
      'createdBy': 'user-1',
      'syncStatus': 'pending',
      'dirtyAt': 'device-only',
    });

    expect(payload, {
      'id': 'machine-1',
      'hatchery_id': 'hatchery-1',
      'kind': 'setter',
      'code': 'S-01',
      'name': 'Setter 1',
      'batch_size': 120000,
      'trolley_capacity': 120,
      'tray_size': 150,
      'trolley_count': 80,
      'trays_per_trolley': 100,
      'created_at': '2026-10-05T00:00:00Z',
      'updated_at': '2026-10-05T00:00:00Z',
      'created_by': 'user-1',
    });
  });

  test(
    'upsert payload strips local sync metadata before snake case conversion',
    () {
      final payload = toSupabaseUpsertPayload('flocks', {
        'id': 'flock-1',
        'customerId': 'customer-1',
        'flockId': 'F-1',
        'depletionAgeWeeks': 65,
        'updatedAt': '2026-07-28T00:24:00Z',
        'syncStatus': 'pending',
        'dirtyAt': '2026-07-28T00:24:01Z',
        'lastSyncedAt': null,
        'syncError': 'previous failure',
      });

      expect(payload, {
        'id': 'flock-1',
        'customer_id': 'customer-1',
        'flock_id': 'F-1',
        'depletion_age_weeks': 65,
        'updated_at': '2026-07-28T00:24:00Z',
      });
    },
  );

  test('hatchery upsert payload omits legacy updated timestamp columns', () {
    final payload = toSupabaseUpsertPayload('hatcheries', {
      'id': 'hatchery-1',
      'customerId': 'customer-1',
      'name': 'QA Hatchery',
      'samplingCode': 'QAH',
      'createdAt': '2026-10-06T00:00:00Z',
      'createdBy': 'user-1',
      'updatedAt': 'legacy-camel-timestamp',
      'updated_at': 'legacy-snake-timestamp',
      'syncStatus': 'pending',
      'dirtyAt': 'device-only',
    });

    expect(payload, {
      'id': 'hatchery-1',
      'customer_id': 'customer-1',
      'name': 'QA Hatchery',
      'sampling_code': 'QAH',
      'created_at': '2026-10-06T00:00:00Z',
      'created_by': 'user-1',
    });
  });

  test(
    'refreshAvailability waits for Supabase initialization readiness',
    () async {
      var initializerCalled = false;
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async {
          initializerCalled = true;
          return false;
        },
      );

      final available = await service.refreshAvailability();

      expect(initializerCalled, isTrue);
      expect(available, isFalse);
    },
  );

  test(
    'refreshAvailability reloads config before declaring cloud unconfigured',
    () async {
      var configured = false;
      var reloadCalled = false;
      var initializerCalled = false;
      final service = SupabaseService(
        isConfiguredForTesting: () => configured,
        reloadConfigForTesting: () async {
          reloadCalled = true;
          configured = true;
        },
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async {
          initializerCalled = true;
          return true;
        },
      );

      final available = await service.refreshAvailability();

      expect(reloadCalled, isTrue);
      expect(initializerCalled, isTrue);
      expect(available, isTrue);
    },
  );

  test(
    'remote operations do not read client before initialization succeeds',
    () async {
      var clientRead = false;
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async => false,
        clientForTesting: () {
          clientRead = true;
          throw StateError('client should not be read before initialization');
        },
      );

      final sent = await service.sendPasswordReset('test@example.com');

      expect(sent, isFalse);
      expect(clientRead, isFalse);
    },
  );

  test(
    'photo delete preserves a storage object referenced by a survivor',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/photos' &&
              request.method == 'GET') {
            final isTarget =
                request.url.queryParameters['select'] == 'file_path';
            return http.Response(
              jsonEncode(
                isTarget
                    ? [
                        {'file_path': 'supabase://photos/shared/object.jpg'},
                      ]
                    : [
                        {
                          'id': 'survivor-photo',
                          'file_path':
                              'http://localhost:54321/storage/v1/object/public/photos/shared/object.jpg',
                        },
                      ],
              ),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async => true,
        clientForTesting: () => client,
      );

      await service.deleteRows('photos', ['delete-photo']);

      expect(
        requests.where((request) => request.url.path.startsWith('/storage/')),
        isEmpty,
      );
      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/photos' &&
              request.method == 'DELETE',
        ),
        hasLength(1),
      );
    },
  );

  test(
    'photo delete removes an unshared object before deleting metadata',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/photos' &&
              request.method == 'GET') {
            if (request.url.queryParameters['select'] == 'file_path') {
              return http.Response(
                jsonEncode([
                  {'file_path': 'supabase://photos/unshared/object.jpg'},
                ]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return http.Response(
              '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async => true,
        clientForTesting: () => client,
      );

      await service.deleteRows('photos', ['delete-photo']);

      final storageDelete = requests.indexWhere(
        (request) => request.url.path.startsWith('/storage/'),
      );
      final metadataDelete = requests.indexWhere(
        (request) =>
            request.url.path == '/rest/v1/photos' && request.method == 'DELETE',
      );
      expect(storageDelete, greaterThanOrEqualTo(0));
      expect(metadataDelete, greaterThan(storageDelete));
      expect(requests[storageDelete].method, 'DELETE');
    },
  );

  test('photo survivor on a later page preserves its backing object', () async {
    final requests = <http.Request>[];
    var survivorPage = 0;
    final client = SupabaseClient(
      'http://localhost:54321',
      'test-key',
      httpClient: MockClient((request) async {
        requests.add(request);
        if (request.url.path == '/rest/v1/photos' && request.method == 'GET') {
          if (request.url.queryParameters['select'] == 'file_path') {
            return http.Response(
              jsonEncode([
                {'file_path': 'supabase://photos/shared/later-page.jpg'},
              ]),
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }
          survivorPage++;
          final rows = survivorPage == 1
              ? List.generate(
                  500,
                  (index) => {
                    'id': 'page-one-$index',
                    'file_path': 'supabase://photos/other/$index.jpg',
                  },
                )
              : [
                  {
                    'id': 'late-survivor',
                    'file_path':
                        'http://localhost:54321/storage/v1/object/public/photos/shared/later-page.jpg',
                  },
                ];
          return http.Response(
            jsonEncode(rows),
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }
        return http.Response(
          '[]',
          200,
          headers: {'content-type': 'application/json'},
          request: request,
        );
      }),
    );
    final service = SupabaseService(
      isConfiguredForTesting: () => true,
      checkNetworkAvailableForTesting: () async => true,
      initializeSupabaseForTesting: () async => true,
      clientForTesting: () => client,
    );

    await service.deleteRows('photos', ['delete-photo']);

    expect(survivorPage, 2);
    expect(
      requests.where((request) => request.url.path.startsWith('/storage/')),
      isEmpty,
    );
    expect(
      requests.where(
        (request) =>
            request.url.path == '/rest/v1/photos' && request.method == 'DELETE',
      ),
      hasLength(1),
    );
  });

  test(
    'photo survivor lookup failure keeps metadata deletion retryable',
    () async {
      final requests = <http.Request>[];
      final client = SupabaseClient(
        'http://localhost:54321',
        'test-key',
        httpClient: MockClient((request) async {
          requests.add(request);
          if (request.url.path == '/rest/v1/photos' &&
              request.method == 'GET') {
            if (request.url.queryParameters['select'] == 'file_path') {
              return http.Response(
                jsonEncode([
                  {'file_path': 'supabase://photos/shared/object.jpg'},
                ]),
                200,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return http.Response('lookup failed', 500, request: request);
          }
          return http.Response(
            '[]',
            200,
            headers: {'content-type': 'application/json'},
            request: request,
          );
        }),
      );
      final service = SupabaseService(
        isConfiguredForTesting: () => true,
        checkNetworkAvailableForTesting: () async => true,
        initializeSupabaseForTesting: () async => true,
        clientForTesting: () => client,
      );

      await expectLater(
        service.deleteRows('photos', ['delete-photo']),
        throwsA(anything),
      );

      expect(
        requests.where(
          (request) =>
              request.url.path == '/rest/v1/photos' &&
              request.method == 'DELETE',
        ),
        isEmpty,
      );
      expect(
        requests.where((request) => request.url.path.startsWith('/storage/')),
        isEmpty,
      );
    },
  );

  for (final observationId in <String?>[null, 'observation-1']) {
    test(
      'photo upload sends only populated observation association $observationId',
      () async {
        Map<String, dynamic>? metadata;
        final client = SupabaseClient(
          'http://localhost:54321',
          'test-key',
          httpClient: MockClient((request) async {
            if (request.url.path == '/rest/v1/photos') {
              metadata = jsonDecode(request.body) as Map<String, dynamic>;
            }
            return http.Response(
              request.url.path.startsWith('/storage/')
                  ? '{"Key":"photos/test.jpg"}'
                  : '[]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        final service = SupabaseService(
          isConfiguredForTesting: () => true,
          checkNetworkAvailableForTesting: () async => true,
          initializeSupabaseForTesting: () async => true,
          clientForTesting: () => client,
        );
        await service.uploadPhoto(
          PhotoModel(
            id: 'photo-1',
            filePath: encodePhotoDataUri(Uint8List.fromList([1, 2, 3])),
            createdAt: DateTime(2026, 10, 6),
            sessionId: 'session-1',
            panelName: 'setter_optimizing',
            panelRowId: 'row-1',
            fieldKey: 'turning_angle',
            observationId: observationId,
          ),
        );
        expect(metadata, isNotNull);
        expect(metadata!.containsKey('observation_id'), observationId != null);
        if (observationId != null) {
          expect(metadata!['observation_id'], observationId);
        }
        expect(metadata!['file_path'], startsWith('supabase://photos/'));
      },
    );
  }
  for (final scenario in ['modern', 'legacy-null', 'legacy-linked']) {
    test(
      'photo metadata update preserves association semantics: $scenario',
      () async {
        final updates = <Map<String, dynamic>>[];
        final client = SupabaseClient(
          'http://localhost:54321',
          'test-key',
          httpClient: MockClient((request) async {
            final update = jsonDecode(request.body) as Map<String, dynamic>;
            updates.add(update);
            if (scenario != 'modern' && update.containsKey('observation_id')) {
              return http.Response(
                jsonEncode({
                  'code': 'PGRST204',
                  'message':
                      "Could not find the 'observation_id' column of 'photos' in the schema cache",
                }),
                400,
                headers: {'content-type': 'application/json'},
                request: request,
              );
            }
            return http.Response(
              '[{"id":"photo-1"}]',
              200,
              headers: {'content-type': 'application/json'},
              request: request,
            );
          }),
        );
        final service = SupabaseService(
          isConfiguredForTesting: () => true,
          checkNetworkAvailableForTesting: () async => true,
          initializeSupabaseForTesting: () async => true,
          clientForTesting: () => client,
        );
        final photo = PhotoModel(
          id: 'photo-1',
          filePath: 'supabase://photos/test.jpg',
          createdAt: DateTime(2026, 10, 6),
          sessionId: 'session-1',
          panelName: 'setter_optimizing',
          panelRowId: 'row-1',
          fieldKey: 'turning_angle',
          observationId: scenario == 'legacy-linked' ? 'observation-1' : null,
        );
        if (scenario == 'legacy-linked') {
          await expectLater(
            service.upsertPhotoMetadata(photo),
            throwsA(isA<PostgrestException>()),
          );
          expect(updates, hasLength(1));
          expect(updates.single['observation_id'], 'observation-1');
        } else {
          await service.upsertPhotoMetadata(photo);
          expect(updates.first.containsKey('observation_id'), isTrue);
          expect(updates.first['observation_id'], isNull);
          expect(updates, hasLength(scenario == 'modern' ? 1 : 2));
          if (scenario == 'legacy-null') {
            expect(updates.last.containsKey('observation_id'), isFalse);
            expect(updates.last['panel_row_id'], 'row-1');
          }
        }
      },
    );
  }
}
