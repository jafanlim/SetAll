import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../domain/entities/activity_event.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal   = Color(0xFF00D9B0);
const _purple = Color(0xFF8B5CF6);
const _green  = Color(0xFF22C55E);
const _slate  = Color(0xFF94A3B8);

/// Omni Activity Hub — polymorphic audit trail.
/// Shows group creation, shared expenses, personal wallet entries, and settlements.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme     = Theme.of(context);
    final feedAsync = ref.watch(omniActivityProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Activity',
          style: TextStyle(
            fontWeight: FontWeight.w800,
            fontSize: 20,
            letterSpacing: -0.3,
          ),
        ),
        backgroundColor: theme.colorScheme.surface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        automaticallyImplyLeading: false,
        actions: [
          IconButton(
            tooltip: 'Invite friend',
            icon: const Icon(Icons.person_add_outlined),
            onPressed: () {
              HapticUtils.lightTap();
              context.push(AppRouter.settings);
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async {
          HapticUtils.lightTap();
          ref.invalidate(omniActivityProvider);
        },
        child: feedAsync.when(
          skipLoadingOnReload: true,
          data:    (feed) => _buildFeed(context, feed, theme),
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Text(
                'Could not load activity',
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFeed(
    BuildContext context,
    List<ActivityEvent> feed,
    ThemeData theme,
  ) {
    if (feed.isEmpty) return _EmptyActivityState(theme: theme);

    final items = <_FeedItem>[];
    String? lastLabel;
    for (final event in feed) {
      final label = _dateSection(event.timestamp);
      if (label != lastLabel) {
        items.add(_FeedItem.header(label));
        lastLabel = label;
      }
      items.add(_FeedItem.event(event));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item.isHeader) {
          return _SectionHeader(label: item.header!, theme: theme);
        }
        final ev = item.event!;
        if (ev is ExpenseEvent)      return _ExpenseTile(event: ev);
        if (ev is GroupCreatedEvent) return _GroupCreatedTile(event: ev);
        if (ev is GroupDeletedEvent) return _GroupDeletedTile(event: ev);
        if (ev is SettlementEvent)   return _SettlementTile(event: ev);
        return const SizedBox.shrink();
      },
    );
  }

  String _dateSection(String? iso) {
    if (iso == null || iso.isEmpty) return 'Earlier';
    try {
      final d   = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
      final yesterday = now.subtract(const Duration(days: 1));
      if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) {
        return 'Yesterday';
      }
      if (now.difference(d).inDays < 7) return 'This Week';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return 'Earlier';
    }
  }
}

// ---------------------------------------------------------------------------
// Feed item wrapper
// ---------------------------------------------------------------------------
class _FeedItem {
  const _FeedItem.header(this.header) : isHeader = true,  event = null;
  const _FeedItem.event(this.event)   : isHeader = false, header = null;

  final bool           isHeader;
  final String?        header;
  final ActivityEvent? event;
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label, required this.theme});
  final String    label;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 6),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 11,
          letterSpacing: 0.8,
          color: _slate,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Empty state
// ---------------------------------------------------------------------------
class _EmptyActivityState extends StatelessWidget {
  const _EmptyActivityState({required this.theme});
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.28),
        Icon(Icons.history, size: 52, color: theme.colorScheme.onSurfaceVariant),
        const SizedBox(height: 16),
        Text(
          'No activity yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            'Your complete financial history — group expenses, personal wallet entries, and settlements — will appear here.',
            textAlign: TextAlign.center,
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Shared tile builder helper
// ---------------------------------------------------------------------------
Widget _buildEventTile({
  required BuildContext context,
  required ThemeData theme,
  required Color accent,
  required IconData icon,
  required String title,
  required String badge,
  String? timestamp,
  String? amount,
  bool amountPositive = false,
  VoidCallback? onTap,
}) {
  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: GlassCard(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: onTap,
        child: Row(
          children: [
            Container(
              width: 42,
              height: 42,
              decoration: BoxDecoration(
                color: accent.withAlpha(28),
                borderRadius: BorderRadius.circular(13),
              ),
              child: Icon(icon, size: 19, color: accent),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: accent.withAlpha(22),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(
                          badge,
                          style: TextStyle(
                            fontSize: 10,
                            fontWeight: FontWeight.w600,
                            color: accent,
                          ),
                        ),
                      ),
                      if (timestamp != null && timestamp.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Text(
                          _fmtTime(timestamp),
                          style: const TextStyle(fontSize: 10, color: _slate),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            if (amount != null)
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: amountPositive ? _green : accent,
                ),
              ),
            if (onTap != null) ...[
              const SizedBox(width: 4),
              const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
            ],
          ],
        ),
      ),
    ),
  );
}

