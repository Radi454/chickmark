import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/auth/customer_account_identifier.dart';

void main() {
  test('maps a customer username to its Supabase login email', () {
    expect(
      CustomerAccountIdentifier.loginEmail(' Ghareeb '),
      'ghareeb@customers.chickmark.app',
    );
  });

  test('normalizes a staff email without remapping it', () {
    expect(
      CustomerAccountIdentifier.loginEmail(' Admin@Example.COM '),
      'admin@example.com',
    );
  });

  test('validates supported customer usernames', () {
    expect(CustomerAccountIdentifier.validateUsername('ghareeb'), isNull);
    expect(CustomerAccountIdentifier.validateUsername('g'), isNotNull);
    expect(CustomerAccountIdentifier.validateUsername('غريب'), isNotNull);
    expect(CustomerAccountIdentifier.validateUsername('has space'), isNotNull);
  });

  test('turns a synthetic customer email back into a display username', () {
    expect(
      CustomerAccountIdentifier.displayIdentifier(
        'ghareeb@customers.chickmark.app',
      ),
      'ghareeb',
    );
  });
}
