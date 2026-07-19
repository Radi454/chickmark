import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/dashboard/providers/dashboard_provider.dart';
import 'package:hatchaudit/features/dashboard/providers/scope_comparison_provider.dart';
import 'package:hatchaudit/features/dashboard/widgets/dashboard_attention_section.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('attention section has an explicit empty operational state', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ScopeComparisonProvider()),
          ChangeNotifierProvider(create: (_) => DashboardProvider()),
        ],
        child: MaterialApp(
          home: Scaffold(body: DashboardAttentionSection(onOpenSource: (_) {})),
        ),
      ),
    );

    expect(find.text('What needs attention'), findsOneWidget);
    expect(
      find.text(
        'No current critical or watch findings in this operational scope.',
      ),
      findsOneWidget,
    );
    expect(find.text('0 critical'), findsOneWidget);
    expect(find.text('0 watch'), findsOneWidget);
  });
}
