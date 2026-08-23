import 'package:flutter/foundation.dart';

import '../../../services/supabase/assistant_chat_service.dart';
import '../models/pip_conversation_summary.dart';

enum PipConversationsLoadState { uninitialized, loading, loaded, error }

/// Buckets a conversation falls into on the conversations list, computed
/// from [PipConversationSummary.updatedAt] against the local calendar date
/// at the moment of grouping.
enum PipConversationDayBucket { today, yesterday, earlier }

/// Splits [conversations] into day buckets by the *local* calendar date of
/// each conversation's [PipConversationSummary.updatedAt], compared against
/// [now] (also read as local time). Pure and independent of any provider
/// state so it is unit-testable on its own: pass a fixed [now] to pin the
/// "today" boundary in a test.
///
/// Within each bucket, conversations keep the order they arrived in (the
/// server already sorts by `updatedAt desc`).
Map<PipConversationDayBucket, List<PipConversationSummary>>
groupConversationsByDay(List<PipConversationSummary> conversations, DateTime now) {
  final today = DateTime(now.year, now.month, now.day);
  final yesterday = today.subtract(const Duration(days: 1));

  final grouped = <PipConversationDayBucket, List<PipConversationSummary>>{
    PipConversationDayBucket.today: [],
    PipConversationDayBucket.yesterday: [],
    PipConversationDayBucket.earlier: [],
  };

  for (final conversation in conversations) {
    final local = conversation.updatedAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    final PipConversationDayBucket bucket;
    if (day == today) {
      bucket = PipConversationDayBucket.today;
    } else if (day == yesterday) {
      bucket = PipConversationDayBucket.yesterday;
    } else {
      bucket = PipConversationDayBucket.earlier;
    }
    grouped[bucket]!.add(conversation);
  }

  return grouped;
}

/// Conversation-list state for the Pip conversations screen.
///
/// The provider only ever knows about summaries — never a full transcript.
/// Opening a conversation is entirely the screen's concern (it pushes a
/// separate [AssistantProvider]-backed route); this provider just lists what
/// exists.
class PipConversationsProvider extends ChangeNotifier {
  PipConversationsProvider({AssistantChatPort? port})
    : _port = port ?? AssistantChatService();

  final AssistantChatPort _port;

  List<PipConversationSummary> _conversations = const [];
  PipConversationsLoadState _loadState = PipConversationsLoadState.uninitialized;
  String? _error;
  bool _disposed = false;

  List<PipConversationSummary> get conversations => _conversations;
  PipConversationsLoadState get loadState => _loadState;
  bool get isLoading => _loadState == PipConversationsLoadState.loading;
  String? get error => _error;

  /// Loads the list for the first time. A no-op if already loading or
  /// already loaded — callers that want a fresh fetch use [refresh].
  Future<void> load() async {
    if (_loadState == PipConversationsLoadState.loading) return;
    if (_loadState == PipConversationsLoadState.loaded) return;
    await _fetch();
  }

  /// Re-fetches the list regardless of current state — used by
  /// pull-to-refresh and after returning from a pushed conversation.
  Future<void> refresh() => _fetch();

  Future<void> _fetch() async {
    _loadState = PipConversationsLoadState.loading;
    _error = null;
    _notify();
    try {
      _conversations = await _port.listConversations();
      _loadState = PipConversationsLoadState.loaded;
    } on AssistantChatException catch (error) {
      _error = error.message;
      _loadState = PipConversationsLoadState.error;
    } catch (_) {
      _error = 'Could not load your conversations. Please try again.';
      _loadState = PipConversationsLoadState.error;
    }
    _notify();
  }

  void _notify() {
    if (_disposed) return;
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
