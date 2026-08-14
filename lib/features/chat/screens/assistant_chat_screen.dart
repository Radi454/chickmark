import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/network/network_status_monitor.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../models/chat_message.dart';
import '../providers/assistant_provider.dart';
import '../widgets/assistant_avatar.dart';

/// In-app assistant chat.
///
/// [provider] is a test seam: when supplied it is used directly instead of the
/// one the shell registers above this screen, so a widget test can drive the
/// conversation from a fake port. [loadOnInit] lets a test pump the screen
/// without firing the history request.
class AssistantChatScreen extends StatelessWidget {
  const AssistantChatScreen({
    super.key,
    this.provider,
    this.loadOnInit = true,
  });

  final AssistantProvider? provider;
  final bool loadOnInit;

  @override
  Widget build(BuildContext context) {
    final injected = provider;
    if (injected == null) {
      return _AssistantChatView(loadOnInit: loadOnInit);
    }
    return ChangeNotifierProvider<AssistantProvider>.value(
      value: injected,
      child: _AssistantChatView(loadOnInit: loadOnInit),
    );
  }
}

class _AssistantChatView extends StatefulWidget {
  const _AssistantChatView({required this.loadOnInit});

  final bool loadOnInit;

  @override
  State<_AssistantChatView> createState() => _AssistantChatViewState();
}

class _AssistantChatViewState extends State<_AssistantChatView> {
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  int _lastMessageCount = 0;

  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<AssistantProvider>().load();
      });
    }
  }

  @override
  void dispose() {
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
    final isOffline = context.select<NetworkStatusMonitor, bool>(
      (monitor) => monitor.isOffline,
    );
    final messages = provider.messages;
    if (messages.length != _lastMessageCount) {
      _lastMessageCount = messages.length;
      _scrollToNewest();
    }

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: GradientAppBar(
        title: AppStrings.assistantTab,
        titleLeading: const AssistantAvatar(
          key: ValueKey('assistant-header-avatar'),
          size: 36,
        ),
        actions: [
          IconButton(
            key: const ValueKey('assistant-clear-action'),
            tooltip: 'Clear conversation',
            icon: const Icon(Icons.delete_sweep_outlined),
            onPressed: provider.isSending || messages.isEmpty
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
            Expanded(child: _buildBody(provider)),
            if (provider.isSending || provider.isAwaitingVoiceReply)
              const _AssistantThinkingIndicator(),
            _AssistantComposer(
              controller: _input,
              enabled: !isOffline,
              isSending: provider.isSending,
              onSend: _send,
              isRecording: provider.isRecording,
              isVoiceBusy: provider.isAwaitingVoiceReply || provider.isSpeaking,
              onMicTap: _toggleMic,
            ),
          ],
        ),
      ),
    );
  }

  /// The banner's retry re-sends the last failed turn when there is one;
  /// otherwise it retries the history load that failed.
  void _retryLast(AssistantProvider provider) {
    final failed = provider.messages.where((message) => message.isFailed);
    if (failed.isEmpty) {
      provider.load();
      return;
    }
    provider.retry(failed.last);
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
        return _AssistantMessageBubble(
          message: message,
          onRetry: message.isFailed ? () => provider.retry(message) : null,
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
  const _AssistantMessageBubble({required this.message, this.onRetry});

  final ChatMessage message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final isUser = message.isUser;
    // AlignmentDirectional, not Alignment: in Arabic the user's own turns must
    // sit on the reading-start side, so the layout mirrors with the locale.
    final alignment = isUser
        ? AlignmentDirectional.centerEnd
        : AlignmentDirectional.centerStart;
    final background = isUser ? AppColors.activeBg : AppColors.surface;
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
          ),
        ),
      ),
    );
  }

  Widget _buildMessageContent({
    required bool isUser,
    required Color background,
    required Color textColor,
  }) {
    final messageColumn = Column(
      crossAxisAlignment: isUser
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        Container(
          decoration: BoxDecoration(
            color: background,
            borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            border: Border.all(color: AppColors.borderDefault),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSizes.spaceMd,
            vertical: AppSizes.spaceSm,
          ),
          child: SelectableText(
            message.text,
            style: AppTextStyles.body.copyWith(color: textColor),
          ),
        ),
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
  const _AssistantErrorBanner({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

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
            child: Text(
              message,
              style: AppTextStyles.caption.copyWith(
                color: AppColors.statusError,
              ),
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
  });

  final TextEditingController controller;
  final bool enabled;
  final bool isSending;
  final VoidCallback onSend;
  final bool isRecording;
  final bool isVoiceBusy;
  final VoidCallback onMicTap;

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
            tooltip: isRecording ? 'Stop recording' : 'Ask by voice',
            icon: Icon(isRecording ? Icons.stop_circle : Icons.mic),
            color: isRecording ? AppColors.statusError : AppColors.primary,
            onPressed: canRecord ? onMicTap : null,
          ),
          const SizedBox(width: AppSizes.spaceSm),
          IconButton(
            key: const ValueKey('assistant-send'),
            tooltip: 'Send message',
            icon: const Icon(Icons.send),
            color: AppColors.primary,
            onPressed: canType ? onSend : null,
          ),
        ],
      ),
    );
  }
}
