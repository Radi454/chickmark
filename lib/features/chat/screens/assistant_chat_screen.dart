import 'package:flutter/material.dart' as material;
import 'package:gpt_markdown/gpt_markdown.dart';
import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/config/feature_flags.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/network_status_monitor.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/conversation_title.dart';
import '../../../core/utils/text_direction_detector.dart';
import '../../../services/supabase/assistant_chat_service.dart'
    show defaultConversationKey;
import '../models/chat_message.dart';
import '../providers/assistant_provider.dart';
import '../providers/realtime_voice_controller.dart';
import 'realtime_voice_screen.dart';
import '../widgets/assistant_avatar.dart';

/// In-app assistant chat.
///
/// [provider] is a test seam: when supplied it is used directly instead of the
/// one the shell registers above this screen, so a widget test can drive the
/// conversation from a fake port. [loadOnInit] lets a test pump the screen
/// without firing the history request.
///
/// [realtimeController] is the same seam for the live ("Pip Live") call. It is
/// looked up as a *nullable* dependency, so a test that only cares about typed
/// chat can pump this screen without registering one, and the live control
/// simply does not appear.
///
/// [conversationKey] identifies which conversation this screen is showing —
/// `'app'` (legacy single thread) or `'app:'+uuid-v4` for one of the
/// multi-conversation threads opened from the conversations list. It is
/// purely a label carried through to [onOpenLive]; the injected [provider]
/// (or the shell-registered one) is what actually determines which
/// conversation's turns are loaded. [initialTitle] is the list-derived title
/// shown in the app bar immediately, before this conversation's own history
/// (and any server-derived title) has loaded — `null` falls back to "Pip".
/// Derives the app-bar title from the first user turn once a fresh
/// conversation (no server/list-derived [AssistantChatScreen.initialTitle])
/// has one — mirrors the server's own title derivation
/// (`conversation_title.ts`) via [deriveConversationTitle]. Returns `null`
/// while there is no user turn yet (or its text collapses to nothing), so the
/// caller falls back to [AppStrings.assistantTab].
String? _deriveDisplayTitle(List<ChatMessage> messages) {
  for (final message in messages) {
    if (message.isUser) return deriveConversationTitle(message.text);
  }
  return null;
}

class AssistantChatScreen extends StatelessWidget {
  const AssistantChatScreen({
    super.key,
    this.provider,
    this.realtimeController,
    this.onOpenLive,
    this.loadOnInit = true,
    this.conversationKey = defaultConversationKey,
    this.initialTitle,
  });

  final AssistantProvider? provider;
  final RealtimeVoiceController? realtimeController;
  final void Function(String conversationKey)? onOpenLive;
  final bool loadOnInit;
  final String conversationKey;
  final String? initialTitle;

  @override
  Widget build(BuildContext context) {
    Widget child = _AssistantChatView(
      loadOnInit: loadOnInit,
      conversationKey: conversationKey,
      initialTitle: initialTitle,
      onOpenLive: onOpenLive,
    );
    final realtime = realtimeController;
    if (realtime != null) {
      child = ChangeNotifierProvider<RealtimeVoiceController>.value(
        value: realtime,
        child: child,
      );
    }
    final injected = provider;
    if (injected == null) return child;
    return ChangeNotifierProvider<AssistantProvider>.value(
      value: injected,
      child: child,
    );
  }
}

class _AssistantChatView extends StatefulWidget {
  const _AssistantChatView({
    required this.loadOnInit,
    required this.conversationKey,
    this.initialTitle,
    this.onOpenLive,
  });

  final bool loadOnInit;
  final String conversationKey;
  final String? initialTitle;
  final void Function(String conversationKey)? onOpenLive;

  @override
  State<_AssistantChatView> createState() => _AssistantChatViewState();
}

