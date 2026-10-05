import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/customer_model.dart';
import 'package:hatchaudit/data/models/flock_model.dart';
import 'package:hatchaudit/data/models/hatchery_model.dart';

void main() {
  group('reference sampling codes', () {
    test('customer code round-trips through model maps', () {
      final customer = CustomerModel(
        id: 'customer-1',
        name: 'Customer',
        samplingCode: 'org',
        createdAt: DateTime(2026),
        createdBy: 'tester',
      );

      expect(customer.samplingCode, 'ORG');
      expect(CustomerModel.fromMap(customer.toMap()).samplingCode, 'ORG');
    });

    test('hatchery and farm codes round-trip without changing ids', () {
      final hatchery = HatcheryModel(
        id: 'hatchery-1',
        customerId: 'customer-1',
        name: 'Hatchery',
        samplingCode: 'hat',
        createdAt: DateTime(2026),
        createdBy: 'tester',
      );
      final flock = FlockModel(
        id: 'flock-1',
        customerId: 'customer-1',
        flockId: 'F-1',
        breed: 'Ross308',
        samplingCode: 'frm',
        entryDate: DateTime(2026),
      );

      expect(HatcheryModel.fromMap(hatchery.toMap()).samplingCode, 'HAT');
      expect(FlockModel.fromMap(flock.toMap()).samplingCode, 'FRM');
      expect(hatchery.id, 'hatchery-1');
      expect(flock.id, 'flock-1');
    });

    test(
      'missing legacy codes remain null and invalid nonempty codes fail',
      () {
        expect(
          CustomerModel.fromMap({'id': 'old', 'name': 'Legacy'}).samplingCode,
          isNull,
        );
        expect(
          () => CustomerModel(
            id: 'bad',
            name: 'Invalid',
            samplingCode: 'A1',
            createdAt: DateTime(2026),
            createdBy: 'tester',
          ),
          throwsArgumentError,
        );
      },
    );
  });
}
