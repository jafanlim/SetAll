import 'dart:async' show unawaited;
import 'dart:convert';

import 'package:decimal/decimal.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart' show AppRouter;
import '../../../../domain/entities/expense.dart' show SplitType;
import '../../../../core/utils/haptic_utils.dart';
import '../../models/ai_chat_message.dart';
import '../../models/canvas_data.dart';
import '../../providers/insights_provider.dart';

// ---------------------------------------------------------------------------
// InsightsScreen — FEAT-06: AI Insights Panel (full chat experience)
// ---------------------------------------------------------------------------
//
// Layout breakpoints (mirrors AdaptiveShell):
//   mobile  (<600dp): full-screen single-column chat
//   tablet  (600–900dp): chat (flex 3) | canvas (flex 2)
//   desktop (>900dp): history sidebar (flex 1) | chat (flex 3) | canvas (flex 2)
//
class InsightsScreen extends ConsumerStatefulWidget {
  const InsightsScreen({super.key});

  @override
  ConsumerState<InsightsScreen> createState() => _InsightsScreenState();
}

class _InsightsScreenState extends ConsumerState<InsightsScreen> {
  final TextEditingController _inputCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();

  @override
  void dispose() {
    _inputCtrl.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          0,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _send() async {
    final text = _inputCtrl.text.trim();
    if (text.isEmpty) return;
    _inputCtrl.clear();
    HapticUtils.primaryTap();
    await ref.read(insightsProvider.notifier).sendMessage(text);
    _scrollToBottom();
  }

  Future<void> _sendDeepAnalysis() async {
    HapticUtils.primaryTap();
    await ref.read(insightsProvider.notifier).sendMessage(
      'insights.deep_analysis_trigger'.tr(),
      mode: 'canvas',
    );
    _scrollToBottom();
  }

  void _showMobileCanvas(BuildContext context) {
    // Signal: expanded — user opened the canvas panel.
    final insState = ref.read(insightsProvider).valueOrNull;
    if (insState != null) {
      final canvasMsg = insState.messages.cast<AiChatMessage?>().lastWhere(
            (m) => m!.role == AiChatRole.assistant && m.isCanvas,
            orElse: () => null,
          );
      final messageId = canvasMsg?.id ?? insState.sessionId;
      unawaited(ref.read(setAllRepositoryProvider).insertInsightSignal(
        sessionId: insState.sessionId,
        messageId: messageId,
        signalType: 'expanded',
      ));
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => DraggableScrollableSheet(
        initialChildSize: 0.75,
        minChildSize: 0.4,
        maxChildSize: 0.95,
        expand: false,
        builder: (ctx, sc) => Container(
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surface,
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: _CanvasPanel(scrollable: true, scrollController: sc),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Show action confirmation sheet whenever AI returns a pending action.
    ref.listen<AsyncValue<InsightsState>>(insightsProvider, (prev, next) {
      final action = next.valueOrNull?.pendingAction;
      if (action == null) return;
      final prevAction = prev?.valueOrNull?.pendingAction;
      if (action == prevAction) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showModalBottomSheet<void>(
          context: context,
          isScrollControlled: true,
          backgroundColor: Colors.transparent,
          builder: (_) => _AiActionSheet(action: action),
        ).then((_) => ref.read(insightsProvider.notifier).clearAction());
      });
    });

    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 600 && width < 900;
    final isDesktop = width >= 900;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'insights.title'.tr(),
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: _teal),
            tooltip: 'insights.new_session_tooltip'.tr(),
            onPressed: () {
              HapticUtils.lightTap();
              ref.read(insightsProvider.notifier).newSession();
            },
          ),
        ],
      ),
      body: isDesktop
          ? _DesktopLayout(
              scrollCtrl: _scrollCtrl,
              inputCtrl: _inputCtrl,
              onSend: _send,
              onDeepAnalysis: _sendDeepAnalysis,
            )
          : isTablet
              ? _TabletLayout(
                  scrollCtrl: _scrollCtrl,
                  inputCtrl: _inputCtrl,
                  onSend: _send,
                  onDeepAnalysis: _sendDeepAnalysis,
                )
              : _MobileLayout(
                  scrollCtrl: _scrollCtrl,
                  inputCtrl: _inputCtrl,
                  onSend: _send,
                  onDeepAnalysis: _sendDeepAnalysis,
                  onShowCanvas: () => _showMobileCanvas(context),
                ),
    );
  }
}

