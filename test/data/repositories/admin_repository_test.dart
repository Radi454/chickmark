import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/repositories/admin_repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _MockSupabaseClient extends Mock implements SupabaseClient {}

class _MockFunctionsClient extends Mock implements FunctionsClient {}

void main() {
  late _MockSupabaseClient client;
  late _MockFunctionsClient functions;

  setUp(() {
    client = _MockSupabaseClient();
    functions = _MockFunctionsClient();
    when(() => client.functions).thenReturn(functions);
  });

  test(
    'creates a customer profile through the privileged Edge Function',
    () async {
      when(
        () => functions.invoke(
          'create-customer-account',
          body: any(named: 'body'),
        ),
      ).thenAnswer(
        (_) async => FunctionResponse(
          status: 201,
          data: {
            'profile': {
              'id': 'user-1',
              'email': 'ghareeb@customers.chickmark.app',
              'username': 'ghareeb',
              'full_name': 'Ghareeb',
              'role': 'customer',
              'status': 'approved',
              'customer_id': 'customer-1',
            },
          },
        ),
      );

      final profile = await AdminRepository(client: client)
          .createCustomerAccount(
            fullName: 'Ghareeb',
            username: 'ghareeb',
            password: 'Ghareeb#12345',
            customerId: 'customer-1',
          );

      expect(profile.username, 'ghareeb');
      expect(profile.role, 'customer');
      expect(profile.status, 'approved');
      expect(profile.customerId, 'customer-1');
      final body =
          verify(
                () => functions.invoke(
                  'create-customer-account',
                  body: captureAny(named: 'body'),
                ),
              ).captured.single
              as Map<String, dynamic>;
      expect(body['password'], 'Ghareeb#12345');
      expect(body['customerId'], 'customer-1');
    },
  );

  test('surfaces a friendly Edge Function account error', () async {
    when(
      () =>
          functions.invoke('create-customer-account', body: any(named: 'body')),
    ).thenThrow(
      const FunctionException(
        status: 409,
        details: {'error': 'That username is already in use.'},
      ),
    );

    expect(
      () => AdminRepository(client: client).createCustomerAccount(
        fullName: 'Ghareeb',
        username: 'ghareeb',
        password: 'Ghareeb#12345',
        customerId: 'customer-1',
      ),
      throwsA(
        isA<AdminAccountException>().having(
          (error) => error.message,
          'message',
          'That username is already in use.',
        ),
      ),
    );
  });

  test('wraps connectivity failures in an admin account error', () async {
    when(
      () =>
          functions.invoke('create-customer-account', body: any(named: 'body')),
    ).thenThrow(StateError('socket closed'));

    expect(
      () => AdminRepository(client: client).createCustomerAccount(
        fullName: 'Ghareeb',
        username: 'ghareeb',
        password: 'Ghareeb#12345',
        customerId: 'customer-1',
      ),
      throwsA(
        isA<AdminAccountException>().having(
          (error) => error.message,
          'message',
          contains('Check your connection'),
        ),
      ),
    );
  });

  test('resets a customer password through the admin Edge Function', () async {
    when(
      () =>
          functions.invoke('reset-customer-password', body: any(named: 'body')),
    ).thenAnswer(
      (_) async => FunctionResponse(status: 200, data: {'success': true}),
    );

    await AdminRepository(
      client: client,
    ).resetCustomerPassword(userId: 'user-1', password: 'NewGhareeb#123');

    final body =
        verify(
              () => functions.invoke(
                'reset-customer-password',
                body: captureAny(named: 'body'),
              ),
            ).captured.single
            as Map<String, dynamic>;
    expect(body['userId'], 'user-1');
    expect(body['password'], 'NewGhareeb#123');
  });
}
