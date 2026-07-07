import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/localized_material.dart';
import 'package:hatchaudit/core/theme/app_text_styles.dart';

void main() {
  test('app text styles include Arabic-capable font fallbacks', () {
    expect(AppTextStyles.body.fontFamilyFallback, contains('Noto Sans Arabic'));
    expect(AppTextStyles.body.fontFamilyFallback, contains('Arial'));
  });

  testWidgets('Arabic app locale resolves to RTL directionality', (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Scaffold(body: Text('Home')),
      ),
    );

    expect(
      Directionality.of(tester.element(find.text('الرئيسية'))),
      TextDirection.rtl,
    );
  });

  testWidgets('localized Text.rich translates text spans', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(text: 'Quick Actions'),
                TextSpan(text: ' · '),
                TextSpan(text: 'Recent Audits'),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('إجراءات سريعة · آخر الزيارات'), findsOneWidget);
  });

  testWidgets('localized Tooltip translates its message', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        locale: Locale('ar'),
        supportedLocales: AppLocalizations.supportedLocales,
        localizationsDelegates: [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
        ],
        home: Tooltip(message: 'Edit customer', child: SizedBox()),
      ),
    );

    final tooltip = tester.widget<material.Tooltip>(
      find.byType(material.Tooltip),
    );
    expect(tooltip.message, 'تعديل العميل');
  });
}
