import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/core/config/feature_flags.dart';
import 'package:hatchaudit/core/network/network_status_monitor.dart';
import 'package:hatchaudit/features/chat/providers/assistant_provider.dart';
import 'package:hatchaudit/features/chat/providers/realtime_voice_controller.dart';
import 'package:hatchaudit/features/chat/screens/assistant_chat_screen.dart';
import 'package:hatchaudit/features/chat/widgets/realtime_live_banner.dart';
import 'package:hatchaudit/features/home/widgets/main_shell.dart';
import 'package:hatchaudit/l10n/app_localizations.dart';
import 'package:hatchaudit/services/realtime/realtime_background_service.dart';
import 'package:provider/provider.dart';

import 'fake_assistant_chat_port.dart';

// Pip Live is parked behind FeatureFlags.realtimeEnabled (default: off — see
// lib/core/config/feature_flags.dart). This suite proves the UI stays
// unreachable at the flag's DEFAULT, even when a fully-formed
// RealtimeVoiceController is injected — the explicit check in
// assistant_chat_screen.dart is belt-and-braces on top of the shell never
// providing one. Same discipline as the other chat widget tests: no sqflite,
// everything injected, bounded pump() only — never pumpAndSettle().

const _micKey = ValueKey('assistant-mic');
const _liveKey = ValueKey('assistant-live');

/// Same reasoning as `assistant_chat_screen_realtime_test.dart`: the default
/// background port talks to a native platform channel that `flutter test`
/// (Android target by default) cannot answer, so every controller built here
/// gets a fake instead.
class _FakeBackgroundPort implements RealtimeBackgroundPort {
  final StreamController<void> _endRequests =
      StreamController<void>.broadcast();

  @override
  Stream<void> get endRequests => _endRequests.stream;

  @override
  Future<void> activate() async {}

  @override
  Future<void> deactivate() async {}

  @override
  void dispose() {
    _endRequests.close();
  }
}

NetworkStatusMonitor _monitor() => NetworkStatusMonitor(
  checkReachability: () async => true,
  connectivityStream: const Stream.empty(),
  initialStatus: NetworkStatus.online,
  startImmediately: false,
);

void main() {
  setUp(() {
    // Belt and braces: confirm every test in this file actually runs against
    // the shipped default rather than a value left over by another suite.
    expect(FeatureFlags.realtimeEnabled, isFalse);
  });

  tearDown(() {
    FeatureFlags.resetForTest();
  });

  testWidgets(
    'AssistantChatScreen shows no live control at the default flag, even '
    'with a RealtimeVoiceController injected',
    (tester) async {
      final controller = RealtimeVoiceController(
        backgroundPort: _FakeBackgroundPort(),
      );
      addTearDown(controller.dispose);
      final provider = AssistantProvider(
        port: FakeAssistantChatPort(),
      );

      await tester.pumpWidget(
        MaterialApp(
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: const [
            AppLocalizations.delegate,
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          home: ChangeNotifierProvider<NetworkStatusMonitor>.value(
            value: _monitor(),
            child: AssistantChatScreen(
              provider: provider,
              realtimeController: controller,
              loadOnInit: false,
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(
        find.byKey(_liveKey),
        findsNothing,
        reason: 'Pip Live is parked — no live control should be reachable',
      );
      // The recorded voice note button must remain fully present and
      // untouched by the flag.
      expect(find.byKey(_micKey), findsOneWidget);
    },
  );

  testWidgets(
    'buildMainShellLiveBodyForTest renders no RealtimeLiveBanner when the '
    'shell has no controller to hand it (the flag-off case)',
    (tester) async {
      const contentKey = ValueKey('parked-content');
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
            // Mirrors exactly what `_MainShellState.build()` passes when
            // `_realtimeVoice` is null (flag off): no controller at all.
            body: buildMainShellLiveBodyForTest(
              controller: null,
              onOpen: () => opened++,
              content: const SizedBox(key: contentKey),
            ),
          ),
        ),
      );

      expect(find.byType(RealtimeLiveBanner), findsNothing);
      expect(find.byKey(const ValueKey('pip-live-banner')), findsNothing);
      expect(find.byKey(contentKey), findsOneWidget);
      expect(opened, 0);
    },
  );
}
