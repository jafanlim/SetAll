import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:uuid/uuid.dart';

import '../../../core/config/auth_config.dart';
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

  Future<void> sendMessage(String userText, {String mode = 'chat'}) async {
    final current = state.valueOrNull ?? const InsightsState();
    if (userText.trim().isEmpty) return;

    final repo = ref.read(setAllRepositoryProvider);

    // Build and persist user message.
    final userMsg = AiChatMessage.create(
      sessionId: current.sessionId,
      role: AiChatRole.user,
      content: userText.trim(),
      userId: repo.currentUserId,
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

      // ARCH-01: Migrated from supabase.functions.invoke — no JWT, no auth header.
      // FEAT-06-P3: Canvas mode is live — pass mode:'canvas' to this function.
      // Netlify fn returns: {summary, insights, charts[], actions[]} at 8192t.
      // Remaining TODO: wire _CanvasPanel in insights_screen.dart to this response.
      final historyStr = history
          .map((m) => '${m['role']}: ${m['content']}')
          .join('\n');
      final query = 'User: ${userText.trim()}'
          '\n\nFinancial data (last 30 days):'
          '\nTotal Expenses: \$${analyticsData.totalSpend.toStringAsFixed(2)}'
          '\nDaily Burn: \$${analyticsData.burnRate.toStringAsFixed(2)}'
          '\nTotal Income: \$${analyticsData.totalIncome.toStringAsFixed(2)}'
          '\nNet: \$${analyticsData.netFlow.toStringAsFixed(2)}'
          '\nTop Categories: $topCatsStr'
          '\n\nRecent 20 transactions:\n$recentRows'
          '${historyStr.isNotEmpty ? '\n\nRecent chat:\n$historyStr' : ''}';

      final httpRes = await http.post(
        Uri.parse(AuthConfig.netlifyAiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'query': query, 'mode': mode}),
      );

      if (httpRes.statusCode != 200) {
        debugPrint('[AI] Netlify returned ${httpRes.statusCode}: ${httpRes.body.substring(0, httpRes.body.length.clamp(0, 200))}');
        throw Exception('AI service error (${httpRes.statusCode})');
      }

      final data   = jsonDecode(httpRes.body) as Map<String, dynamic>?;
      final report = jsonDecode(data?['report'] as String? ?? '{}') as Map<String, dynamic>?;
      final replyText = (report?['summary'] as String?) ?? 'No response.';

      // Detect if response includes canvas data (charts array from canvas mode).
      final hasCanvas = report?['charts'] != null && mode == 'canvas';
      final assistantContent = hasCanvas
          ? '$replyText\n__CANVAS__:${jsonEncode(report)}'
          : replyText;

      final assistantMsg = AiChatMessage.create(
        sessionId: current.sessionId,
        role: AiChatRole.assistant,
        content: assistantContent,
        isCanvas: hasCanvas,
        userId: repo.currentUserId,
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
