import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
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
    this.pendingAction,
  });

  final List<AiChatMessage> messages;
  final String sessionId;
  final List<String> sessionIds;
  final bool isLoading;
  final String? error;
  /// Parsed action suggestion from the AI — non-null triggers confirmation sheet.
  final Map<String, dynamic>? pendingAction;

  InsightsState copyWith({
    List<AiChatMessage>? messages,
    String? sessionId,
    List<String>? sessionIds,
    bool? isLoading,
    String? error,
    bool clearError = false,
    Map<String, dynamic>? pendingAction,
    bool clearAction = false,
  }) {
    return InsightsState(
      messages: messages ?? this.messages,
      sessionId: sessionId ?? this.sessionId,
      sessionIds: sessionIds ?? this.sessionIds,
      isLoading: isLoading ?? this.isLoading,
      error: clearError ? null : (error ?? this.error),
      pendingAction: clearAction ? null : (pendingAction ?? this.pendingAction),
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

  void clearAction() {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.copyWith(clearAction: true));
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
      // Build financial context.
      final analyticsData = await ref.read(analyticsDataProvider.future);
      final baseCurrency = await ref.read(baseCurrencyProvider.future);

      // Build history: last K=8 turns BEFORE the current user message, each capped at 600 chars.
      const int kHistoryTurns = 8;
      const int kMsgCap = 600;
      final history = updatedMessages
          .where((m) => m.id != userMsg.id)
          .toList()
          .reversed
          .take(kHistoryTurns)
          .toList()
          .reversed
          .map((m) => {
                'role': m.role == AiChatRole.user ? 'user' : 'assistant',
                'content': m.content.length > kMsgCap
                    ? m.content.substring(0, kMsgCap)
                    : m.content,
              })
          .toList();

      // ARCH-01: Migrated from supabase.functions.invoke.
      // FEAT-06-P3: Canvas mode is live — pass mode:'canvas' to this function.
      // Netlify fn returns: {summary, insights, charts[], actions[]} at 8192t.
      // Chat: query = bare user message; structured context{} sent separately.
      // Canvas: data inlined in query (unchanged path).
      final isCanvas = mode == 'canvas';

      // Build structured grounding context (chat only — no user PII, no server URLs).
      Map<String, dynamic>? contextPayload;
      if (!isCanvas) {
        final walletTotals = await repo.getWalletEntryTotals(baseCurrency: baseCurrency);
        final balanceSummary = await repo.getBalanceSummary();
        final categoryTotals = Map<String, double>.from(analyticsData.categoryTotals);
        // Build monthly totals from ivePeriods (granularity matches analytics window).
        final monthlyTotals = <String, double>{};
        for (final p in analyticsData.ivePeriods) {
          monthlyTotals[p.label] = p.expense;
        }
        contextPayload = {
          'currency': baseCurrency,
          'baseBalance': walletTotals.net.toDouble(),
          'income': walletTotals.income.toDouble(),
          'spend': walletTotals.spend.toDouble(),
          'sharedOwed': double.tryParse(balanceSummary.youAreOwed) ?? 0.0,
          'sharedOwe': double.tryParse(balanceSummary.youOwe) ?? 0.0,
          'categoryTotals': categoryTotals,
          'monthlyTotals': monthlyTotals,
          'asOf': DateTime.now().toIso8601String().substring(0, 10),
        };
      }

      // Canvas: inline raw data in query (existing path, unchanged).
      String query;
      if (isCanvas) {
        final topCats = analyticsData.categoryTotals.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topCatsStr = topCats
            .take(5)
            .map((e) => '${e.key}: $baseCurrency ${e.value.toStringAsFixed(2)}')
            .join(', ');
        final recentRows = analyticsData.allExpenses
            .take(20)
            .map((e) =>
                '${e.createdAt?.substring(0, 10) ?? ''} ${e.category} ${e.currency} ${e.amount}')
            .join('\n');
        query = '${userText.trim()}'
            '\n\nFinancial data (last 30 days, all amounts in $baseCurrency):'
            '\nTotal Expenses: $baseCurrency ${analyticsData.totalSpend.toStringAsFixed(2)}'
            '\nDaily Burn: $baseCurrency ${analyticsData.burnRate.toStringAsFixed(2)}'
            '\nTotal Income: $baseCurrency ${analyticsData.totalIncome.toStringAsFixed(2)}'
            '\nNet: $baseCurrency ${analyticsData.netFlow.toStringAsFixed(2)}'
            '\nTop Categories: $topCatsStr'
            '\n\nRecent 20 transactions (native currency per entry):\n$recentRows';
      } else {
        query = userText.trim();
      }

      final accessToken = Supabase.instance.client.auth.currentSession?.accessToken ?? '';
      final httpRes = await http.post(
        Uri.parse(AuthConfig.netlifyAiUrl),
        headers: {'Content-Type': 'application/json', 'Authorization': 'Bearer $accessToken'},
        body: jsonEncode({
          'query': query,
          'mode': mode,
          'currency': baseCurrency,
          'language': ref.read(localeProvider).languageCode,
          if (!isCanvas) 'messages': history,
          if (contextPayload != null) 'context': contextPayload,
        }),
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

      // Parse optional action suggestion (chat mode only). Validate enum.
      const validActionTypes = {'add_expense', 'query_total', 'create_group'};
      Map<String, dynamic>? parsedAction;
      if (!isCanvas && report?['action'] is Map) {
        final a = (report!['action'] as Map).cast<String, dynamic>();
        if (validActionTypes.contains(a['type'] as String?)) {
          parsedAction = a;
        }
      }

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
        pendingAction: parsedAction,
        clearAction: parsedAction == null,
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
