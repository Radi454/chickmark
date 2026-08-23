import 'package:flutter/material.dart' as material;
import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/utils/text_direction_detector.dart';
import '../../../services/supabase/assistant_chat_service.dart'
    show defaultConversationKey;
import '../providers/realtime_voice_controller.dart';
import '../widgets/realtime_voice_orb.dart';

/// The full-screen "Pip Live" call surface: header, orb, a collapsed-by
/// -default transcript strip, and the three circular controls. Every widget
/// key here is load-bearing for `realtime_voice_screen_test.dart` and for
/// `assistant_chat_screen_realtime_test.dart` — keep them stable even when
/// restyling the widgets they're attached to.
class RealtimeVoiceScreen extends StatefulWidget {
  const RealtimeVoiceScreen({
    super.key,
    this.autoStart = false,
    this.conversationKey = defaultConversationKey,
  });

  final bool autoStart;

  /// Which conversation this call joins and is transcribed into — `'app'`
  /// (default) or `'app:'+uuid-v4`. Only consulted on the autoStart path;
  /// once a call is already active (banner reopen) this screen never calls
  /// `start` again, so the key of an already-running call cannot change.
  final String conversationKey;

  @override
  State<RealtimeVoiceScreen> createState() => _RealtimeVoiceScreenState();
}

class _RealtimeVoiceScreenState extends State<RealtimeVoiceScreen> {
  bool _started = false;
  bool _transcriptExpanded = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!widget.autoStart || _started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final controller = context.read<RealtimeVoiceController>();
      // Prefer the controller's own active key over this screen's — it
      // survives across the error state (see `activeConversationKey`'s own
      // doc), so a route that got rebuilt with a stale/default
      // `conversationKey` (e.g. main_shell overwriting `_liveConversationKey`
      // on reopen) still rebinds to the conversation the call actually
      // belongs to instead of hijacking it into a new one.
      final effectiveKey =
          controller.activeConversationKey ?? widget.conversationKey;
      controller.start(conversationKey: effectiveKey);
    });
  }

  /// The short label under "Pip" in the header. Deliberately excludes the
  /// `error` state — that message is shown centered under the orb instead
  /// (see [_ErrorAndRetry]), so it isn't said twice.
  String? _headerStatus(BuildContext context, RealtimeVoiceState state) =>
      switch (state) {
        RealtimeVoiceState.listening => context.tr('Listening'),
        RealtimeVoiceState.userSpeaking => context.tr('You are speaking'),
        RealtimeVoiceState.thinking => context.tr('Pip is thinking'),
        RealtimeVoiceState.assistantSpeaking => context.tr('Pip is speaking'),
        RealtimeVoiceState.reconnectingMuted => context.tr('Reconnecting'),
        RealtimeVoiceState.idle ||
        RealtimeVoiceState.ending => context.tr('Call ended'),
        RealtimeVoiceState.error => null,
        _ => context.tr('Connecting securely'),
      };

  Future<void> _end(RealtimeVoiceController controller) async {
    await controller.stop();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _retry(RealtimeVoiceController controller) async {
    // Captured before any `stop()` below: `stop()` clears
    // `activeConversationKey`, so the key must be read while it still
    // reflects which conversation the failed/reconnecting call was for.
    final effectiveKey =
        controller.activeConversationKey ?? widget.conversationKey;
    if (controller.state == RealtimeVoiceState.reconnectingMuted) {
      await controller.stop();
    }
    await controller.start(conversationKey: effectiveKey);
  }

  void _toggleTranscript() {
    setState(() => _transcriptExpanded = !_transcriptExpanded);
  }

  @override
  Widget build(BuildContext context) {
    final controller = context.watch<RealtimeVoiceController>();
    final state = controller.state;
    final isError = state == RealtimeVoiceState.error;
    final isReconnecting = state == RealtimeVoiceState.reconnectingMuted;
    final showRetry = isError || isReconnecting;

    return Scaffold(
      key: const ValueKey('pip-live-screen'),
      backgroundColor: AppColors.background,
      body: DecoratedBox(
        // A calm, barely-there gradient rather than a flat fill — enough to
        // read as intentional without competing with the orb.
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              AppColors.background,
              Color.lerp(AppColors.background, AppColors.primary, 0.05)!,
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              _LiveHeader(statusLabel: _headerStatus(context, state)),
              Expanded(
                child: Center(
                  // Scales the orb (and its error/retry copy) down together
                  // rather than overflowing when the transcript strip is
                  // expanded or the screen is short — the shape stays
                  // proportional at any size.
                  child: FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        AnimatedOpacity(
                          opacity: isReconnecting ? 0.45 : 1.0,
                          duration: const Duration(milliseconds: 250),
                          child: RealtimeVoiceOrb(state: state),
                        ),
                        _ErrorAndRetry(
                          controller: controller,
                          showRetry: showRetry,
                          onRetry: () => _retry(controller),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              _TranscriptStrip(
                captions: controller.captions,
                expanded: _transcriptExpanded,
                onToggle: _toggleTranscript,
              ),
              _ControlsRow(
                controller: controller,
                transcriptExpanded: _transcriptExpanded,
                onEnd: () => _end(controller),
                onToggleTranscript: _toggleTranscript,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LiveHeader extends StatelessWidget {
  const _LiveHeader({required this.statusLabel});

  /// Null while in the error state — the failure is described under the orb
  /// instead, so the header stays quiet rather than repeating it.
  final String? statusLabel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceXs,
        vertical: AppSizes.spaceXs,
      ),
      child: Row(
        children: [
          IconButton(
            key: const ValueKey('pip-live-minimize'),
            tooltip: context.tr('Minimize'),
            onPressed: () => Navigator.of(context).pop(),
            icon: const Icon(Icons.keyboard_arrow_down),
          ),
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(context.tr('Pip'), style: AppTextStyles.title),
                if (statusLabel != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    statusLabel!,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.textSecondary,
                    ),
                  ),
                ],
              ],
            ),
          ),
          // Balances the minimize button so the title column stays centered.
          const SizedBox(width: 48),
        ],
      ),
    );
  }
}