const _teal = Color(0xFF14B8A6);

// ---------------------------------------------------------------------------
// Mobile layout — full-screen single-column chat
// ---------------------------------------------------------------------------
class _MobileLayout extends ConsumerWidget {
  const _MobileLayout({
    required this.scrollCtrl,
    required this.inputCtrl,
    required this.onSend,
    required this.onDeepAnalysis,
    required this.onShowCanvas,
  });

  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final VoidCallback onSend;
  final VoidCallback onDeepAnalysis;
  final VoidCallback onShowCanvas;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(insightsProvider).valueOrNull;
    final hasCanvas = state?.messages.any(
          (m) => m.role == AiChatRole.assistant && m.isCanvas,
        ) ??
        false;

    return Column(
      children: [
        const _LatestAnalysisCard(),
        const _BudgetPanel(),
        Expanded(child: _ChatPanel(scrollCtrl: scrollCtrl)),
        if (hasCanvas)
          Align(
            alignment: Alignment.centerRight,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 0, 16, 8),
              child: FloatingActionButton.extended(
                onPressed: onShowCanvas,
                backgroundColor: _teal,
                foregroundColor: Colors.white,
                icon: const Icon(Icons.bar_chart_outlined, size: 18),
                label: Text(
                  'insights.view_analysis_btn'.tr(),
                  style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w700),
                ),
              ),
            ),
          ),
        _InputBar(
          controller: inputCtrl,
          onSend: onSend,
          onDeepAnalysis: onDeepAnalysis,
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Tablet layout — chat | canvas
// ---------------------------------------------------------------------------
class _TabletLayout extends ConsumerWidget {
  const _TabletLayout({
    required this.scrollCtrl,
    required this.inputCtrl,
    required this.onSend,
    required this.onDeepAnalysis,
  });

  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final VoidCallback onSend;
  final VoidCallback onDeepAnalysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _ChatPanel(scrollCtrl: scrollCtrl)),
              _InputBar(
                controller: inputCtrl,
                onSend: onSend,
                onDeepAnalysis: onDeepAnalysis,
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        const Expanded(flex: 2, child: _CanvasPanel()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop layout — history sidebar | chat | canvas
// ---------------------------------------------------------------------------
class _DesktopLayout extends ConsumerWidget {
  const _DesktopLayout({
    required this.scrollCtrl,
    required this.inputCtrl,
    required this.onSend,
    required this.onDeepAnalysis,
  });

  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final VoidCallback onSend;
  final VoidCallback onDeepAnalysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        const Expanded(flex: 1, child: _HistorySidebar()),
        const VerticalDivider(width: 1),
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _ChatPanel(scrollCtrl: scrollCtrl)),
              _InputBar(
                controller: inputCtrl,
                onSend: onSend,
                onDeepAnalysis: onDeepAnalysis,
              ),
            ],
          ),
        ),
        const VerticalDivider(width: 1),
        const Expanded(flex: 2, child: _CanvasPanel()),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// History Sidebar (desktop only)
