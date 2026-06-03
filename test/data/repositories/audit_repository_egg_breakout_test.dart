import 'package:flutter_test/flutter_test.dart';

import 'package:hatchaudit/data/repositories/audit_repository.dart';
import 'package:hatchaudit/features/dashboard/models/dashboard_filter.dart';

void main() {
  test(
    'legacy egg breakout dashboard queries are disabled after panel cutover',
    () async {
      final repository = AuditRepository();

      expect(
        await repository.getEggBreakoutAvg(
          DashboardFilter(),
          'residueHatchDay',
        ),
        isNull,
      );
      expect(
        await repository.getEggBreakoutTrend(
          DashboardFilter(),
          'residueHatchDay',
        ),
        isNull,
      );
    },
  );
}
