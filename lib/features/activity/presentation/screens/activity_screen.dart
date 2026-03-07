import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
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

// ---------------------------------------------------------------------------
// Filter / sort enums
// ---------------------------------------------------------------------------
enum _ActivityFilter { all, wallet, groups, income }
enum _ActivitySort   { newest, largest }

/// Omni Activity Hub — polymorphic audit trail.
/// Shows group creation, shared expenses, personal wallet entries, and settlements.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _ActivityFilter _filter = _ActivityFilter.all;
  _ActivitySort   _sort   = _ActivitySort.newest;

  List<ActivityEvent> _applyFilterSort(List<ActivityEvent> feed) {
    // Filter
    var result = feed.where((ev) {
      switch (_filter) {
        case _ActivityFilter.all:
          return true;
        case _ActivityFilter.wallet:
          return ev is ExpenseEvent && ev.expense.groupId == null;
        case _ActivityFilter.groups:
          return (ev is ExpenseEvent && ev.expense.groupId != null) ||
              ev is GroupCreatedEvent ||
              ev is GroupDeletedEvent;
        case _ActivityFilter.income:
          return ev is ExpenseEvent && ev.expense.isIncome;
      }
    }).toList();

    // Sort
    if (_sort == _ActivitySort.largest) {
      result.sort((a, b) {
        final amtA = _eventAmount(a);
        final amtB = _eventAmount(b);
        return amtB.compareTo(amtA);
      });
    }
    // newest is already the default order from the provider
    return result;
  }

  Decimal _eventAmount(ActivityEvent ev) {
    if (ev is ExpenseEvent) {
      return Decimal.tryParse(ev.expense.universalUsdAmount ?? ev.expense.amount) ?? Decimal.zero;
    }
    if (ev is SettlementEvent) {
      return Decimal.tryParse(ev.amount) ?? Decimal.zero;
    }
    return Decimal.zero;
  }

  @override
  Widget build(BuildContext context) {
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
            tooltip: _sort == _ActivitySort.newest ? 'Sort: Newest first' : 'Sort: Largest first',
            icon: Icon(
              _sort == _ActivitySort.newest
                  ? Icons.sort_rounded
                  : Icons.attach_money_rounded,
              color: _sort == _ActivitySort.largest ? _teal : null,
            ),
            onPressed: () {
              HapticUtils.selection();
              setState(() {
                _sort = _sort == _ActivitySort.newest
                    ? _ActivitySort.largest
                    : _ActivitySort.newest;
              });
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: Column(
        children: [
          // ── Filter chips ───────────────────────────────────────────────
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
              children: [
                _FilterChip(
                  label: 'All',
                  selected: _filter == _ActivityFilter.all,
                  onTap: () { HapticUtils.selection(); setState(() => _filter = _ActivityFilter.all); },
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Wallet',
                  selected: _filter == _ActivityFilter.wallet,
                  onTap: () { HapticUtils.selection(); setState(() => _filter = _ActivityFilter.wallet); },
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Groups',
                  selected: _filter == _ActivityFilter.groups,
                  onTap: () { HapticUtils.selection(); setState(() => _filter = _ActivityFilter.groups); },
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'Income',
                  selected: _filter == _ActivityFilter.income,
                  onTap: () { HapticUtils.selection(); setState(() => _filter = _ActivityFilter.income); },
                ),
              ],
            ),
          ),
          // ── Feed ───────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              color: _teal,
              onRefresh: () async {
                HapticUtils.lightTap();
                ref.invalidate(omniActivityProvider);
              },
              child: feedAsync.when(
                skipLoadingOnReload: true,
                data: (feed) {
                  final filtered = _applyFilterSort(feed);
                  return _buildFeed(context, filtered, theme);
                },
                loading: () => const Center(child: CircularProgressIndicator()),
                error: (e, _) => Center(
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
          ),
        ],
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
    // For largest sort, skip date headers (they'd be misleading).
    if (_sort == _ActivitySort.newest) {
      String? lastLabel;
      for (final event in feed) {
        final label = _dateSection(event.timestamp);
        if (label != lastLabel) {
          items.add(_FeedItem.header(label));
          lastLabel = label;
        }
        items.add(_FeedItem.event(event));
      }
    } else {
      for (final event in feed) {
        items.add(_FeedItem.event(event));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
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
// Filter chip widget
// ---------------------------------------------------------------------------
class _FilterChip extends StatelessWidget {
  const _FilterChip({required this.label, required this.selected, required this.onTap});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? _teal.withAlpha(38) : Colors.transparent,
          border: Border.all(
            color: selected ? _teal : Colors.white24,
            width: selected ? 1.5 : 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          label,
          style: TextStyle(
            fontSize: 12,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            color: selected ? _teal : _slate,
          ),
        ),
      ),
    );
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