class _ErrorAndRetry extends StatelessWidget {
  const _ErrorAndRetry({
    required this.controller,
    required this.showRetry,
    required this.onRetry,
  });

  final RealtimeVoiceController controller;
  final bool showRetry;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final isError = controller.state == RealtimeVoiceState.error;
    if (!isError && !showRetry) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: AppSizes.spaceMd),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isError) ...[
            Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSizes.spaceLg,
              ),
              child: Text(
                context.tr(
                  controller.errorMessage ??
                      'Live voice is unavailable right now. Please try again.',
                ),
                style: AppTextStyles.caption,
                textAlign: TextAlign.center,
              ),
            ),
            if (controller.errorDetail != null)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSizes.spaceLg,
                  vertical: 2,
                ),
                // Technical English by design (it names code stages), so it
                // stays LTR and untranslated — see errorDetail's own doc.
                child: SelectableText(
                  controller.errorDetail!,
                  key: const ValueKey('pip-live-error-detail'),
                  textAlign: TextAlign.center,
                  textDirection: TextDirection.ltr,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.statusError,
                    fontSize: 10,
                  ),
                ),
              ),
          ],
          if (showRetry)
            Padding(
              padding: const EdgeInsets.only(top: AppSizes.spaceXs),
              child: TextButton(
                key: const ValueKey('pip-live-retry'),
                onPressed: onRetry,
                child: Text(context.tr('Retry')),
              ),
            ),
        ],
      ),
    );
  }
}

/// Collapsed by default: only the latest user turn and the latest assistant
/// turn (each independently, not simply "the last two by index"), so a long
/// call never leaves stale copy on screen. Tapping the strip — or the
/// dedicated toggle in [_ControlsRow] — expands it into the full scrollable
/// history. Hidden entirely once there is nothing to show.
class _TranscriptStrip extends StatelessWidget {
  const _TranscriptStrip({
    required this.captions,
    required this.expanded,
    required this.onToggle,
  });

  final List<RealtimeCaption> captions;
  final bool expanded;
  final VoidCallback onToggle;

  static List<RealtimeCaption> _latestTurns(List<RealtimeCaption> captions) {
    RealtimeCaption? lastUser;
    RealtimeCaption? lastAssistant;
    for (final caption in captions) {
      if (caption.speaker == RealtimeCaptionSpeaker.user) {
        lastUser = caption;
      } else {
        lastAssistant = caption;
      }
    }
    return [
      for (final caption in captions)
        if (identical(caption, lastUser) || identical(caption, lastAssistant))
          caption,
    ];
  }

  @override
  Widget build(BuildContext context) {
    if (captions.isEmpty) return const SizedBox.shrink();
    final visible = expanded ? captions : _latestTurns(captions);

    return GestureDetector(
      key: const ValueKey('pip-live-transcript'),
      behavior: HitTestBehavior.opaque,
      onTap: onToggle,
      child: ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Colors.black],
          stops: [0.0, 0.22],
        ).createShader(rect),
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: expanded ? 260 : 116),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.spaceLg,
              vertical: AppSizes.spaceSm,
            ),
            child: expanded
                ? ListView.builder(
                    itemCount: visible.length,
                    itemBuilder: (context, index) =>
                        _CaptionRow(caption: visible[index]),
                  )
                : Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (final caption in visible)
                        _CaptionRow(caption: caption),
                    ],
                  ),
          ),
        ),
      ),
    );
  }
}