class _AssistantChatViewState extends State<_AssistantChatView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastMessageCount = 0;
  bool _openingLive = false;

  // Reloads this conversation's history exactly once after a Pip Live call
  // that belonged to it ends, so the call's persisted transcript (written
  // server-side by the sideband) appears in the visible thread without the
  // user having to leave and reopen it. `_reloadArmedForThisCall` is set
  // while the controller is bound to THIS screen's conversationKey (in any
  // non-idle state — including error, so a call that failed after already
  // going live still triggers the reload) and consumed on the transition
  // back to idle. By the time a call reaches idle, `activeConversationKey`
  // has already been cleared (see `RealtimeVoiceController.stop`), so the key
  // must be captured earlier, while the call is still active.
  RealtimeVoiceController? _realtimeForReload;
  bool _reloadArmedForThisCall = false;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AssistantProvider>().load();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _attachRealtimeReloadListener();
    });
  }

  void _attachRealtimeReloadListener() {
    if (!mounted) return;
    // Parked: with the flag off the shell never provides a controller, so
    // this lookup is already null — skip it explicitly rather than rely on
    // that alone.
    if (!FeatureFlags.realtimeEnabled) return;
    final realtime = context.read<RealtimeVoiceController?>();
    if (realtime == null) return;
    _realtimeForReload = realtime;
    _reloadArmedForThisCall =
        realtime.activeConversationKey == widget.conversationKey;
    realtime.addListener(_onRealtimeChangedForReload);
  }

  void _onRealtimeChangedForReload() {
    final realtime = _realtimeForReload;
    if (realtime == null) return;
    if (realtime.state != RealtimeVoiceState.idle) {
      if (realtime.activeConversationKey == widget.conversationKey) {
        _reloadArmedForThisCall = true;
      }
      return;
    }
    if (!_reloadArmedForThisCall) return;
    _reloadArmedForThisCall = false;
    if (mounted) context.read<AssistantProvider>().load();
  }

  @override
  void dispose() {
    _realtimeForReload?.removeListener(_onRealtimeChangedForReload);
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the newest turn in view. Deferred to the next frame so the list has
  /// already been laid out with the new item when we measure its extent.
  void _scrollToNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scroll.hasClients) return;
      _scroll.jumpTo(_scroll.position.maxScrollExtent);
    });
  }

  Future<void> _send() async {
    final provider = context.read<AssistantProvider>();
    final text = _input.text;
    if (text.trim().isEmpty) return;
    _input.clear();
    await provider.send(text);
  }

  Future<void> _toggleMic() async {
    final provider = context.read<AssistantProvider>();
    if (provider.isRecording) {
      await provider.stopRecordingAndSend();
    } else {
      await provider.startRecording();
    }
  }

  Future<void> _toggleLive(RealtimeVoiceController realtime) async {
    // Parked: unreachable via the UI (see `onLiveTap` above), kept as a
    // defensive guard rather than relying solely on the button being absent.
    if (!FeatureFlags.realtimeEnabled) return;
    final shellOpen = widget.onOpenLive;
    if (shellOpen != null) {
      shellOpen(widget.conversationKey);
      return;
    }
    if (_openingLive) return;
    _openingLive = true;
    try {
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(
          builder: (_) => ChangeNotifierProvider.value(
            value: realtime,
            child: RealtimeVoiceScreen(
              autoStart: !realtime.isRealtimeActive,
              conversationKey: widget.conversationKey,
            ),
          ),
        ),
      );
    } finally {
      _openingLive = false;
    }
  }

  Future<void> _confirmClear() async {
    final provider = context.read<AssistantProvider>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear this conversation?'),
        content: const Text(
          'The messages here are removed. Your saved records are not affected.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text(AppStrings.cancel),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await provider.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<AssistantProvider>();
    // Nullable lookup on purpose: pre-existing tests (and any host that has
    // not registered the controller) must keep working without one.
    final realtime = context.watch<RealtimeVoiceController?>();
    final isRealtimeActive = realtime?.isRealtimeActive ?? false;
    final isOffline = context.select<NetworkStatusMonitor, bool>(
      (monitor) => monitor.isOffline,
    );
    final messages = provider.messages;
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToNewest();
    }

    // True only while a live call THIS conversation owns is up — a call
    // bound to some other conversation must never gate this screen's clear
    // action (see F7: clearing bumps context_epoch server-side, which would
    // orphan the rest of a call's transcript if that call belonged here).
    final liveCallOwnsThisConversation =
        isRealtimeActive && realtime?.activeConversationKey == widget.conversationKey;

    // A fresh conversation has no list-derived title yet — derive one from
    // its first user turn (mirrors the server's own derivation) instead of
    // sitting on "Pip" forever. Both this and `initialTitle` are user/model
    // content, so they must never pass through the app's localized `Text`
    // (which runs every string through the Arabic UI phrasebook) — only the
    // static "Pip" fallback goes through the normal (translated) path.
    final contentTitle = widget.initialTitle ?? _deriveDisplayTitle(messages);

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradientAppBar(
        title: contentTitle ?? AppStrings.assistantTab,
        titleWidget: contentTitle == null
            ? null
            : material.Text(
                contentTitle,
                key: const ValueKey('assistant-header-title'),
                maxLines: 1,
                overflow: material.TextOverflow.ellipsis,
                textDirection: TextDirectionDetector.detect(contentTitle),
              ),
        titleLeading: const AssistantAvatar(
          key: ValueKey('assistant-header-avatar'),
          size: 36,
        ),
        actions: [
          IconButton(
            key: const ValueKey('assistant-clear-action'),
            tooltip: context.tr('Clear conversation'),
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed:
                provider.isSending ||
                    provider.isRecording ||
                    provider.isAwaitingVoiceReply ||
                    messages.isEmpty ||
                    liveCallOwnsThisConversation
                ? null
                : _confirmClear,
          ),
        ],
      ),
      body: SafeArea(
        top: false,
        child: Column(
          children: [
            if (isOffline) const _AssistantOfflineNotice(),
            if (provider.error != null)
              _AssistantErrorBanner(
                message: provider.error!,
                onRetry: () => _retryLast(provider),
              ),
            // The live call failing must say WHERE, not just that it failed —
            // "nothing happens" is undebuggable from a device. The detail line
            // carries the setup stage and exception text, nothing sensitive.
            // Scoped to THIS conversation (F5): a call that failed while
            // bound to a different conversation must not show here, and its
            // Retry must rebind to *this* screen's conversation, never the
            // controller's `start()` default.
            if (realtime != null &&
                realtime.state == RealtimeVoiceState.error &&
                realtime.errorMessage != null &&
                realtime.activeConversationKey == widget.conversationKey)
              _AssistantErrorBanner(
                key: const ValueKey('assistant-live-error'),
                message: realtime.errorMessage!,
                detail: realtime.errorDetail,
                onRetry: () =>
                    realtime.start(conversationKey: widget.conversationKey),
              ),
            Expanded(child: _buildBody(provider)),
            if (provider.isSending || provider.isAwaitingVoiceReply)
              const _AssistantThinkingIndicator(),
            _AssistantComposer(
              controller: _input,
              enabled: !isOffline,
              isSending: provider.isSending,
              onSend: _send,
              isRecording: provider.isRecording,
              // A live call holds the one iOS audio session, so recorded voice
              // and typing are gated on it exactly like an in-flight TTS reply.
              isVoiceBusy:
                  provider.isAwaitingVoiceReply ||
                  provider.isSpeaking ||
                  isRealtimeActive,
              onMicTap: _toggleMic,
              // Separate control with its own callback — the recorded-voice mic
              // button is request/response and must not be overloaded.
              //
              // Pip Live is parked behind `FeatureFlags.realtimeEnabled`
              // (lib/core/config/feature_flags.dart). The single choke point
              // is the shell never providing a `RealtimeVoiceController` when
              // the flag is off, which already makes `realtime` null here —
              // this explicit check is belt-and-braces so a stray provider
              // (e.g. from a test or a future call site) cannot resurrect the
              // button on its own.
              showLiveControl: realtime != null && FeatureFlags.realtimeEnabled,
              isLive: isRealtimeActive,
              canGoLive:
                  realtime != null &&
                  FeatureFlags.realtimeEnabled &&
                  (isRealtimeActive ||
                      (realtime.canStart &&
                          !provider.isSending &&
                          !provider.isRecording &&
                          !provider.isAwaitingVoiceReply &&
                          !provider.isSpeaking)),
              onLiveTap: realtime == null || !FeatureFlags.realtimeEnabled
                  ? null
                  : () => _toggleLive(realtime),
            ),
          ],
        ),
      ),
    );
  }

  /// The banner's retry re-sends the last *retryable* failed turn when there
  /// is one; otherwise it retries the history load that failed. A
  /// voice-originated failed turn is never retryable (its clip is already
  /// gone — see `AssistantProvider.canRetry`), so it is skipped here the
  /// same way the message bubble's own retry button skips it: falling
  /// through to `provider.load()` rather than leaving a dead button with no
  /// feedback.
  void _retryLast(AssistantProvider provider) {
    final retryable = provider.messages.where(provider.canRetry);
    if (retryable.isEmpty) {
      provider.load();
      return;
    }
    provider.retry(retryable.last);
  }

  Widget _buildBody(AssistantProvider provider) {
    if (provider.loadState == AssistantLoadState.loading &&
        provider.messages.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.messages.isEmpty) {
      return _buildEmptyState();
    }
    return ListView.builder(
      key: const ValueKey('assistant-message-list'),
      controller: _scroll,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceMd,
        vertical: AppSizes.spaceMd,
      ),
      itemCount: provider.messages.length,
      itemBuilder: (context, index) {
        final message = provider.messages[index];
        final isThisPlaying = provider.playingMessageId == message.id;
        return _AssistantMessageBubble(
          message: message,
          onRetry: provider.canRetry(message)
              ? () => provider.retry(message)
              : null,
          isPlaying: isThisPlaying && !provider.isPaused,
          isPaused: isThisPlaying && provider.isPaused,
          onPlayPause: message.hasAudio
              ? () {
                  if (isThisPlaying && !provider.isPaused) {
                    provider.pausePlayback();
                  } else if (isThisPlaying && provider.isPaused) {
                    provider.resumePlayback();
                  } else {
                    provider.playMessageAudio(message);
                  }
                }
              : null,
          onReplay: message.hasAudio
              ? () => provider.playMessageAudio(message)
              : null,
        );
      },
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.spaceLg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AssistantAvatar(
              key: ValueKey('assistant-empty-avatar'),
              size: 88,
              semanticLabel: 'ChickMark logo',
            ),
            const SizedBox(height: AppSizes.spaceMd),
            Text(
              AppStrings.assistantEmptyTitle,
              key: const ValueKey('assistant-empty-title'),
              style: AppTextStyles.sectionTitle,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSizes.spaceSm),
            Text(
              'Ask about flock performance, hatch results, or a recent audit.',
              style: AppTextStyles.caption,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantMessageBubble extends StatelessWidget {
  const _AssistantMessageBubble({
    required this.message,
    this.onRetry,
    this.isPlaying = false,
    this.isPaused = false,
    this.onPlayPause,
    this.onReplay,
  });

  final ChatMessage message;
  final VoidCallback? onRetry;

  /// True while this message's reply audio is actively sounding.
  final bool isPlaying;

  /// True while this message's reply audio is loaded but paused.
  final bool isPaused;

  /// Null when the message has no audio. Toggles play/pause/resume.
  final VoidCallback? onPlayPause;

  /// Null when the message has no audio. Restarts playback from the top.
  final VoidCallback? onReplay;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    // AlignmentDirectional, not Alignment: in Arabic the user's own turns must
    // sit on the reading-end side, so the layout mirrors with the locale.
    final alignment = isUser
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    // A voice-source turn (a realtime call transcript, per `source: "voice"`
    // in history) gets a slightly tinted bubble on top of its normal
    // role-based color, plus the mic icon built in `_buildMessageContent` —
    // together they mark it as "this is what was said on a call", not typed.
    final background = isUser
        ? (message.isVoice
              ? Color.lerp(AppColors.activeBg, AppColors.primary, 0.15)!
              : AppColors.activeBg)
        : (message.isVoice ? AppColors.surfaceVariant : AppColors.surface);
    final textColor = isUser ? AppColors.activeText : AppColors.textBody;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      child: Align(
        alignment: alignment,
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxWidth: MediaQuery.sizeOf(context).width * 0.82,
          ),
          child: _buildMessageContent(
            isUser: isUser,
            background: background,
            textColor: textColor,
            replayTooltip: context.tr('Replay'),
            voiceTranscriptLabel: context.tr('Voice transcript'),
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent({
    required bool isUser,
    required Color background,
    required Color textColor,
    required String replayTooltip,
    required String voiceTranscriptLabel,
  }) {
    final bubble = Container(
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        border: Border.all(color: AppColors.borderDefault),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceMd,
        vertical: AppSizes.spaceSm,
      ),
      child: message.isVoice
          ? Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.mic,
                  key: const ValueKey('assistant-voice-transcript-icon'),
                  size: 14,
                  color: textColor,
                ),
                const SizedBox(width: AppSizes.spaceXs),
                Flexible(
                  child: GptMarkdown(
                    message.text,
                    textDirection: TextDirectionDetector.detect(message.text),
                    style: AppTextStyles.body.copyWith(color: textColor),
                  ),
                ),
              ],
            )
          : GptMarkdown(
              message.text,
              textDirection: TextDirectionDetector.detect(message.text),
              style: AppTextStyles.body.copyWith(color: textColor),
            ),
    );

    final messageColumn = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        message.isVoice
            ? Semantics(label: voiceTranscriptLabel, child: bubble)
            : bubble,
        if (message.isSending)
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.spaceXs),
            child: Text('Sending', style: AppTextStyles.badgeLabel),
          ),
        if (message.isFailed)
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.spaceXs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Not sent',
                  style: AppTextStyles.badgeLabel.copyWith(
                    color: AppColors.statusError,
                  ),
                ),
                const SizedBox(width: AppSizes.spaceSm),
                if (onRetry != null)
                  TextButton(
                    onPressed: onRetry,
                    child: const Text(AppStrings.retry),
                  ),
              ],
            ),
          ),
        if (message.hasAudio)
          Padding(
            padding: const EdgeInsets.only(top: AppSizes.spaceXs),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton(
                  key: const ValueKey('assistant-reply-play-pause'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: isPlaying ? 'Pause' : (isPaused ? 'Resume' : 'Play'),
                  icon: Icon(
                    isPlaying ? Icons.pause_circle : Icons.play_circle,
                    size: 26,
                    color: AppColors.primary,
                  ),
                  onPressed: onPlayPause,
                ),
                const SizedBox(width: AppSizes.spaceXs),
                IconButton(
                  key: const ValueKey('assistant-reply-replay'),
                  visualDensity: VisualDensity.compact,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: replayTooltip,
                  icon: const Icon(Icons.replay, size: 20),
                  color: AppColors.textTertiary,
                  onPressed: onReplay,
                ),
              ],
            ),
          ),
      ],
    );
    if (isUser) return messageColumn;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const AssistantAvatar(
          key: ValueKey('assistant-message-avatar'),
          size: 30,
        ),
        const SizedBox(width: AppSizes.spaceSm),
        Flexible(child: messageColumn),
      ],
    );
  }
}

