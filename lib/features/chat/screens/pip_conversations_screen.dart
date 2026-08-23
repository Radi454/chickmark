import 'package:flutter/material.dart' as material;
import 'package:hatchaudit/localized_material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../../../core/constants/app_colors.dart';
import '../../../core/constants/app_sizes.dart';
import '../../../core/constants/app_strings.dart';
import '../../../core/theme/app_text_styles.dart';
import '../../../core/theme/gradient_app_bar.dart';
import '../../../core/utils/date_utils.dart';
import '../../../core/utils/text_direction_detector.dart';
import '../models/pip_conversation_summary.dart';
import '../providers/pip_conversations_provider.dart';

/// Longest preview shown when a conversation has no server-derived title
/// (used as the title line's fallback source instead).
const int _titleFallbackPreviewChars = 40;

/// Lists every Pip conversation the caller has, grouped by the local day
/// its most recent activity landed on. Tapping a tile or the "New
/// conversation" action hands off to [openConversation] — this screen owns
/// no navigation itself, only the list and the fresh-key minting for a new
/// thread.
class PipConversationsScreen extends StatelessWidget {
  const PipConversationsScreen({
    super.key,
    this.provider,
    this.openConversation,
    this.loadOnInit = true,
  });

  /// Test seam: when supplied, used directly instead of the one the shell
  /// registers above this screen via `ChangeNotifierProvider`.
  final PipConversationsProvider? provider;

  /// Opens one conversation (existing or freshly minted). The screen awaits
  /// this before refreshing its list, so the caller should not resolve until
  /// the pushed conversation route has been popped.
  final Future<void> Function(String conversationKey, String? title)?
  openConversation;

  /// Lets a test pump the screen without firing the initial load.
  final bool loadOnInit;

  @override
  Widget build(BuildContext context) {
    final child = _PipConversationsView(
      loadOnInit: loadOnInit,
      openConversation: openConversation,
    );
    final injected = provider;
    if (injected == null) return child;
    return ChangeNotifierProvider<PipConversationsProvider>.value(
      value: injected,
      child: child,
    );
  }
}

class _PipConversationsView extends StatefulWidget {
  const _PipConversationsView({
    required this.loadOnInit,
    this.openConversation,
  });

  final bool loadOnInit;
  final Future<void> Function(String conversationKey, String? title)?
  openConversation;

  @override
  State<_PipConversationsView> createState() => _PipConversationsViewState();
}

class _PipConversationsViewState extends State<_PipConversationsView> {
  @override
  void initState() {
    super.initState();
    if (widget.loadOnInit) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        context.read<PipConversationsProvider>().load();
      });
    }
  }

  Future<void> _open(String conversationKey, String? title) async {
    final callback = widget.openConversation;
    if (callback == null) return;
    await callback(conversationKey, title);
    if (!mounted) return;
    await context.read<PipConversationsProvider>().refresh();
  }

  Future<void> _startNewConversation() async {
    // 'app' is the legacy single-thread key; every new conversation gets its
    // own 'app:<uuid>' key so the server creates a fresh row for it on the
    // first send. No title yet — the server derives one from the first user
    // message once there is one.
    final key = 'app:${const Uuid().v4()}';
    await _open(key, null);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PipConversationsProvider>();

    return Scaffold(
      key: const ValueKey('pip-conversations-screen'),
      backgroundColor: AppColors.background,
      appBar: const GradientAppBar(title: AppStrings.assistantTab),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('pip-new-conversation'),
        heroTag: 'pip-new-conversation',
        onPressed: _startNewConversation,
        icon: const Icon(Icons.add_comment_outlined),
        label: const Text('New conversation'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: _buildBody(provider),
    );
  }

  Widget _buildBody(PipConversationsProvider provider) {
    if (provider.isLoading && provider.conversations.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (provider.loadState == PipConversationsLoadState.error) {
      return _PipConversationsErrorState(
        message:
            provider.error ?? 'Something went wrong. Please try again.',
        onRetry: () => provider.refresh(),
      );
    }
    if (provider.conversations.isEmpty) {
      return RefreshIndicator(
        onRefresh: provider.refresh,
        child: ListView(
          children: const [
            SizedBox(height: AppSizes.spaceXxl),
            _PipConversationsEmptyState(),
          ],
        ),
      );
    }

    final grouped = groupConversationsByDay(provider.conversations, DateTime.now());
    final items = <_PipListItem>[];
    for (final bucket in PipConversationDayBucket.values) {
      final bucketConversations = grouped[bucket]!;
      if (bucketConversations.isEmpty) continue;
      items.add(_PipListItem.header(bucket));
      for (final conversation in bucketConversations) {
        items.add(_PipListItem.conversation(conversation));
      }
    }

    return RefreshIndicator(
      onRefresh: provider.refresh,
      child: ListView.builder(
        key: const ValueKey('pip-conversation-list'),
        padding: const EdgeInsets.fromLTRB(
          AppSizes.spaceMd,
          AppSizes.spaceSm,
          AppSizes.spaceMd,
          AppSizes.fabBottomPadding,
        ),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          if (item.bucket != null) {
            return _PipSectionHeader(bucket: item.bucket!);
          }
          final summary = item.summary!;
          return _PipConversationTile(
            summary: summary,
            onTap: () => _open(summary.conversationKey, summary.title),
          );
        },
      ),
    );
  }
}