class _CaptionRow extends StatelessWidget {
  const _CaptionRow({required this.caption});

  final RealtimeCaption caption;

  @override
  Widget build(BuildContext context) {
    final isUser = caption.speaker == RealtimeCaptionSpeaker.user;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            context.tr(isUser ? 'You' : 'Pip'),
            style: AppTextStyles.caption.copyWith(
              fontWeight: FontWeight.w700,
              color: isUser ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          // Raw material.Text, not the app's localized `Text`: this is the
          // model/user's own words, transcribed live, and must never pass
          // through the Arabic UI phrasebook (see F11 — a caption that
          // happens to equal a UI label like "Refresh" must render verbatim).
          material.Text(
            caption.text,
            textDirection: TextDirectionDetector.detect(caption.text),
            style: AppTextStyles.body,
          ),
        ],
      ),
    );
  }
}

class _ControlsRow extends StatelessWidget {
  const _ControlsRow({
    required this.controller,
    required this.transcriptExpanded,
    required this.onEnd,
    required this.onToggleTranscript,
  });

  final RealtimeVoiceController controller;
  final bool transcriptExpanded;
  final VoidCallback onEnd;
  final VoidCallback onToggleTranscript;

  @override
  Widget build(BuildContext context) {
    final isActive = controller.isRealtimeActive;
    final isMuted = controller.isMuted;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSizes.spaceXl,
          vertical: AppSizes.spaceLg,
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _CircleControl(
              controlKey: const ValueKey('pip-live-mute'),
              size: 56,
              icon: isMuted ? Icons.mic_off : Icons.mic,
              semanticLabel: context.tr(isMuted ? 'Unmute' : 'Mute'),
              filled: isMuted,
              backgroundColor: AppColors.primary,
              iconColor: isMuted ? Colors.white : AppColors.primary,
              onTap: isActive ? controller.toggleMute : null,
            ),
            _CircleControl(
              controlKey: const ValueKey('pip-live-end'),
              size: 64,
              icon: Icons.call_end,
              semanticLabel: context.tr('End live conversation'),
              filled: true,
              backgroundColor: AppColors.statusError,
              iconColor: Colors.white,
              onTap: isActive ? onEnd : null,
            ),
            _CircleControl(
              controlKey: const ValueKey('pip-live-transcript-toggle'),
              size: 44,
              icon: transcriptExpanded
                  ? Icons.expand_more
                  : Icons.expand_less,
              semanticLabel: context.tr(
                transcriptExpanded ? 'Collapse transcript' : 'Expand transcript',
              ),
              filled: false,
              iconColor: AppColors.textSecondary,
              onTap: controller.captions.isEmpty ? null : onToggleTranscript,
            ),
          ],
        ),
      ),
    );
  }
}

/// One circular control. No visible text by design — accessibility is
/// carried entirely by the explicit [Semantics] label (so
/// `find.bySemanticsLabel` and screen readers both see it) plus a
/// [Tooltip] for pointer/hover users.
class _CircleControl extends StatelessWidget {
  const _CircleControl({
    required this.controlKey,
    required this.size,
    required this.icon,
    required this.semanticLabel,
    required this.onTap,
    this.filled = false,
    this.backgroundColor,
    this.iconColor,
  });

  final Key controlKey;
  final double size;
  final IconData icon;
  final String semanticLabel;
  final VoidCallback? onTap;
  final bool filled;
  final Color? backgroundColor;
  final Color? iconColor;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    final resolvedIconColor = disabled
        ? AppColors.textDisabled
        : (iconColor ?? AppColors.textPrimary);
    return Semantics(
      label: semanticLabel,
      button: true,
      enabled: !disabled,
      excludeSemantics: true,
      child: Tooltip(
        message: semanticLabel,
        child: Material(
          key: controlKey,
          color: filled
              ? (disabled ? AppColors.textDisabled : backgroundColor)
              : Colors.transparent,
          shape: CircleBorder(
            side: filled
                ? BorderSide.none
                : BorderSide(color: AppColors.borderDefault, width: 1.5),
          ),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: resolvedIconColor, size: size * 0.42),
            ),
          ),
        ),
      ),
    );
  }
}
