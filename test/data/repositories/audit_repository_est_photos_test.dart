import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';

void main() {
  test('extractEstPhotoPathsFromRows returns unique EST evidence paths', () {
    final paths = AuditRepository.extractEstPhotoPathsFromRows(
      [
        {
          'es_estPhotosJson':
              '{"front_top":"/tmp/front.jpg","middle_top":"/tmp/middle.jpg"}',
        },
        {
          'es_estPhotosJson':
              '{"back_top":"/tmp/front.jpg","back_middle":"","back_bottom":null}',
        },
        {'es_estPhotosJson': 'not-json'},
      ],
      existing: const ['/tmp/existing.jpg'],
    );

    expect(paths, ['/tmp/existing.jpg', '/tmp/front.jpg', '/tmp/middle.jpg']);
  });

  test(
    'legacy EST dashboard queries are disabled after panel cutover',
    () async {
      final repository = AuditRepository();

      expect(
        await repository.getLatestEggStorageEstEvidence(DashboardFilter()),
        isNull,
      );
      expect(await repository.getEggStorageTrend(DashboardFilter()), isNull);
    },
  );
}