// ---------------------------------------------------------------------------
class _HistorySidebar extends ConsumerWidget {
  const _HistorySidebar();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(insightsProvider).valueOrNull;
    final sessionIds = state?.sessionIds ?? [];
    final currentId = state?.sessionId ?? '';

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: Text(
              'insights.sessions_header'.tr(),
              style: theme.textTheme.labelSmall?.copyWith(
                fontWeight: FontWeight.w700,
                letterSpacing: 1.1,
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Expanded(
            child: sessionIds.isEmpty
                ? Center(
                    child: Text(
                      'insights.no_sessions'.tr(),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: sessionIds.length,
                    itemBuilder: (context, index) {
                      final sid = sessionIds[index];
                      final isActive = sid == currentId;
                      return ListTile(
                        dense: true,
                        selected: isActive,
                        selectedTileColor:
                            const Color(0xFF14B8A6).withValues(alpha: 0.1),
                        leading: Icon(
                          Icons.chat_bubble_outline,
                          size: 16,
                          color: isActive
                              ? const Color(0xFF14B8A6)
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          'insights.session_n'.tr(namedArgs: {'n': '${index + 1}'}),
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight:
                                isActive ? FontWeight.w700 : FontWeight.w400,
                            color: isActive
                                ? const Color(0xFF14B8A6)
                                : theme.colorScheme.onSurface,
                          ),
                        ),
                        onTap: () {
                          HapticUtils.lightTap();
                          ref
                              .read(insightsProvider.notifier)
                              .loadSession(sid);
                        },
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Chat Panel — message list
// ---------------------------------------------------------------------------
class _ChatPanel extends ConsumerWidget {
  const _ChatPanel({required this.scrollCtrl});

  final ScrollController scrollCtrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final insightsAsync = ref.watch(insightsProvider);

    return insightsAsync.when(
      loading: () =>
          const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      error: (e, _) => Center(
        child: Text('insights.error_loading'.tr(namedArgs: {'error': '$e'})),
      ),
      data: (state) {
        final messages = state.messages;
        if (messages.isEmpty && !state.isLoading) {
          return const _EmptyChat();
        }
        return ListView.builder(
          controller: scrollCtrl,
          reverse: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          itemCount: messages.length + (state.isLoading ? 1 : 0),
          itemBuilder: (context, index) {
            if (state.isLoading && index == 0) {
              return const _TypingBubble();
            }
            final msgIndex =
                messages.length - 1 - (state.isLoading ? index - 1 : index);
            final msg = messages[msgIndex];
            return _MessageBubble(message: msg);
          },
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Canvas Panel — FEAT-08: full structured AI analysis with charts
// ---------------------------------------------------------------------------
class _CanvasPanel extends ConsumerWidget {
  const _CanvasPanel({this.scrollable = false, this.scrollController});

  final bool scrollable;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(insightsProvider).valueOrNull;

    AiChatMessage? canvasMsg;
    for (final m in (state?.messages ?? []).reversed) {
      if (m.role == AiChatRole.assistant && m.isCanvas) {
        canvasMsg = m;
        break;
      }
    }

    CanvasData? canvas;
    if (canvasMsg != null) {
      canvas = CanvasData.tryParseFromSentinel(canvasMsg.content);
    }

    final isEmpty = canvas == null;

    Widget body;
    if (isEmpty) {
      body = ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        physics: const ClampingScrollPhysics(),
        shrinkWrap: scrollable,
        children: [
          const _BudgetPanel(),
          const SizedBox(height: 24),
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.auto_awesome_outlined,
                  size: 40,
                  color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                ),
                const SizedBox(height: 12),
                Text(
                  'insights.tap_deep_hint'.tr(),
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    } else {
      final widgets = <Widget>[
        // Budget progress (always visible at top of canvas)
        const _BudgetPanel(),
        const SizedBox(height: 12),

        // Header
        Text(
          'insights.analysis_header'.tr(),
          style: theme.textTheme.labelSmall?.copyWith(
            fontWeight: FontWeight.w700,
            letterSpacing: 1.2,
            color: _teal,
          ),
        ),
        const SizedBox(height: 10),

        // Summary card
        Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: _teal.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: _teal.withValues(alpha: 0.2)),
          ),
          child: Text(
            canvas.summary,
            style: theme.textTheme.bodySmall?.copyWith(
              height: 1.5,
              color: theme.colorScheme.onSurface,
            ),
          ),
        ),

        // Insights chips
        if (canvas.insights.isNotEmpty) ...[  
          const SizedBox(height: 14),
          Text(
            'insights.key_insights_header'.tr(),
            style: theme.textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              letterSpacing: 1.1,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 8),
          ...canvas.insights.map((insight) => Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      margin: const EdgeInsets.only(top: 5),
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: _teal,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        insight,
                        style: theme.textTheme.bodySmall?.copyWith(
                          height: 1.45,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              )),
        ],

        // Charts
        ...canvas.charts.map((chart) => _CanvasChartTile(chart: chart)),

        // Action chips
        if (canvas.actions.isNotEmpty) ...[  
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 6,
            children: canvas.actions
                .map((a) => Chip(
                      label: Text(a,
                          style: const TextStyle(
                              fontSize: 11, fontWeight: FontWeight.w600)),
                      backgroundColor: _teal.withValues(alpha: 0.12),
                      side: BorderSide(color: _teal.withValues(alpha: 0.3)),
                    ))
                .toList(),
          ),
        ],

        const SizedBox(height: 16),
      ];

      body = ListView(
        controller: scrollController,
        padding: const EdgeInsets.all(16),
        physics: const ClampingScrollPhysics(),
        shrinkWrap: scrollable,
        children: widgets,
      );
    }

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      child: body,
    );
  }
}

// ---------------------------------------------------------------------------
// Individual chart tile rendered inside _CanvasPanel
// ---------------------------------------------------------------------------
class _CanvasChartTile extends StatelessWidget {
  const _CanvasChartTile({required this.chart});

  final CanvasChart chart;

  Color _parseColor(String hex, int fallbackIdx) {
    final palette = [
      const Color(0xFF14B8A6),
      const Color(0xFF8B5CF6),
      const Color(0xFFF59E0B),
      const Color(0xFFEF4444),
      const Color(0xFF3B82F6),
    ];
    try {
      final clean = hex.replaceAll('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return palette[fallbackIdx % palette.length];
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Widget chartWidget;

    switch (chart.type.toLowerCase()) {
      case 'line':
        chartWidget = _buildLine(theme);
        break;
      case 'doughnut':
      case 'donut':
      case 'pie':
        chartWidget = _buildPie(theme);
        break;
      default:
        chartWidget = _buildBar(theme);
    }

    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            chart.title,
            style: theme.textTheme.labelMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: theme.colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 10),
          SizedBox(height: 180, child: chartWidget),
        ],
      ),
    );
  }

  Widget _buildBar(ThemeData theme) {
    final groups = <BarChartGroupData>[];
    for (var i = 0; i < chart.data.length; i++) {
      final color = i < chart.backgroundColor.length
          ? _parseColor(chart.backgroundColor[i], i)
          : _teal;
      groups.add(BarChartGroupData(
        x: i,
        barRods: [
          BarChartRodData(
            toY: chart.data[i],
            color: color,
            width: 18,
            borderRadius: BorderRadius.circular(4),
          ),
        ],
      ));
    }
    return BarChart(
      BarChartData(
        barGroups: groups,
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 0.8,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= chart.labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    chart.labels[idx],
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLine(ThemeData theme) {
    final spots = <FlSpot>[];
    for (var i = 0; i < chart.data.length; i++) {
      spots.add(FlSpot(i.toDouble(), chart.data[i]));
    }
    final color = chart.backgroundColor.isNotEmpty
        ? _parseColor(chart.backgroundColor.first, 0)
        : _teal;
    return LineChart(
      LineChartData(
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            color: color,
            barWidth: 2.5,
            dotData: const FlDotData(show: false),
            belowBarData: BarAreaData(
              show: true,
              color: color.withValues(alpha: 0.12),
            ),
          ),
        ],
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          getDrawingHorizontalLine: (v) => FlLine(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4),
            strokeWidth: 0.8,
          ),
        ),
        borderData: FlBorderData(show: false),
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          rightTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          topTitles: const AxisTitles(
            sideTitles: SideTitles(showTitles: false),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (value, meta) {
                final idx = value.toInt();
                if (idx < 0 || idx >= chart.labels.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(
                    chart.labels[idx],
                    style: TextStyle(
                      fontSize: 9,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildPie(ThemeData theme) {
    final sections = <PieChartSectionData>[];
    for (var i = 0; i < chart.data.length; i++) {
      final color = i < chart.backgroundColor.length
          ? _parseColor(chart.backgroundColor[i], i)
          : _teal;
      sections.add(PieChartSectionData(
        value: chart.data[i],
        color: color,
        radius: chart.type == 'doughnut' || chart.type == 'donut' ? 40 : 70,
        title: i < chart.labels.length ? chart.labels[i] : '',
        titleStyle: const TextStyle(
            fontSize: 9, fontWeight: FontWeight.w600, color: Colors.white),
      ));
    }
    return PieChart(
      PieChartData(
        sections: sections,
        centerSpaceRadius:
            chart.type == 'doughnut' || chart.type == 'donut' ? 35 : 0,
        sectionsSpace: 2,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Message Bubble
// ---------------------------------------------------------------------------
class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final AiChatMessage message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isUser = message.role == AiChatRole.user;
    final displayContent = message.isCanvas && message.content.contains('__CANVAS__:')
        ? message.content.split('__CANVAS__:').first.trim()
        : message.content;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 28,
              height: 28,
              decoration: BoxDecoration(
                color: _teal.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.auto_awesome, size: 14, color: _teal),
            ),
            const SizedBox(width: 8),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: isUser
                    ? _teal
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft: const Radius.circular(16),
                  topRight: const Radius.circular(16),
                  bottomLeft: Radius.circular(isUser ? 16 : 4),
                  bottomRight: Radius.circular(isUser ? 4 : 16),
                ),
              ),
              child: Text(
                displayContent,
                style: TextStyle(
                  fontSize: 14,
                  height: 1.45,
                  color: isUser
                      ? Colors.white
                      : theme.colorScheme.onSurface,
                ),
              ),
            ),
          ),
          if (isUser) const SizedBox(width: 8),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Typing indicator bubble
// ---------------------------------------------------------------------------
class _TypingBubble extends StatelessWidget {
  const _TypingBubble();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            decoration: BoxDecoration(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                size: 14, color: Color(0xFF14B8A6)),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(16),
                topRight: Radius.circular(16),
                bottomRight: Radius.circular(16),
                bottomLeft: Radius.circular(4),
              ),
            ),
            child: const SizedBox(
              width: 36,
              height: 12,
              child: _ThreeDotsLoader(),
            ),
          ),
        ],
      ),
    );
  }
}

class _ThreeDotsLoader extends StatefulWidget {
  const _ThreeDotsLoader();

  @override
  State<_ThreeDotsLoader> createState() => _ThreeDotsLoaderState();
}

class _ThreeDotsLoaderState extends State<_ThreeDotsLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, ignored) {
        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: List.generate(3, (i) {
            final delay = i / 3;
            final t = ((_ctrl.value - delay) % 1.0).clamp(0.0, 1.0);
            final opacity = (t < 0.5 ? t * 2 : (1 - t) * 2).clamp(0.3, 1.0);
            return Opacity(
              opacity: opacity,
              child: const CircleAvatar(
                radius: 3,
                backgroundColor: Color(0xFF14B8A6),
              ),
            );
          }),
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Empty chat state
// ---------------------------------------------------------------------------
class _EmptyChat extends StatelessWidget {
  const _EmptyChat();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 64,
            height: 64,
            decoration: BoxDecoration(
              color: const Color(0xFF14B8A6).withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.auto_awesome,
                color: Color(0xFF14B8A6), size: 28),
          ),
          const SizedBox(height: 16),
          Text(
            'SetAll AI',
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.w700,
              color: const Color(0xFF14B8A6),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'insights.ask_hint'.tr(),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Input bar
// ---------------------------------------------------------------------------
class _InputBar extends ConsumerWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
    required this.onDeepAnalysis,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final VoidCallback onDeepAnalysis;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isLoading =
        ref.watch(insightsProvider).valueOrNull?.isLoading ?? false;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        8,
        16,
        8 + MediaQuery.of(context).padding.bottom,
      ),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant,
            width: 0.5,
          ),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  minLines: 1,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: InputDecoration(
                    hintText: 'insights.ask_hint'.tr(),
                    hintStyle: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant,
                      fontSize: 14,
                    ),
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerHighest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              GestureDetector(
                onTap: isLoading ? null : onSend,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: isLoading
                        ? _teal.withValues(alpha: 0.4)
                        : _teal,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.send_rounded,
                    color: Colors.white,
                    size: 18,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Deep Analysis button
          SizedBox(
            width: double.infinity,
            child: Tooltip(
              message: 'Generate a comprehensive AI analysis with charts',
              child: OutlinedButton.icon(
                onPressed: isLoading ? null : onDeepAnalysis,
                icon: const Icon(Icons.auto_awesome, size: 14),
                label: Text('insights.deep_analysis_btn'.tr(),
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w700)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _teal,
                  side: BorderSide(color: _teal.withValues(alpha: 0.5)),
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// FEAT-19: Latest AI analysis card — shown at top of InsightsScreen chat
// ---------------------------------------------------------------------------
class _LatestAnalysisCard extends ConsumerStatefulWidget {
  const _LatestAnalysisCard();

  @override
  ConsumerState<_LatestAnalysisCard> createState() => _LatestAnalysisCardState();
}

class _LatestAnalysisCardState extends ConsumerState<_LatestAnalysisCard> {
  bool _generating = false;

  Future<void> _generate() async {
    final uid = Supabase.instance.client.auth.currentUser?.id;
    if (uid == null) return;
    setState(() => _generating = true);
    try {
      await Supabase.instance.client.functions.invoke(
        'weekly-analysis',
        body: {'userId': uid, 'onDemand': true},
      );
      ref.invalidate(aiInsightsProvider);
    } catch (_) {} finally {
      if (mounted) setState(() => _generating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme    = Theme.of(context);
    final insights = ref.watch(aiInsightsProvider);

    return insights.when(
      loading: () => _buildShimmer(theme),
      error:   (_, _) => const SizedBox.shrink(),
      data: (list) {
        if (list.isEmpty) return _buildEmpty(theme);
        final latest = list.first;
        return _buildCard(theme, latest.summary, latest.topCategory, _fmtDate(latest.createdAt));
      },
    );
  }

  Widget _buildShimmer(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        height: 72,
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
          borderRadius: BorderRadius.circular(12),
        ),
        child: const Center(
          child: SizedBox(
            width: 20, height: 20,
            child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
          ),
        ),
      ),
    );
  }

  Widget _buildEmpty(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          border: Border.all(color: _teal.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(12),
          color: _teal.withValues(alpha: 0.04),
        ),
        child: Row(
          children: [
            const Icon(Icons.auto_awesome, size: 16, color: _teal),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'No analysis yet — tap Generate',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
            _generating
                ? const SizedBox(width: 16, height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                : TextButton(
                    style: TextButton.styleFrom(
                      foregroundColor: _teal,
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    onPressed: () { HapticUtils.primaryTap(); _generate(); },
                    child: const Text('Generate',
                        style: TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
                  ),
          ],
        ),
      ),
    );
  }

  Widget _buildCard(ThemeData theme, String summary, String? topCat, String date) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      child: Container(
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          border: Border.all(color: _teal.withValues(alpha: 0.25)),
          borderRadius: BorderRadius.circular(12),
          color: _teal.withValues(alpha: 0.04),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.auto_awesome, size: 14, color: _teal),
                const SizedBox(width: 6),
                Text('insights.latest_analysis_label'.tr(namedArgs: {'date': date}),
                    style: const TextStyle(
                        fontSize: 11, fontWeight: FontWeight.w700,
                        color: _teal, letterSpacing: 0.3)),
                const Spacer(),
                if (topCat != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                    decoration: BoxDecoration(
                      color: _teal.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(topCat,
                        style: const TextStyle(
                            fontSize: 10, fontWeight: FontWeight.w600, color: _teal)),
                  ),
                  const SizedBox(width: 8),
                ],
                _generating
                    ? const SizedBox(width: 14, height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: _teal))
                    : GestureDetector(
                        onTap: () { HapticUtils.lightTap(); _generate(); },
                        child: const Icon(Icons.refresh_rounded, size: 16, color: _teal),
                      ),
              ],
            ),
            const SizedBox(height: 6),
            Text(summary,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 12, color: theme.colorScheme.onSurface, height: 1.4)),
          ],
        ),
      ),
    );
  }

  String _fmtDate(String? raw) {
    if (raw == null) return '';
    try {
      return DateFormat('d MMM').format(DateTime.parse(raw).toLocal());
    } catch (_) {
      return '';
    }
  }
}

