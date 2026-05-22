import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';

void main() {
  test(
    'legacy Pasgar dashboard repository is disabled after panel cutover',
    () async {
      final repository = AuditRepository();

      expect(await repository.getPasgarAvg(DashboardFilter()), isNull);
    },
  );
}
