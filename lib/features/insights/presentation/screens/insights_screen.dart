import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/utils/haptic_utils.dart';
import '../../models/ai_chat_message.dart';
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

  static const _teal = Color(0xFF14B8A6);

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

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.of(context).size.width;
    final isTablet = width >= 600 && width < 900;
    final isDesktop = width >= 900;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Insights',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 20),
        ),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        actions: [
          IconButton(
            icon: const Icon(Icons.add_comment_outlined, color: _teal),
            tooltip: 'New session',
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
            )
          : isTablet
              ? _TabletLayout(
                  scrollCtrl: _scrollCtrl,
                  inputCtrl: _inputCtrl,
                  onSend: _send,
                )
              : _MobileLayout(
                  scrollCtrl: _scrollCtrl,
                  inputCtrl: _inputCtrl,
                  onSend: _send,
                ),
    );
  }
}

// ---------------------------------------------------------------------------
// Mobile layout — full-screen single-column chat
// ---------------------------------------------------------------------------
class _MobileLayout extends ConsumerWidget {
  const _MobileLayout({
    required this.scrollCtrl,
    required this.inputCtrl,
    required this.onSend,
  });

  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Column(
      children: [
        Expanded(child: _ChatPanel(scrollCtrl: scrollCtrl)),
        _InputBar(controller: inputCtrl, onSend: onSend),
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
  });

  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Row(
      children: [
        Expanded(
          flex: 3,
          child: Column(
            children: [
              Expanded(child: _ChatPanel(scrollCtrl: scrollCtrl)),
              _InputBar(controller: inputCtrl, onSend: onSend),
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
  });

  final ScrollController scrollCtrl;
  final TextEditingController inputCtrl;
  final VoidCallback onSend;

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
              _InputBar(controller: inputCtrl, onSend: onSend),
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
              'Sessions',
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
                      'No sessions yet',
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
                          'Session ${index + 1}',
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
        child: Text('Error loading insights: $e'),
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
// Canvas Panel — renders chart data from AI if present
// ---------------------------------------------------------------------------
class _CanvasPanel extends ConsumerWidget {
  const _CanvasPanel();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final state = ref.watch(insightsProvider).valueOrNull;

    // Find the latest assistant canvas message.
    final canvasMsg = state?.messages.lastWhere(
      (m) => m.role == AiChatRole.assistant && m.isCanvas,
      orElse: () => AiChatMessage.create(
        sessionId: '',
        role: AiChatRole.assistant,
        content: '',
      ),
    );

    final hasCanvas = canvasMsg != null &&
        canvasMsg.isCanvas &&
        canvasMsg.content.isNotEmpty;

    return Container(
      color: theme.colorScheme.surfaceContainerLow,
      padding: const EdgeInsets.all(20),
      child: hasCanvas
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Analysis',
                  style: theme.textTheme.labelSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.1,
                    color: const Color(0xFF14B8A6),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: Center(
                    child: Text(
                      canvasMsg.content.contains('__CANVAS__:')
                          ? canvasMsg.content
                              .split('__CANVAS__:')
                              .first
                              .trim()
                          : canvasMsg.content,
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                ),
              ],
            )
          : Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.bar_chart_outlined,
                    size: 40,
                    color: theme.colorScheme.onSurfaceVariant
                        .withValues(alpha: 0.4),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'Ask a question to\ngenerate a chart.',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
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

  static const _teal = Color(0xFF14B8A6);

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
            'Ask anything about your finances.',
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
class _InputBar extends StatelessWidget {
  const _InputBar({
    required this.controller,
    required this.onSend,
  });

  final TextEditingController controller;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: controller,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.newline,
              decoration: InputDecoration(
                hintText: 'Ask about your finances…',
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
            onTap: onSend,
            child: Container(
              width: 40,
              height: 40,
              decoration: const BoxDecoration(
                color: Color(0xFF14B8A6),
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
    );
  }
}