// ---------------------------------------------------------------------------
// Budget progress panel — shown in insights screen (mobile + canvas)
// ---------------------------------------------------------------------------
class _BudgetPanel extends ConsumerWidget {
  const _BudgetPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme    = Theme.of(context);
    final progress = ref.watch(budgetProgressProvider);
    final budgets  = progress.valueOrNull ?? [];

    if (budgets.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
        child: GestureDetector(
          onTap: () => context.push(AppRouter.budgets),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              border: Border.all(color: _teal.withValues(alpha: 0.18)),
              borderRadius: BorderRadius.circular(12),
              color: _teal.withValues(alpha: 0.03),
            ),
            child: Row(
              children: [
                const Icon(Icons.savings_outlined, size: 15, color: _teal),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'budget.set_budget_hint'.tr(),
                    style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant),
                  ),
                ),
                const Icon(Icons.chevron_right, size: 16, color: _teal),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 6, 12, 0),
      child: GestureDetector(
        onTap: () => context.push(AppRouter.budgets),
        child: Container(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(
            border: Border.all(color: _teal.withValues(alpha: 0.22)),
            borderRadius: BorderRadius.circular(12),
            color: _teal.withValues(alpha: 0.04),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.savings_outlined, size: 14, color: _teal),
                  const SizedBox(width: 6),
                  Text(
                    'budget.monthly_budgets'.tr(),
                    style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: _teal,
                        letterSpacing: 0.3),
                  ),
                  const Spacer(),
                  const Icon(Icons.chevron_right, size: 14, color: _teal),
                ],
              ),
              const SizedBox(height: 8),
              ...budgets.map((b) {
                final label = b.category ?? 'budget.overall'.tr();
                final isOver = b.isOver;
                final barColor = isOver
                    ? const Color(0xFFF97316)
                    : const Color(0xFF22C55E);
                return Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(label,
                              style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: theme.colorScheme.onSurface)),
                          Text(
                            '${b.currency} ${b.spend.toStringAsFixed(0)} / ${b.amount.toStringAsFixed(0)}',
                            style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.w600,
                                color: isOver ? const Color(0xFFF97316) : const Color(0xFF22C55E)),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(3),
                        child: LinearProgressIndicator(
                          value: b.fraction,
                          minHeight: 4,
                          backgroundColor: barColor.withAlpha(28),
                          valueColor: AlwaysStoppedAnimation<Color>(barColor),
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// AI Action Confirmation Sheet
// ---------------------------------------------------------------------------
// Shows when the AI returns an action suggestion in chat mode.
// query_total: display only (no write).
// add_expense / create_group: confirm before calling repo.
class _AiActionSheet extends ConsumerStatefulWidget {
  const _AiActionSheet({required this.action});
  final Map<String, dynamic> action;

  @override
  ConsumerState<_AiActionSheet> createState() => _AiActionSheetState();
}

class _AiActionSheetState extends ConsumerState<_AiActionSheet> {
  bool _busy = false;
  String? _error;

  String get _type => widget.action['type'] as String? ?? '';

  Future<void> _confirm() async {
    setState(() { _busy = true; _error = null; });
    try {
      final repo = ref.read(setAllRepositoryProvider);
      if (_type == 'add_expense') {
        final uid = await repo.ensureUser();
        if (uid == null) throw Exception('Not signed in');
        final raw = widget.action['amount'];
        final amount = Decimal.tryParse(raw?.toString() ?? '0') ?? Decimal.zero;
        final description = widget.action['description'] as String? ?? 'AI Expense';
        final currency = widget.action['currency'] as String? ?? 'USD';
        final category = widget.action['category'] as String? ?? 'General';
        await repo.addExpense(
          payerId: uid,
          amount: amount,
          description: description,
          currency: currency,
          splitType: SplitType.even,
          splits: [],
          category: category,
          entryDate: DateTime.now(),
        );
      } else if (_type == 'create_group') {
        final name = widget.action['name'] as String? ?? 'New Group';
        await repo.createGroup(name);
      }
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      setState(() { _busy = false; _error = e.toString(); });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isWrite = _type == 'add_expense' || _type == 'create_group';

    String title;
    String subtitle;
    if (_type == 'add_expense') {
      final amt = widget.action['amount'];
      final cur = widget.action['currency'] as String? ?? '';
      final desc = widget.action['description'] as String? ?? '';
      title = 'Log expense?';
      subtitle = '$cur ${amt ?? '?'} — $desc';
    } else if (_type == 'create_group') {
      title = 'Create group?';
      subtitle = widget.action['name'] as String? ?? '';
    } else {
      title = 'Query result';
      subtitle = jsonEncode(widget.action);
    }

    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
          24, 20, 24, 24 + MediaQuery.of(context).viewInsets.bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text(title,
              style: theme.textTheme.titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 6),
          Text(subtitle,
              style: theme.textTheme.bodyMedium
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!,
                style: TextStyle(
                    color: theme.colorScheme.error, fontSize: 13)),
          ],
          const SizedBox(height: 24),
          if (isWrite)
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: _busy
                        ? null
                        : () => Navigator.of(context).pop(),
                    child: const Text('Cancel'),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                        backgroundColor: _teal,
                        foregroundColor: Colors.white),
                    onPressed: _busy ? null : _confirm,
                    child: _busy
                        ? const SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: Colors.white))
                        : const Text('Confirm'),
                  ),
                ),
              ],
            )
          else
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: _teal,
                  foregroundColor: Colors.white),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('OK'),
            ),
        ],
      ),
    );
  }
}