class _AssistantThinkingIndicator extends StatelessWidget {
  const _AssistantThinkingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: AlignmentDirectional.centerStart,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSizes.spaceLg,
          0,
          AppSizes.spaceLg,
          AppSizes.spaceSm,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AssistantAvatar(
              key: ValueKey('assistant-thinking-avatar'),
              size: 30,
            ),
            const SizedBox(width: AppSizes.spaceSm),
            const SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            const SizedBox(width: AppSizes.spaceSm),
            Text(
              AppStrings.assistantThinking,
              key: const ValueKey('assistant-thinking'),
              style: AppTextStyles.caption,
            ),
          ],
        ),
      ),
    );
  }
}

class _AssistantOfflineNotice extends StatelessWidget {
  const _AssistantOfflineNotice();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      color: AppColors.statusNeutralBg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.cloud_off_outlined,
            size: 16,
            color: AppColors.statusNeutralText,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Text(
              'The assistant needs a connection. Your other work still saves offline.',
              style: AppTextStyles.caption,
            ),
          ),
        ],
      ),
    );
  }
}

class _AssistantErrorBanner extends StatelessWidget {
  const _AssistantErrorBanner({
    super.key,
    required this.message,
    required this.onRetry,
    this.detail,
  });

  final String message;
  final VoidCallback onRetry;

