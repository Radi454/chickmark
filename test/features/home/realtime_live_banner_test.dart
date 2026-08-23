import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/providers/realtime_voice_controller.dart';
import 'package:hatchaudit/features/chat/screens/realtime_voice_screen.dart';
import 'package:hatchaudit/features/chat/widgets/realtime_live_banner.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:provider/provider.dart';

void main() {
  test('shared shell route guard prevents duplicate mixed opens', () async {
    final opened = Completer<void>();
    var pushes = 0;
    final guard = RealtimeLiveRouteGuard(() async {
      pushes++;
      await opened.future;
    });

    final first = guard.open();
    final second = guard.open();
    expect(pushes, 1);
    opened.complete();
    await Future.wait([first, second]);
  });

  testWidgets(
    'active Live banner opens the existing call and its End action stops it',
    (tester) async {
      final controller = _ActiveRealtimeController();
      var opened = 0;
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: Scaffold(
            body: RealtimeLiveBanner(
              controller: controller,
              onOpen: () => opened++,
            ),
          ),
        ),
      );

      expect(find.byKey(const ValueKey('pip-live-banner')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pip-live-banner')));
      expect(opened, 1);
      await tester.tap(find.byTooltip('End live conversation'));
      await tester.pump();
      expect(controller.stopCount, 1);
    },
  );

  testWidgets(
    'shell Live composition reserves banner space and keeps compact content interactive',
    (tester) async {
      final controller = _ActiveRealtimeController();
      var opened = 0;
      var selected = 'Home';
      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              body: buildMainShellLiveBodyForTest(
                controller: controller,
                onOpen: () {
                  opened++;
                  Navigator.of(context).push<void>(
                    MaterialPageRoute<void>(
                      builder: (_) => ChangeNotifierProvider<
                        RealtimeVoiceController
                      >.value(
                        value: controller,
                        child: const RealtimeVoiceScreen(),
                      ),
                    ),
                  );
                },
                content: Column(
                  children: [
                    Text(selected),
                    TextButton(
                      key: const ValueKey('compact-tab-switch'),
                      onPressed: () => setState(() => selected = 'Settings'),
                      child: const Text('switch tab'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.byKey(const ValueKey('compact-tab-switch')));
      await tester.pump();
      expect(find.text('Settings'), findsOneWidget);
      expect(find.byKey(const ValueKey('pip-live-banner')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('pip-live-banner')));
      await tester.pump();
      await tester.pump();
      expect(opened, 1);
      expect(find.byType(RealtimeVoiceScreen), findsOneWidget);
      final screenContext = tester.element(find.byType(RealtimeVoiceScreen));
      expect(
        identical(screenContext.read<RealtimeVoiceController>(), controller),
        isTrue,
      );
      await tester.tap(find.byKey(const ValueKey('pip-live-end')));
      await tester.pump();
      expect(controller.stopCount, 1);
    },
  );
}

class _ActiveRealtimeController extends RealtimeVoiceController {
  int stopCount = 0;

  @override
  bool get isRealtimeActive => true;

  @override
  Future<void> stop() async {
    stopCount++;
  }
}