/// Either a section header or a conversation row in the flattened list —
/// `ListView.builder` needs one item type, so headers are interleaved as
/// their own entries rather than living in a separate `Sliver`.
class _PipListItem {
  const _PipListItem.header(this.bucket) : summary = null;
  const _PipListItem.conversation(this.summary) : bucket = null;

  final PipConversationDayBucket? bucket;
  final PipConversationSummary? summary;
}

class _PipSectionHeader extends StatelessWidget {
  const _PipSectionHeader({required this.bucket});

  final PipConversationDayBucket bucket;

  String get _label {
    switch (bucket) {
      case PipConversationDayBucket.today:
        return 'Today';
      case PipConversationDayBucket.yesterday:
        return 'Yesterday';
      case PipConversationDayBucket.earlier:
        return 'Earlier';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSizes.spaceSm,
        AppSizes.spaceMd,
        AppSizes.spaceSm,
        AppSizes.spaceXs,
      ),
      child: Text(_label, style: AppTextStyles.subtitle),
    );
  }
}

class _PipConversationTile extends StatelessWidget {
  const _PipConversationTile({required this.summary, required this.onTap});

  final PipConversationSummary summary;
  final VoidCallback onTap;

  bool get _hasServerTitle =>
      summary.title != null && summary.title!.trim().isNotEmpty;

  String? get _trimmedPreview {
    final preview = summary.lastMessageText?.trim();
    return (preview == null || preview.isEmpty) ? null : preview;
  }

  /// True when the title line is real conversation content (a server title
  /// or a preview snippet standing in for one) rather than the fixed
  /// "Voice conversation" fallback label — only content gets per-message
  /// direction detection; the fallback label is a static app string and
  /// follows the ambient locale direction like any other UI label.
  bool get _titleIsContent => _hasServerTitle || _trimmedPreview != null;

  /// Raw (untranslated) title text. `Text` translates the fixed fallback
  /// label itself; a server title or preview snippet is user/model content
  /// and is never run through the app's static `_ar` phrasebook.
  String get _titleText {
    if (_hasServerTitle) return summary.title!;
    final preview = _trimmedPreview;
    if (preview != null) {
      return preview.length > _titleFallbackPreviewChars
          ? '${preview.substring(0, _titleFallbackPreviewChars)}…'
          : preview;
    }
    return 'Voice conversation';
  }

  /// Null when the preview text is already shown as the title line (no
  /// server title, so the fallback text is doing double duty) — showing it
  /// twice would be redundant.
  String? get _previewText => _hasServerTitle ? _trimmedPreview : null;