  /// Optional diagnostic line (setup stage + exception text) rendered small
  /// and selectable under the message, so a failure on a device can be copied
  /// and reported verbatim.
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const ValueKey('assistant-error-banner'),
      width: double.infinity,
      color: AppColors.statusErrorBg,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSizes.spaceLg,
        vertical: AppSizes.spaceSm,
      ),
      child: Row(
        children: [
          const Icon(
            Icons.error_outline,
            size: 16,
            color: AppColors.statusError,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  message,
                  style: AppTextStyles.caption.copyWith(
                    color: AppColors.statusError,
                  ),
                ),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  SelectableText(
                    detail!,
                    key: const ValueKey('assistant-error-detail'),
                    // Diagnostics are left-to-right technical text even when
                    // the surrounding locale is Arabic.
                    textDirection: TextDirection.ltr,
                    style: AppTextStyles.caption.copyWith(
                      color: AppColors.statusError,
                      fontSize: 10,
                      fontFamily: 'monospace',
                    ),
                  ),
                ],
              ],
            ),
          ),
          TextButton(
            key: const ValueKey('assistant-error-retry'),
            onPressed: onRetry,
            child: const Text(AppStrings.retry),
          ),
        ],
      ),
    );
  }
}

class _AssistantComposer extends StatelessWidget {
  const _AssistantComposer({
    required this.controller,
    required this.enabled,
    required this.isSending,
    required this.onSend,
    required this.isRecording,
    required this.isVoiceBusy,
    required this.onMicTap,
    this.showLiveControl = false,
    this.isLive = false,
    this.canGoLive = false,
    this.onLiveTap,
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;
  final bool isRecording;
  final bool isVoiceBusy;
  final VoidCallback onMicTap;

  /// Whether a live-call control is available at all (a
  /// [RealtimeVoiceController] is registered above this screen).
  final bool showLiveControl;

  /// Whether a live call is currently up.
  final bool isLive;

  /// Whether the live control is tappable right now.
  final bool canGoLive;

  /// The live control's own callback. Never [onMicTap]: the mic button drives
  /// the request/response recorded-voice turn, which is a different feature
  /// with a different transport.
  final VoidCallback? onLiveTap;

  @override
  Widget build(BuildContext context) {
    final canType = enabled && !isSending && !isRecording && !isVoiceBusy;
    final canRecord = enabled && !isSending && !isVoiceBusy;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(top: BorderSide(color: AppColors.borderDefault)),
      ),
      padding: const EdgeInsets.all(AppSizes.spaceSm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const ValueKey('assistant-input'),
              controller: controller,
              enabled: canType,
              minLines: 1,
              maxLines: 4,
              keyboardType: TextInputType.multiline,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: enabled
                    ? AppStrings.assistantComposerHint
                    : 'Unavailable while offline',
                border: const OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: AppSizes.spaceSm),
          IconButton(
            key: const ValueKey('assistant-mic'),
            tooltip: context.tr(
              isRecording ? 'Stop recording' : 'Ask by voice',
            ),
            icon: Icon(isRecording ? Icons.stop_circle : Icons.mic),
            color: isRecording ? AppColors.statusError : AppColors.primary,
            onPressed: canRecord ? onMicTap : null,
          ),
          if (showLiveControl) ...[
            const SizedBox(width: AppSizes.spaceSm),
            IconButton(
              key: const ValueKey('assistant-live'),
              tooltip: context.tr(isLive ? 'Return to Pip Live' : 'Talk live'),
              icon: const Icon(Icons.graphic_eq),
              color: AppColors.primary,
              onPressed: (enabled || isLive) && canGoLive ? onLiveTap : null,
            ),
          ],
          const SizedBox(width: AppSizes.spaceSm),
          IconButton(
            key: const ValueKey('assistant-send'),
            tooltip: context.tr('Send message'),
            icon: const Icon(Icons.send),
            color: AppColors.primary,
            onPressed: canType ? onSend : null,
          ),
        ],
      ),
    );
  }
}
