import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:uuid/uuid.dart';

import '../../../core/providers/setall_providers.dart';
import '../../analytics/presentation/screens/analytics_screen.dart'
    show analyticsDataProvider;
import '../models/ai_chat_message.dart';

// ---------------------------------------------------------------------------
// State
// ---------------------------------------------------------------------------

class InsightsState {
  const InsightsState({
    this.messages = const [],
    this.sessionId = '',
    this.sessionIds = const [],
    this.isLoading = false,
    this.error,
  });

  final List<AiChatMessage> messages;
  final String sessionId;
  final List<String> sessionIds;
  final bool isLoading;
  final String? error;

  InsightsState copyWith({
    List<AiChatMessage>? messages,
    String? sessionId,
    List<String>? sessionIds,
    bool? isLoading,
    String? error,
    bool clearError = false,
  }) {
    return InsightsState(
      messages: messages ?? this.messages,
      sessionId: sessionId ?? this.sessionId,
      sessionIds: sessionIds ?? this.sessionIds,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
    );
  }
}

// ---------------------------------------------------------------------------
// Notifier
// ---------------------------------------------------------------------------

class InsightsNotifier extends AsyncNotifier<InsightsState> {
  @override
  Future<InsightsState> build() async {
    final repo = ref.read(setAllRepositoryProvider);
    final sessionIds = await repo.getChatSessionIds();
    final sessionId = sessionIds.isNotEmpty ? sessionIds.first : const Uuid().v4();
    final messages = sessionIds.isNotEmpty
        ? await repo.getChatHistory(sessionId)
        : <AiChatMessage>[];
    return InsightsState(
      messages: messages,
      sessionId: sessionId,
      sessionIds: sessionIds,
    );
  }

  Future<void> newSession() async {
    final newId = const Uuid().v4();
    final repo = ref.read(setAllRepositoryProvider);
    final sessionIds = await repo.getChatSessionIds();
    state = AsyncData(
      (state.valueOrNull ?? const InsightsState()).copyWith(
        messages: [],
        sessionId: newId,
        sessionIds: sessionIds,
        clearError: true,
      ),
    );
  }

  Future<void> loadSession(String sessionId) async {
    final repo = ref.read(setAllRepositoryProvider);
    final messages = await repo.getChatHistory(sessionId);
    state = AsyncData(
      (state.valueOrNull ?? const InsightsState()).copyWith(
        messages: messages,
        sessionId: sessionId,
        clearError: true,
      ),
    );
  }

  Future<void> sendMessage(String userText) async {
    final current = state.valueOrNull ?? const InsightsState();
    if (userText.trim().isEmpty) return;

    final repo = ref.read(setAllRepositoryProvider);

    // Build and persist user message.
    final userMsg = AiChatMessage.create(
      sessionId: current.sessionId,
      role: AiChatRole.user,
      content: userText.trim(),
    );
    await repo.insertChatMessage(userMsg);

    final updatedMessages = [...current.messages, userMsg];
    state = AsyncData(current.copyWith(
      messages: updatedMessages,
      isLoading: true,
      clearError: true,
    ));

    try {
      // Build financial context from analyticsDataProvider.
      final analyticsData = await ref.read(analyticsDataProvider.future);
      final topCats = analyticsData.categoryTotals.entries.toList()
        ..sort((a, b) => b.value.compareTo(a.value));
      final topCatsStr = topCats
          .take(5)
          .map((e) => '${e.key}: \$${e.value.toStringAsFixed(2)}')
          .join(', ');
      final recentRows = analyticsData.allExpenses
          .take(20)
          .map((e) =>
              '${e.createdAt?.substring(0, 10) ?? ''} ${e.category} ${e.currency} ${e.amount}')
          .join('\n');

      final financialContext = {
        'totalSpending': analyticsData.totalSpend,
        'dailyBurn': analyticsData.burnRate,
        'totalIncome': analyticsData.totalIncome,
        'net': analyticsData.netFlow,
        'topCategories': topCatsStr,
        'recentRows': recentRows,
      };

      // Build history (last 10 messages before current).
      final history = updatedMessages
          .where((m) => m.id != userMsg.id)
          .toList()
          .reversed
          .take(10)
          .toList()
          .reversed
          .map((m) => {
                'role': m.role == AiChatRole.user ? 'user' : 'assistant',
                'content': m.content,
              })
          .toList();

      final client = Supabase.instance.client;
      // TODO(FEAT-06-P3): add canvas mode to edge function once FEAT-02 Ph.2 is built
      final res = await client.functions.invoke('ai-analyst', body: {
        'message': userText.trim(),
        'history': history,
        'context': financialContext,
        'mode': 'canvas',
      });

      final data = res.data as Map<String, dynamic>?;
      final structured = data?['structured'] as Map<String, dynamic>?;
      final replyText = (structured?['summary'] as String?)
          ?? (data?['reply'] as String?)
          ?? 'No response.';

      // Detect if response includes canvas (chart) data.
      final hasCanvas = structured?['chartData'] != null;
      final assistantContent = hasCanvas
          ? '$replyText\n__CANVAS__:${structured!['chartData'].toString()}'
          : replyText;

      final assistantMsg = AiChatMessage.create(
        sessionId: current.sessionId,
        role: AiChatRole.assistant,
        content: assistantContent,
        isCanvas: hasCanvas,
      );
      await repo.insertChatMessage(assistantMsg);

      // Refresh session list after new messages.
      final sessionIds = await repo.getChatSessionIds();

      state = AsyncData(current.copyWith(
        messages: [...updatedMessages, assistantMsg],
        sessionIds: sessionIds,
        isLoading: false,
      ));
    } catch (e) {
      state = AsyncData(current.copyWith(
        messages: updatedMessages,
        isLoading: false,
        error: 'Failed to get response. Please try again.',
      ));
    }
  }
}

// ---------------------------------------------------------------------------
// Provider
// ---------------------------------------------------------------------------

final insightsProvider =
    AsyncNotifierProvider<InsightsNotifier, InsightsState>(
  InsightsNotifier.new,
);