  String _timeLabel() {
    final timestamp = (summary.lastMessageAt ?? summary.updatedAt).toLocal();
    final now = DateTime.now();
    final sameDay =
        timestamp.year == now.year &&
        timestamp.month == now.month &&
        timestamp.day == now.day;
    if (sameDay) {
      return '${_twoDigits(timestamp.hour)}:${_twoDigits(timestamp.minute)}';
    }
    return HatchDateUtils.formatDisplayDate(timestamp);
  }

  static String _twoDigits(int value) => value.toString().padLeft(2, '0');

  @override
  Widget build(BuildContext context) {
    final title = _titleText;
    final preview = _previewText;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSizes.spaceSm),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(AppSizes.cardRadius),
        child: InkWell(
          key: ValueKey('pip-conversation-tile-${summary.conversationKey}'),
          onTap: onTap,
          borderRadius: BorderRadius.circular(AppSizes.cardRadius),
          child: Container(
            decoration: BoxDecoration(
              border: Border.all(color: AppColors.borderDefault),
              borderRadius: BorderRadius.circular(AppSizes.cardRadius),
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSizes.spaceMd,
              vertical: AppSizes.spaceMd,
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // `_titleIsContent` picks the widget, not just the
                      // `textDirection`: real conversation content (a server
                      // title or a preview snippet) must never pass through
                      // the app's localized `Text`, which runs every string
                      // through the Arabic UI phrasebook — a title that
                      // happens to equal a UI label (e.g. "Refresh") would
                      // otherwise render as that label's Arabic translation.
                      // Only the static "Voice conversation" fallback is
                      // actual UI copy and is meant to be translated.
                      _titleIsContent
                          ? material.Text(
                              title,
                              maxLines: 1,
                              overflow: material.TextOverflow.ellipsis,
                              textDirection: TextDirectionDetector.detect(
                                title,
                              ),
                              style: AppTextStyles.title,
                            )
                          : Text(
                              title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: AppTextStyles.title,
                            ),
                      if (preview != null) ...[
                        const SizedBox(height: 2),
                        // Always content (see `_previewText`'s doc): never
                        // translated, same reasoning as the title above.
                        material.Text(
                          preview,
                          maxLines: 1,
                          overflow: material.TextOverflow.ellipsis,
                          textDirection: TextDirectionDetector.detect(
                            preview,
                          ),
                          style: AppTextStyles.caption,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: AppSizes.spaceSm),
                Text(
                  _timeLabel(),
                  style: AppTextStyles.caption,
                  textDirection: TextDirection.ltr,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PipConversationsEmptyState extends StatelessWidget {
  const _PipConversationsEmptyState();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(AppSizes.spaceXl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: AppColors.activeBg,
              borderRadius: BorderRadius.circular(AppSizes.iconRadius),
            ),
            child: const Icon(
              Icons.forum_outlined,
              color: AppColors.primary,
              size: 28,
            ),
          ),
          const SizedBox(height: AppSizes.spaceLg),
          const Text('No conversations yet', style: AppTextStyles.title),
          const SizedBox(height: AppSizes.spaceSm),
          const Text(
            'Start your first conversation with Pip',
            textAlign: TextAlign.center,
            style: AppTextStyles.caption,
          ),
        ],
      ),
    );
  }
}

class _PipConversationsErrorState extends StatelessWidget {
  const _PipConversationsErrorState({
    required this.message,
    required this.onRetry,
  });

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSizes.spaceXl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.error_outline,
              color: AppColors.statusError,
              size: 32,
            ),
            const SizedBox(height: AppSizes.spaceMd),
            Text(
              message,
              textAlign: TextAlign.center,
              style: AppTextStyles.body,
            ),
            const SizedBox(height: AppSizes.spaceMd),
            FilledButton(
              key: const ValueKey('pip-conversations-retry'),
              onPressed: onRetry,
              child: const Text(AppStrings.retry),
            ),
          ],
        ),
      ),
    );
  }
}