String _fmtTime(String iso) {
  try {
    final d = DateTime.parse(iso).toLocal();
    return '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
  } catch (_) {
    return '';
  }
}

// ---------------------------------------------------------------------------
// Expense event tile
// ---------------------------------------------------------------------------
class _ExpenseTile extends StatelessWidget {
  const _ExpenseTile({required this.event});
  final ExpenseEvent event;

  static const Map<String, IconData> _categoryIcons = {
    'Food & drink':      Icons.restaurant_outlined,
    'Transport':         Icons.directions_car_outlined,
    'Entertainment':     Icons.movie_outlined,
    'Bills & utilities': Icons.receipt_long_outlined,
    'Shopping':          Icons.shopping_bag_outlined,
    'Travel':            Icons.flight_outlined,
    'Settlement':        Icons.check_circle_outline,
    'Other':             Icons.category_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final theme        = Theme.of(context);
    final e            = event.expense;
    final isPersonal   = e.groupId == null;
    final isSettlement = e.category == 'Settlement';

    final accent = isSettlement ? _green : isPersonal ? _purple : _teal;
    final icon   = isSettlement
        ? Icons.check_circle_outline
        : e.isIncome
            ? Icons.arrow_downward_rounded
            : (_categoryIcons[e.category] ?? Icons.attach_money_outlined);

    final desc  = e.description.isEmpty ? e.category : e.description;
    final title = isSettlement
        ? 'Settlement: $desc'
        : e.isIncome
            ? 'Income: $desc'
            : isPersonal
                ? 'Personal expense: $desc'
                : desc;

    final badge       = isPersonal ? 'Wallet' : (event.groupName.isEmpty ? 'Group' : event.groupName);
    final displayAmt  = formatAmount(e.originalAmount ?? e.amount);
    final displayCcy  = e.originalCurrency ?? e.currency;
    final amountStr   = '${e.isIncome ? '+' : ''}$displayCcy $displayAmt';

    return _buildEventTile(
      context:        context,
      theme:          theme,
      accent:         accent,
      icon:           icon,
      title:          title,
      badge:          badge,
      timestamp:      e.createdAt,
      amount:         amountStr,
      amountPositive: e.isIncome || isSettlement,
      onTap: e.groupId != null
          ? () {
              HapticUtils.lightTap();
              context.push(
                '/group/${e.groupId}/expense/${e.id}',
                extra: {'groupName': event.groupName},
              );
            }
          : null,
    );
  }
}

// ---------------------------------------------------------------------------
// Group created event tile
// ---------------------------------------------------------------------------
class _GroupCreatedTile extends StatelessWidget {
  const _GroupCreatedTile({required this.event});
  final GroupCreatedEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = event.createdByYou
        ? 'You created the group "${event.groupName}"'
        : 'Joined group "${event.groupName}"';

    return _buildEventTile(
      context:   context,
      theme:     theme,
      accent:    _teal,
      icon:      Icons.add_circle_outline,
      title:     title,
      badge:     'Group',
      timestamp: event.timestamp,
      onTap: () {
        HapticUtils.lightTap();
        context.push('/group/${event.groupId}');
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Group deleted event tile
// ---------------------------------------------------------------------------
class _GroupDeletedTile extends StatelessWidget {
  const _GroupDeletedTile({required this.event});
  final GroupDeletedEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return _buildEventTile(
      context:   context,
      theme:     theme,
      accent:    Colors.redAccent,
      icon:      Icons.delete_outline,
      title:     'You deleted the group "${event.groupName}"',
      badge:     'Deleted',
      timestamp: event.timestamp,
    );
  }
}

// ---------------------------------------------------------------------------
// Settlement event tile
// ---------------------------------------------------------------------------
class _SettlementTile extends StatelessWidget {
  const _SettlementTile({required this.event});
  final SettlementEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = event.isYouSender
        ? 'You settled up with ${event.toName}'
        : '${event.fromName} settled up with you';

    return _buildEventTile(
      context:        context,
      theme:          theme,
      accent:         _green,
      icon:           Icons.check_circle_outline,
      title:          title,
      badge:          'Settlement',
      timestamp:      event.timestamp,
      amount:         '${event.currency} ${formatAmount(event.amount)}',
      amountPositive: true,
    );
  }
}
