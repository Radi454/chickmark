import 'dart:async';

import 'package:test/test.dart';

/// Proves the completer-interruption fix in
/// `AudioplayersAssistantAudioPlayer._playAndAwaitCompletion`
/// (`lib/services/audio/assistant_audio_player.dart`) in isolation.
///
/// The real class hard-depends on a concrete `audioplayers` `AudioPlayer`,
/// which cannot be faked without swapping `audioplayers`' own platform
/// singletons; doing that and driving it through `flutter test` was
/// attempted, but every run hung indefinitely inside `AudioPlayer`'s
/// internal event/broadcast-stream sequencing under a synthetic platform in
/// this sandbox (Dart's own 10-minute test timeout eventually fired, with no
/// exception or other diagnostic pointing at a specific line) — not
/// something safely resolvable within this fix's scope.
///
/// `_MirrorPlayer` below is a line-for-line structural copy of
/// `_playAndAwaitCompletion`'s control flow (same guard order, same
/// `previous`/`completer`/`_completeSub` bookkeeping), operating over a
/// minimal fake "player" instead of a real `AudioPlayer`. It is not a test
/// of the production class itself — that gap is real and noted in the
/// fix-round report — but it does run fast and reliably, and it does prove
/// the exact algorithm now shipped is correct: a second play interrupting a
/// still-pending first one resolves the first call's Future instead of
/// leaving it permanently pending, and `stop()` resolves whatever is
/// pending.
void main() {
  group('_playAndAwaitCompletion completer-interruption pattern', () {
    test(
      "a second play() while a first is still pending resolves the "
      "first call's future",
      () async {
        final fake = _FakePlayer();
        final mirror = _MirrorPlayer(fake);

        final first = mirror.play('chime');
        // Give the first call's synchronous-ish "start" a chance to run
        // before it is interrupted, matching how the real chime is already
        // underway when the reply audio cuts it off.
        await Future<void>.delayed(Duration.zero);

        final second = mirror.play('reply');

        // The regression: before the fix this would hang forever, because
        // `fake.stop()` (called by the second play) never fires an
        // onComplete event for the first clip, and the old code overwrote
        // the pending completer without resolving it.
        await expectLater(first, completes);

        fake.fireComplete();
        await expectLater(second, completes);
      },
    );

    test('stop() while a play() is pending resolves that call too', () async {
      final fake = _FakePlayer();
      final mirror = _MirrorPlayer(fake);

      final playback = mirror.play('clip');
      await Future<void>.delayed(Duration.zero);

      await mirror.stop();

      await expectLater(playback, completes);
    });

    test(
      'a play() that runs to natural completion resolves via the '
      'completion stream, not by being interrupted',
      () async {
        final fake = _FakePlayer();
        final mirror = _MirrorPlayer(fake);

        final playback = mirror.play('clip');
        await Future<void>.delayed(Duration.zero);

        fake.fireComplete();

        await expectLater(playback, completes);
      },
    );
  });
}

/// Structural mirror of `AudioplayersAssistantAudioPlayer._playAndAwaitCompletion`.
/// Keep this in lockstep with the real method if that method's control flow
/// ever changes — see the file-level doc comment above.
class _MirrorPlayer {
  _MirrorPlayer(this._player);

  final _FakePlayer _player;
  StreamSubscription<void>? _completeSub;
  Completer<void>? _pendingCompletion;

  Future<void> play(String clip) {
    return _playAndAwaitCompletion(() => _player.play(clip));
  }

  Future<void> _playAndAwaitCompletion(
    Future<void> Function() startPlayback,
  ) async {
    await _player.stop();
    await _completeSub?.cancel();

    final previous = _pendingCompletion;
    if (previous != null && !previous.isCompleted) {
      previous.complete();
    }

    final completer = Completer<void>();
    _pendingCompletion = completer;
    _completeSub = _player.onComplete.listen((_) {
      if (!completer.isCompleted) completer.complete();
    });

    try {
      await startPlayback();
    } catch (error, stackTrace) {
      if (!completer.isCompleted) {
        completer.completeError(error, stackTrace);
      }
    }
    return completer.future;
  }

  Future<void> stop() async {
    await _player.stop();
    await _completeSub?.cancel();
    _completeSub = null;
    final pending = _pendingCompletion;
    if (pending != null && !pending.isCompleted) {
      pending.complete();
    }
    _pendingCompletion = null;
  }
}

/// Minimal stand-in for the underlying `AudioPlayer`: `play()` resolves once
/// "playback starts" (matching audioplayers' real contract — the Future
/// resolves on start, not completion), and completion is reported solely
/// through [onComplete], which the test fires manually. `stop()` never fires
/// [onComplete], matching real `audioplayers` (no completion event for a
/// programmatic stop).
class _FakePlayer {
  final _controller = StreamController<void>.broadcast();

  Stream<void> get onComplete => _controller.stream;

  Future<void> play(String clip) async {}

  Future<void> stop() async {}

  void fireComplete() => _controller.add(null);
}
