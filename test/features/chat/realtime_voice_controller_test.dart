import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hatchaudit/features/chat/providers/realtime_voice_controller.dart';
import 'package:hatchaudit/services/realtime/realtime_background_service.dart';
import 'package:hatchaudit/services/realtime/realtime_call_signaling.dart';
import 'package:hatchaudit/services/realtime/realtime_session_service.dart';
import 'package:hatchaudit/services/realtime/realtime_sideband_channel.dart';
import 'package:hatchaudit/services/realtime/realtime_transport.dart';

import 'fake_realtime.dart';

/// Lets queued microtasks and stream events run without a real delay.
Future<void> settle() async {
  for (var i = 0; i < 6; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class FakeRealtimeBackgroundPort implements RealtimeBackgroundPort {
  FakeRealtimeBackgroundPort(this.log);

  final List<String> log;
  final StreamController<void> _endRequests =
      StreamController<void>.broadcast();
  Object? activateError;
  Completer<void>? activateGate;
  int activateCount = 0;
  int deactivateCount = 0;
  bool disposed = false;

  @override
  Stream<void> get endRequests => _endRequests.stream;

  @override
  Future<void> activate() async {
    log.add('background.activate');
    activateCount++;
    if (activateGate != null) await activateGate!.future;
    final error = activateError;
    if (error != null) throw error;
  }

  @override
  Future<void> deactivate() async {
    log.add('background.deactivate');
    deactivateCount++;
  }

  void requestEnd() => _endRequests.add(null);

  @override
  void dispose() {
    disposed = true;
    _endRequests.close();
  }
}

void main() {
  late FakeRealtimeSessionPort sessionPort;
  late FakeRealtimeSignaling signaling;
  late List<FakeRealtimeTransport> transports;
  late List<FakeRealtimeSideband> sidebands;
  late List<String> log;
  late List<RealtimeVoiceState> observed;
  late FakeRealtimeBackgroundPort background;

  RealtimeVoiceController build() {
    final controller = RealtimeVoiceController(
      sessionPort: sessionPort,
      signaling: signaling,
      transportFactory: () {
        final transport = FakeRealtimeTransport(log: log);
        transports.add(transport);
        return transport;
      },
      sidebandFactory: () {
        final sideband = FakeRealtimeSideband(log: log);
        sidebands.add(sideband);
        return sideband;
      },
      backgroundPort: background,
    );
    controller.addListener(() => observed.add(controller.state));
    return controller;
  }

  FakeRealtimeTransport transport() => transports.last;
  FakeRealtimeSideband sideband() => sidebands.last;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    log = <String>[];
    sessionPort = FakeRealtimeSessionPort(log: log);
    signaling = FakeRealtimeSignaling(log: log);
    transports = <FakeRealtimeTransport>[];
    sidebands = <FakeRealtimeSideband>[];
    observed = <RealtimeVoiceState>[];
    background = FakeRealtimeBackgroundPort(log);
  });

  tearDown(() {
    debugDefaultTargetPlatformOverride = null;
  });

  group('setup', () {
    test(
      'activates after microphone access and before session creation',
      () async {
        final controller = build();

        await controller.start();

        expect(
          log.indexOf('openMicrophone'),
          lessThan(log.indexOf('background.activate')),
        );
        expect(
          log.indexOf('background.activate'),
          lessThan(log.indexOf('createSession')),
        );
        controller.dispose();
      },
    );

    test('walks the states and stops at awaiting READY', () async {
      final controller = build();

      await controller.start();

      expect(observed, <RealtimeVoiceState>[
        RealtimeVoiceState.requestingPermission,
        RealtimeVoiceState.connectingMuted,
        RealtimeVoiceState.registeringCall,
        RealtimeVoiceState.bindingSideband,
        RealtimeVoiceState.awaitingAuthoritativeReady,
      ]);
      expect(controller.isRealtimeActive, isTrue);
      controller.dispose();
    });

    test('permission denial never activates the background port', () async {
      final controller = RealtimeVoiceController(
        sessionPort: sessionPort,
        signaling: signaling,
        backgroundPort: background,
        transportFactory: () => FakeRealtimeTransport(
          log: log,
        )..openMicrophoneError = const RealtimeMicPermissionException('denied'),
        sidebandFactory: () => FakeRealtimeSideband(log: log),
      );

      await controller.start();

      expect(background.activateCount, 0);
      controller.dispose();
    });

    test(
      'negotiates with a null-track transceiver and never transmits',
      () async {
        final controller = build();

        await controller.start();

        expect(transport().calls, <String>[
          'openMicrophone',
          'createConnection',
          'addSilentAudioTransceiver',
          'openEventChannel',
          'createOffer',
          'acceptAnswer',
        ]);
        expect(transport().calls, isNot(contains('startTransmitting')));
        expect(controller.isTransmitting, isFalse);
        controller.dispose();
      },
    );

    test('registers the call id before binding the sideband', () async {
      final controller = build();

      await controller.start();

      expect(
        log.indexOf('registerCall'),
        lessThan(log.indexOf('bind')),
        reason: 'register_call must run the instant the call id is known',
      );
      expect(sessionPort.registeredCallIds, <String>['rtc_call1']);
      expect(sideband().boundSessionId, 'session-1');
      controller.dispose();
    });

    test('binds with both credentials and the server generation', () async {
      final controller = build();

      await controller.start();

      expect(sideband().boundBindingToken, 'binding-token');
      expect(sideband().boundAccessToken, 'supabase-jwt');
      expect(sideband().boundGeneration, 1);
      controller.dispose();
    });

    test(
      'sends the health frame once, right after the bind succeeds',
      () async {
        final controller = build();

        await controller.start();

        expect(
          log.indexOf('bind'),
          lessThan(log.indexOf('sendHealth')),
          reason:
              'the server never announces READY without a health frame, and '
              'the wire contract requires bind to be the first frame',
        );
        expect(sideband().sendHealthCount, 1);
        // WebRTC and the data channel are already up by bind time in this
        // flow, so the frame carries no state to construct — see
        // kSidebandHealthFrame.
        expect(controller.state, RealtimeVoiceState.awaitingAuthoritativeReady);
        controller.dispose();
      },
    );

    test('READY still drives listening once the health frame is sent', () async {
      final controller = build();
      await controller.start();
      expect(sideband().sendHealthCount, 1);

      sideband().emitReady(sessionId: 'session-1');
      await settle();

      expect(controller.state, RealtimeVoiceState.listening);
      expect(transport().startTransmittingCount, 1);
      controller.dispose();
    });

    test('a second start while active is ignored', () async {
      final controller = build();
      await controller.start();

      await controller.start();

      expect(transports, hasLength(1));
      controller.dispose();
    });
  });

  group('background lifecycle', () {
    test(
      'stop during pending activation cleans up and never creates a session',
      () async {
        background.activateGate = Completer<void>();
        final controller = build();
        final starting = controller.start();
        await settle();

        await controller.stop();
        background.activateGate!.complete();
        await starting;

        expect(background.deactivateCount, greaterThanOrEqualTo(1));
        expect(sessionPort.calls, isNot(contains('createSession')));
        controller.dispose();
      },
    );

    test(
      'dispose during pending activation cleans up and never creates a session',
      () async {
        background.activateGate = Completer<void>();
        final controller = build();
        final starting = controller.start();
        await settle();

        controller.dispose();
        background.activateGate!.complete();
        await starting;
        await settle();

        expect(background.deactivateCount, greaterThanOrEqualTo(1));
        expect(sessionPort.calls, isNot(contains('createSession')));
      },
    );

    test('keeps one activation across the automatic recovery', () async {
      signaling.error = const RealtimeSignalingException('first failure');
      final controller = build();

      await controller.start();

      expect(transports, hasLength(2));
      expect(background.activateCount, 1);
      controller.dispose();
    });

    test('explicit stop deactivates the active background port', () async {
      final controller = build();
      await controller.start();

      await controller.stop();

      expect(background.deactivateCount, 1);
      controller.dispose();
    });

    test('final error deactivates the active background port', () async {
      signaling.error = const RealtimeSignalingException('broken');
      final controller = build();

      await controller.start();

      expect(controller.state, RealtimeVoiceState.error);
      expect(background.deactivateCount, 1);
      controller.dispose();
    });

    test(
      'recovery permission denial deactivates the active background port',
      () async {
        var attempts = 0;
        final controller = RealtimeVoiceController(
          sessionPort: sessionPort,
          signaling: signaling
            ..error = const RealtimeSignalingException('broken'),
          backgroundPort: background,
          transportFactory: () {
            final transport = FakeRealtimeTransport(log: log);
            if (attempts++ == 1) {
              transport.openMicrophoneError =
                  const RealtimeMicPermissionException('denied');
            }
            return transport;
          },
          sidebandFactory: () => FakeRealtimeSideband(log: log),
        );

        await controller.start();

        expect(controller.state, RealtimeVoiceState.error);
        expect(background.deactivateCount, 1);
        controller.dispose();
      },
    );

    test('notification end uses stop and records user ended', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      background.requestEnd();
      await settle();

      expect(controller.state, RealtimeVoiceState.idle);
      expect(sessionPort.endReasons, <RealtimeEndReason>[
        RealtimeEndReason.userEnded,
      ]);
      expect(background.deactivateCount, 1);
      controller.dispose();
    });

    test('dispose deactivates the active background port', () async {
      final controller = build();
      await controller.start();

      controller.dispose();
      await settle();

      expect(background.deactivateCount, 1);
      expect(background.disposed, isTrue);
    });
  });

  group('authoritative READY', () {
    test('is the only thing that starts transmission', () async {
      final controller = build();
      await controller.start();
      expect(transport().isTransmitting, isFalse);

      sideband().emitReady(sessionId: 'session-1');
      await settle();

      expect(transport().startTransmittingCount, 1);
      expect(controller.isTransmitting, isTrue);
      expect(controller.state, RealtimeVoiceState.listening);
      controller.dispose();
    });

    test('a duplicate READY never toggles transmission again', () async {
      final controller = build();
      await controller.start();

      sideband().emitReady(sessionId: 'session-1');
      await settle();
      sideband().emitReady(sessionId: 'session-1');
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      expect(transport().startTransmittingCount, 1);
      expect(controller.state, RealtimeVoiceState.listening);
      controller.dispose();
    });

    test('a READY for another session id is ignored', () async {
      final controller = build();
      await controller.start();

      sideband().emitReady(sessionId: 'session-99');
      await settle();

      expect(transport().startTransmittingCount, 0);
      controller.dispose();
    });

    test('a READY for another generation is ignored', () async {
      final controller = build();
      await controller.start();

      sideband().emitReady(sessionId: 'session-1', generation: 7);
      await settle();

      expect(transport().startTransmittingCount, 0);
      expect(controller.state, RealtimeVoiceState.awaitingAuthoritativeReady);
      controller.dispose();
    });

    test('a READY arriving after stop cannot re-enable the mic', () async {
      final controller = build();
      await controller.start();
      final stale = sideband();
      final staleTransport = transport();

      await controller.stop();
      stale.emitReady(sessionId: 'session-1');
      await settle();

      expect(staleTransport.startTransmittingCount, 0);
      expect(controller.state, RealtimeVoiceState.idle);
      controller.dispose();
    });
  });

  group('sideband close codes', () {
    test('a rejected bind and a lost lease read differently', () async {
      final rejected = build();
      await rejected.start();
      sideband().emitClosing(RealtimeSidebandCloseCause.bindRejected);
      await settle();
      // One automatic recovery is spent first, then the cause is surfaced.
      sidebands.last.emitClosing(RealtimeSidebandCloseCause.bindRejected);
      await settle();
      expect(rejected.state, RealtimeVoiceState.error);
      final rejectedMessage = rejected.errorMessage;
      rejected.dispose();

      transports.clear();
      sidebands.clear();
      final lost = build();
      await lost.start();
      sideband().emitClosing(RealtimeSidebandCloseCause.leaseLost);
      await settle();
      sidebands.last.emitClosing(RealtimeSidebandCloseCause.leaseLost);
      await settle();

      expect(lost.state, RealtimeVoiceState.error);
      expect(lost.errorMessage, isNot(rejectedMessage));
      expect(
        lost.errorMessage,
        sidebandCloseMessage(RealtimeSidebandCloseCause.leaseLost),
      );
      lost.dispose();
    });

    test('a bind timeout is its own message', () async {
      final controller = build();
      await controller.start();

      sideband().emitClosing(RealtimeSidebandCloseCause.bindTimeout);
      await settle();
      sidebands.last.emitClosing(RealtimeSidebandCloseCause.bindTimeout);
      await settle();

      expect(
        controller.errorMessage,
        sidebandCloseMessage(RealtimeSidebandCloseCause.bindTimeout),
      );
      controller.dispose();
    });

    test('a normal close ends the call instead of erroring', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      sideband().emitClosing(RealtimeSidebandCloseCause.normal);
      await settle();

      expect(controller.state, RealtimeVoiceState.idle);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });

    test('the closing NOTICE alone does not tear the call down', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      // `{"type":"closing","reason":"server_drain"}` carries no close code; the
      // socket close that follows is what the client acts on.
      sideband().emit(
        parseSidebandEvent({'type': 'closing', 'reason': 'server_drain'}),
      );
      await settle();

      expect(controller.state, RealtimeVoiceState.listening);
      controller.dispose();
    });

    test(
      'an error notice surfaces a mapped message, never the raw code',
      () async {
        final controller = build();
        await controller.start();

        sideband().emit(
          parseSidebandEvent({'type': 'error', 'code': 'identity_mismatch'}),
        );
        await settle();
        sidebands.last.emit(
          parseSidebandEvent({'type': 'error', 'code': 'identity_mismatch'}),
        );
        await settle();

        expect(controller.state, RealtimeVoiceState.error);
        expect(
          controller.errorMessage,
          sidebandErrorMessage('identity_mismatch'),
        );
        expect(controller.errorMessage, isNot(contains('identity_mismatch')));
        controller.dispose();
      },
    );
  });

  group('cancellation during setup', () {
    test('stop() mid-permission never enables transmission', () async {
      final gate = Completer<void>();
      final controller = RealtimeVoiceController(
        sessionPort: sessionPort,
        signaling: signaling,
        transportFactory: () {
          final t = FakeRealtimeTransport(log: log)..openMicrophoneGate = gate;
          transports.add(t);
          return t;
        },
        sidebandFactory: () {
          final s = FakeRealtimeSideband(log: log);
          sidebands.add(s);
          return s;
        },
      );
      final pending = controller.start();

      // start() is suspended on openMicrophone; cancel from under it.
      await settle();
      await controller.stop();
      if (!gate.isCompleted) gate.complete();
      await pending;
      await settle();

      expect(
        transports.every((t) => t.startTransmittingCount == 0),
        isTrue,
        reason: 'a cancelled setup must never reach replaceTrack',
      );
      expect(controller.state, RealtimeVoiceState.idle);
      controller.dispose();
    });

    test('stop() mid-SDP-exchange tears the attempt down', () async {
      final controller = build();
      final gate = Completer<void>();
      signaling.gate = gate;
      final pending = controller.start();
      await settle();

      await controller.stop();
      gate.complete();
      await pending;
      await settle();

      expect(transport().startTransmittingCount, 0);
      expect(transport().disposed, isTrue);
      expect(controller.state, RealtimeVoiceState.idle);
      controller.dispose();
    });

    test('dispose() mid-setup never enables transmission', () async {
      final controller = build();
      final gate = Completer<void>();
      signaling.gate = gate;
      final pending = controller.start();
      await settle();

      controller.dispose();
      gate.complete();
      await pending;
      await settle();

      expect(transport().startTransmittingCount, 0);
      expect(transport().disposed, isTrue);
    });
  });

  group('teardown', () {
    test('stop releases the transport, sideband and backend session', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      await controller.stop();

      expect(transport().disposed, isTrue);
      expect(transport().isTransmitting, isFalse);
      expect(transport().calls, contains('stopTransmitting'));
      expect(sideband().closed, isTrue);
      expect(sessionPort.calls, contains('endSession'));
      expect(controller.state, RealtimeVoiceState.idle);
      controller.dispose();
    });

    test('stopping before READY aborts setup instead of ending', () async {
      final controller = build();
      await controller.start();

      await controller.stop();

      // abort_setup, not end: the call never went live, and reporting its
      // orphaned id is what lets the sweeper hang it up at the provider.
      expect(sessionPort.calls, contains('abortSetup'));
      expect(sessionPort.calls, isNot(contains('endSession')));
      expect(sessionPort.abortedCallIds, <String?>['rtc_call1']);
      controller.dispose();
    });

    test('stopping a live call ends it with user_ended', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      await controller.stop();

      expect(sessionPort.calls, contains('endSession'));
      expect(sessionPort.endReasons, <RealtimeEndReason>[
        RealtimeEndReason.userEnded,
      ]);
      controller.dispose();
    });

    test('stop from idle is a no-op', () async {
      final controller = build();

      await controller.stop();

      expect(sessionPort.calls, isEmpty);
      expect(controller.state, RealtimeVoiceState.idle);
      controller.dispose();
    });

    test('dispose after a live call releases everything', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      controller.dispose();
      await settle();

      expect(transport().disposed, isTrue);
      expect(sideband().closed, isTrue);
    });
  });

  group('turn states', () {
    Future<RealtimeVoiceController> live() async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();
      return controller;
    }

    test('data-channel events drive speaking/thinking', () async {
      final controller = await live();

      transport().eventController.add({
        'type': 'input_audio_buffer.speech_started',
      });
      await settle();
      expect(controller.state, RealtimeVoiceState.userSpeaking);

      transport().eventController.add({'type': 'response.created'});
      await settle();
      expect(controller.state, RealtimeVoiceState.thinking);

      transport().eventController.add({'type': 'response.audio.delta'});
      await settle();
      expect(controller.state, RealtimeVoiceState.assistantSpeaking);

      transport().eventController.add({'type': 'response.done'});
      await settle();
      expect(controller.state, RealtimeVoiceState.listening);
      controller.dispose();
    });

    test(
      'sideband turn-state frames no longer exist and are dropped',
      () async {
        final controller = await live();

        // The sideband contract has three notices; anything else is unknown and
        // must not move the machine.
        sideband().emit(
          parseSidebandEvent({'type': 'state', 'state': 'thinking'}),
        );
        sideband().emit(
          parseSidebandEvent({'type': 'caption', 'text': 'leaked'}),
        );
        await settle();

        expect(controller.state, RealtimeVoiceState.listening);
        expect(controller.captions, isEmpty);
        controller.dispose();
      },
    );

    test('interrupt moves off assistantSpeaking without relaying', () async {
      final controller = await live();
      transport().eventController.add({'type': 'response.audio.delta'});
      await settle();
      final callsBefore = List<String>.of(sessionPort.calls);

      controller.interrupt();

      expect(controller.state, RealtimeVoiceState.listening);
      expect(sessionPort.calls, callsBefore);
      controller.dispose();
    });

    test('turn events before READY never move the machine', () async {
      final controller = build();
      await controller.start();

      transport().eventController.add({
        'type': 'input_audio_buffer.speech_started',
      });
      transport().eventController.add({'type': 'response.created'});
      await settle();

      expect(controller.state, RealtimeVoiceState.awaitingAuthoritativeReady);
      controller.dispose();
    });
  });

  group('client event policy', () {
    test('tool events are dropped and never relayed to any backend', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();
      final backendCallsBefore = List<String>.of(sessionPort.calls);
      final stateBefore = controller.state;

      transport().eventController.add({
        'type': 'response.function_call_arguments.delta',
        'delta': '{"customerId":"secret"}',
      });
      transport().eventController.add({
        'type': 'response.function_call_arguments.done',
        'arguments': '{"customerId":"secret"}',
      });
      transport().eventController.add({
        'type': 'response.output_item.added',
        'item': {'type': 'function_call', 'name': 'lookup_flock'},
      });
      transport().eventController.add({
        'type': 'conversation.item.created',
        'item': {'type': 'function_call_output', 'output': 'sensitive'},
      });
      await settle();

      expect(sessionPort.calls, backendCallsBefore);
      expect(controller.state, stateBefore);
      expect(
        controller.captions.any((caption) => caption.text.contains('secret')),
        isFalse,
      );
      controller.dispose();
    });

    test('unrecognised event types are dropped silently', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      transport().eventController.add({'type': 'some.future.event'});
      transport().eventController.add(<String, dynamic>{});
      await settle();

      expect(controller.state, RealtimeVoiceState.listening);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });

    test('captions accumulate locally from transcript deltas', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      transport().eventController.add({
        'type': 'response.audio_transcript.delta',
        'delta': 'Hatch of ',
      });
      transport().eventController.add({
        'type': 'response.audio_transcript.delta',
        'delta': '84 percent.',
      });
      await settle();

      expect(controller.captions.single.text, 'Hatch of 84 percent.');
      controller.dispose();
    });

    test('the final transcript replaces the streamed line, never doubles it',
        () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      transport().eventController.add({
        'type': 'response.audio_transcript.delta',
        'delta': 'Hatch of ',
      });
      transport().eventController.add({
        'type': 'response.audio_transcript.delta',
        'delta': '84 percent.',
      });
      // The `.done` frame carries the FULL transcript again; it must close the
      // open line with that authoritative text, not append a second copy.
      transport().eventController.add({
        'type': 'response.audio_transcript.done',
        'transcript': 'Hatch of 84 percent.',
      });
      await settle();

      expect(controller.captions.single.text, 'Hatch of 84 percent.');
      expect(controller.captions.single.isFinal, isTrue);

      // A completed-only user transcription (no deltas) still lands as its
      // own new line.
      transport().eventController.add({
        'type': 'conversation.item.input_audio_transcription.completed',
        'transcript': 'What about fertility?',
      });
      await settle();

      expect(controller.captions.length, 2);
      expect(controller.captions.last.text, 'What about fertility?');
      expect(controller.captions.last.isFinal, isTrue);
      controller.dispose();
    });
  });

  group('mute', () {
    test('flips the track flag without stopping transmission', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      controller.toggleMute();

      expect(controller.isMuted, isTrue);
      expect(transport().calls, contains('setMicrophoneEnabled(false)'));
      expect(controller.isTransmitting, isTrue);

      controller.toggleMute();
      expect(controller.isMuted, isFalse);
      expect(transport().calls, contains('setMicrophoneEnabled(true)'));
      controller.dispose();
    });
  });

  group('permission denial', () {
    test('fails straight to error without an automatic retry', () async {
      final controllerWithDenial = RealtimeVoiceController(
        sessionPort: sessionPort,
        signaling: signaling,
        transportFactory: () {
          final t = FakeRealtimeTransport(log: log)
            ..openMicrophoneError = const RealtimeMicPermissionException(
              'Microphone access is off.',
            );
          transports.add(t);
          return t;
        },
        sidebandFactory: () {
          final s = FakeRealtimeSideband(log: log);
          sidebands.add(s);
          return s;
        },
      );

      await controllerWithDenial.start();

      expect(controllerWithDenial.state, RealtimeVoiceState.error);
      expect(controllerWithDenial.errorMessage, 'Microphone access is off.');
      expect(
        transports,
        hasLength(1),
        reason: 'a denial must not trigger the automatic recovery',
      );
      expect(transports.single.disposed, isTrue);
      controllerWithDenial.dispose();
    });

    test('the user can retry after a denial', () async {
      var deny = true;
      final controller = RealtimeVoiceController(
        sessionPort: sessionPort,
        signaling: signaling,
        transportFactory: () {
          final t = FakeRealtimeTransport(log: log);
          if (deny) {
            t.openMicrophoneError = const RealtimeMicPermissionException(
              'Microphone access is off.',
            );
          }
          transports.add(t);
          return t;
        },
        sidebandFactory: () {
          final s = FakeRealtimeSideband(log: log);
          sidebands.add(s);
          return s;
        },
      );
      await controller.start();
      expect(controller.state, RealtimeVoiceState.error);

      deny = false;
      await controller.start();

      expect(controller.state, RealtimeVoiceState.awaitingAuthoritativeReady);
      expect(controller.errorMessage, isNull);
      controller.dispose();
    });
  });

  group('recovery', () {
    test('recovers once, restarting non-transmitting', () async {
      final controller = build();
      // First attempt fails; the single automatic recovery succeeds.
      sessionPort.createSessionOutcomes.addAll(<Object?>[
        const RealtimeSessionException('Grant failed.', 'x'),
        null,
      ]);

      await controller.start();
      await settle();

      expect(transports, hasLength(2));
      expect(transports.first.disposed, isTrue);
      expect(transports.last.startTransmittingCount, 0);
      expect(controller.state, RealtimeVoiceState.awaitingAuthoritativeReady);
      // Only the attempt that actually bound sends a health frame, and it
      // does so exactly once: the first attempt failed at createSession,
      // before its sideband ever bound.
      expect(sidebands, hasLength(2));
      expect(sidebands.first.sendHealthCount, 0);
      expect(sidebands.last.sendHealthCount, 1);

      // A READY belonging to the abandoned attempt is refused...
      sidebands.first.emitReady(sessionId: 'session-1');
      await settle();
      expect(transports.last.startTransmittingCount, 0);

      // ...and only a current-generation one starts transmission.
      sidebands.last.emitReady(sessionId: 'session-1', generation: 1);
      await settle();
      expect(transports.last.startTransmittingCount, 1);
      controller.dispose();
    });

    test('releases the failed session before reconnecting', () async {
      final controller = build();
      await controller.start();
      sideband().emitReady(sessionId: 'session-1');
      await settle();

      transport().connectionController.add(RealtimeConnectionState.failed);
      await settle();

      // The control plane allows one live session per profile, so the old one
      // must be handed back before `start` is called again.
      expect(
        sessionPort.calls.indexOf('endSession'),
        lessThan(sessionPort.calls.lastIndexOf('createSession')),
      );
      expect(sessionPort.endReasons, contains(RealtimeEndReason.clientError));
      controller.dispose();
    });

    test('never loops: a second failure ends in error', () async {
      final controller = build();
      sessionPort.createSessionError = const RealtimeSessionException(
        'Grant failed.',
        'x',
      );

      await controller.start();
      await settle();

      expect(transports, hasLength(2));
      expect(controller.state, RealtimeVoiceState.error);
      expect(controller.errorMessage, 'Grant failed.');
      expect(transports.every((t) => t.disposed), isTrue);
      expect(transports.every((t) => t.startTransmittingCount == 0), isTrue);
      controller.dispose();
    });

    test(
      'a dropped connection reconnects on a fresh, silent transport',
      () async {
        final controller = build();
        await controller.start();
        sideband().emitReady(sessionId: 'session-1');
        await settle();
        final first = transport();

        first.connectionController.add(RealtimeConnectionState.failed);
        await settle();

        expect(transports, hasLength(2));
        expect(first.disposed, isTrue);
        // The replacement call is back to a null-track sender and needs its own
        // authoritative READY before a single packet can leave the device.
        expect(transports.last.startTransmittingCount, 0);
        expect(controller.isTransmitting, isFalse);
        expect(controller.state, RealtimeVoiceState.awaitingAuthoritativeReady);

        // And a second drop, having used up the one recovery, ends in error.
        transports.last.connectionController.add(
          RealtimeConnectionState.failed,
        );
        await settle();
        expect(transports, hasLength(2));
        expect(controller.state, RealtimeVoiceState.error);
        controller.dispose();
      },
    );
  });

  group('error detail diagnostics', () {
    test(
      'a setup failure names its stage and exception in errorDetail',
      () async {
        // Fails at acceptAnswer — the step right before the sideband bind, and
        // the one an on-device failure was impossible to distinguish without
        // this diagnostic. Every transport the factory hands out carries the
        // error, so the automatic recovery fails identically and the ORIGINAL
        // detail must be the one that survives.
        final controller = RealtimeVoiceController(
          sessionPort: sessionPort,
          signaling: signaling,
          transportFactory: () {
            final transport = FakeRealtimeTransport(log: log)
              ..acceptAnswerError = StateError('setRemoteDescription rejected');
            transports.add(transport);
            return transport;
          },
          sidebandFactory: () {
            final sideband = FakeRealtimeSideband(log: log);
            sidebands.add(sideband);
            return sideband;
          },
        );

        await controller.start();
        await settle();

        expect(controller.state, RealtimeVoiceState.error);
        expect(controller.errorDetail, isNotNull);
        expect(controller.errorDetail, contains('acceptAnswer'));
        expect(controller.errorDetail, contains('StateError'));
        expect(
          controller.errorDetail,
          contains('setRemoteDescription rejected'),
        );
        // The mic can never have gone live on a failed setup.
        expect(transports.every((t) => t.startTransmittingCount == 0), isTrue);
        controller.dispose();
      },
    );

    test('a fresh start clears the previous detail', () async {
      final controller = build();
      sessionPort.createSessionError = const RealtimeSessionException(
        'Grant failed.',
        'x',
      );
      await controller.start();
      await settle();
      expect(controller.errorDetail, contains('createSession'));

      // Next attempt succeeds; stale diagnostics must not survive it.
      sessionPort.createSessionError = null;
      await controller.start();
      await settle();
      expect(controller.errorDetail, isNull);
      await controller.stop();
      controller.dispose();
    });
  });

  group('conversation key', () {
    test('defaults to the app sentinel and exposes it while active', () async {
      final controller = build();

      await controller.start();

      expect(sessionPort.requestedConversationKeys, <String>['app']);
      expect(controller.activeConversationKey, 'app');
      controller.dispose();
    });

    test('a caller-supplied key is threaded to createSession', () async {
      final controller = build();
      const key = 'app:11111111-1111-4111-8111-111111111111';

      await controller.start(conversationKey: key);

      expect(sessionPort.requestedConversationKeys, <String>[key]);
      expect(controller.activeConversationKey, key);
      controller.dispose();
    });

    test('is cleared once the call returns to idle', () async {
      final controller = build();
      const key = 'app:11111111-1111-4111-8111-111111111111';
      await controller.start(conversationKey: key);
      expect(controller.activeConversationKey, key);

      await controller.stop();

      expect(controller.activeConversationKey, isNull);
      controller.dispose();
    });

    test(
      'survives the error state, so a failed call is still attributable',
      () async {
        final controller = build();
        const key = 'app:11111111-1111-4111-8111-111111111111';
        sessionPort.createSessionError = const RealtimeSessionException(
          'Grant failed.',
          'x',
        );

        await controller.start(conversationKey: key);
        await settle();

        expect(controller.state, RealtimeVoiceState.error);
        expect(controller.activeConversationKey, key);
        controller.dispose();
      },
    );

    test(
      'the automatic recovery reconnect reuses the same key, not the default',
      () async {
        final controller = build();
        const key = 'app:11111111-1111-4111-8111-111111111111';
        signaling.error = const RealtimeSignalingException('first failure');

        await controller.start(conversationKey: key);

        expect(sessionPort.requestedConversationKeys, <String>[key, key]);
        controller.dispose();
      },
    );

    test('an invalid key is rejected before any backend call', () async {
      final controller = build();

      await expectLater(
        controller.start(conversationKey: 'not-a-real-key'),
        throwsArgumentError,
      );
      expect(sessionPort.calls, isEmpty);
      controller.dispose();
    });
  });

  group('invariant assertion helper', () {
    test('reports no outbound audio before READY', () async {
      final controller = build();
      await controller.start();
      transport().reports = const <RealtimeOutboundAudioReport>[
        RealtimeOutboundAudioReport(packetsSent: 0),
      ];

      expect(
        noAudioHasBeenTransmitted(await controller.outboundAudioReports()),
        isTrue,
      );
      controller.dispose();
    });
  });
}
