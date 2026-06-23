import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/data/models/user_model.dart';
import 'package:hatchaudit/data/repositories/activity_log_repository.dart';
import 'package:hatchaudit/data/repositories/user_repository.dart';
import 'package:hatchaudit/features/auth/providers/auth_provider.dart';
import 'package:hatchaudit/features/auth/screens/login_screen.dart';
import 'package:hatchaudit/services/supabase/supabase_service.dart';
import 'package:mocktail/mocktail.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockSupabaseService extends Mock implements SupabaseService {}

class _MockUserRepository extends Mock implements UserRepository {}

class _MockActivityLogRepository extends Mock
    implements ActivityLogRepository {}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    registerFallbackValue(_approvedUser('fallback@example.com'));
  });

  late _MockSupabaseService supabase;
  late _MockUserRepository userRepository;
  late _MockActivityLogRepository activityLogRepository;

  setUp(() {
    supabase = _MockSupabaseService();
    userRepository = _MockUserRepository();
    activityLogRepository = _MockActivityLogRepository();
    when(() => userRepository.upsertUser(any())).thenAnswer((_) async {});
    when(
      () => activityLogRepository.log(any(), any()),
    ).thenAnswer((_) async {});
  });

  Future<void> pumpLogin(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(430, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final authProvider = AuthProvider(
      userRepository: userRepository,
      activityLogRepository: activityLogRepository,
      supabaseService: supabase,
    );
    await tester.pumpWidget(
      ChangeNotifierProvider<AuthProvider>.value(
        value: authProvider,
        child: MaterialApp(
          routes: {
            '/startup-sync': (_) => const Scaffold(body: Text('Startup sync')),
          },
          home: const LoginScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  testWidgets('prefills saved email and checks Remember me', (tester) async {
    SharedPreferences.setMockInitialValues({
      'remember_me_email': 'saved@example.com',
    });

    await pumpLogin(tester);

    final emailField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    final rememberMe = tester.widget<Checkbox>(find.byType(Checkbox));

    expect(emailField.controller?.text, 'saved@example.com');
    expect(rememberMe.value, isTrue);
  });

  testWidgets('checked Remember me saves email and remembers session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    when(
      () => supabase.signIn(
        'auditor@example.com',
        'Test.12345',
        rememberSession: true,
      ),
    ).thenAnswer(
      (_) async =>
          AuthResult(success: true, user: _approvedUser('auditor@example.com')),
    );

    await pumpLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      'auditor@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Test.12345');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remember_me_email'), 'auditor@example.com');
    verify(
      () => supabase.signIn(
        'auditor@example.com',
        'Test.12345',
        rememberSession: true,
      ),
    ).called(1);
  });

  testWidgets('unchecked Remember me removes saved email and skips session', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'remember_me_email': 'saved@example.com',
    });
    when(
      () => supabase.signIn(
        'auditor@example.com',
        'Test.12345',
        rememberSession: false,
      ),
    ).thenAnswer(
      (_) async =>
          AuthResult(success: true, user: _approvedUser('auditor@example.com')),
    );

    await pumpLogin(tester);
    await tester.enterText(
      find.byType(TextFormField).first,
      'auditor@example.com',
    );
    await tester.enterText(find.byType(TextFormField).at(1), 'Test.12345');
    await tester.ensureVisible(find.byType(Checkbox));
    await tester.tap(find.byType(Checkbox));
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.tap(find.widgetWithText(ElevatedButton, 'Sign In'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('remember_me_email'), isNull);
    verify(
      () => supabase.signIn(
        'auditor@example.com',
        'Test.12345',
        rememberSession: false,
      ),
    ).called(1);
  });
}

UserModel _approvedUser(String email) {
  return UserModel(
    id: 'user-$email',
    fullName: 'Test Auditor',
    email: email,
    role: 'auditor',
    status: 'approved',
    accessToken: 'token',
    tokenExpiry: DateTime(2026, 7),
    createdAt: DateTime(2026),
    lastLoginAt: DateTime(2026),
  );
}
