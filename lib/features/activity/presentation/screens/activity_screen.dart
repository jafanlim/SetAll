import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/expense_model.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal   = Color(0xFF00D9B0);
const _purple = Color(0xFF8B5CF6);
const _slate  = Color(0xFF94A3B8);

/// Unified activity hub: all group + personal expenses, sorted newest-first.
/// Personal/Wallet items are accented in purple; group items in teal.
class ActivityScreen extends ConsumerWidget {
  const ActivityScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme      = Theme.of(context);
    final feedAsync  = ref.watch(activityFeedProvider);
    final groupsAsync = ref.watch(myGroupsProvider);

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
      ),
      body: RefreshIndicator(
        color: _teal,
        onRefresh: () async {
          HapticUtils.lightTap();
          ref.invalidate(activityFeedProvider);
          ref.invalidate(myGroupsProvider);
        },
        child: feedAsync.when(
          skipLoadingOnReload: true,
          data: (feed) {
            final groups      = groupsAsync.valueOrNull ?? [];
            final groupNameMap = {for (final g in groups) g.id: g.name};
            return _buildFeed(context, feed, groupNameMap, theme);
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
    );
  }

  Widget _buildFeed(
    BuildContext context,
    List<ExpenseModel> feed,
    Map<String, String> groupNameMap,
    ThemeData theme,
  ) {
    if (feed.isEmpty) {
      return _EmptyActivityState(theme: theme);
    }

    // Group by date section header
    final items = <_FeedItem>[];
    String? lastDateLabel;
    for (final expense in feed) {
      final dateLabel = _dateSection(expense.createdAt);
      if (dateLabel != lastDateLabel) {
        items.add(_FeedItem.header(dateLabel));
        lastDateLabel = dateLabel;
      }
      items.add(_FeedItem.expense(expense));
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 96),
      itemCount: items.length,
      itemBuilder: (_, i) {
        final item = items[i];
        if (item.isHeader) {
          return _SectionHeader(label: item.header!, theme: theme);
        }
        final expense    = item.expense!;
        final isPersonal = expense.groupId == null;
        final groupName  = isPersonal
            ? 'Personal Wallet'
            : (groupNameMap[expense.groupId] ?? 'Group');
        return _ActivityEventTile(
          expense:    expense,
          groupName:  groupName,
          isPersonal: isPersonal,
        );
      },
    );
  }

  String _dateSection(String? iso) {
    if (iso == null) return 'Earlier';
    try {
      final d   = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (d.year == now.year && d.month == now.month && d.day == now.day) {
        return 'Today';
      }
      final yesterday = now.subtract(const Duration(days: 1));
      if (d.year == yesterday.year &&
          d.month == yesterday.month &&
          d.day == yesterday.day) {
        return 'Yesterday';
      }
      final diff = now.difference(d).inDays;
      if (diff < 7) return 'This Week';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return 'Earlier';
    }
  }
}

// ---------------------------------------------------------------------------
// Feed item wrapper (header OR expense)
// ---------------------------------------------------------------------------
class _FeedItem {
  const _FeedItem.header(this.header)
      : isHeader = true,
        expense = null;
  const _FeedItem.expense(this.expense)
      : isHeader = false,
        header = null;

  final bool           isHeader;
  final String?        header;
  final ExpenseModel?  expense;
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.history,
              size: 52,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              'No activity yet',
              style: theme.textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Your complete financial history — group expenses, personal wallet entries, and settlements — will appear here.',
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity event tile
// ---------------------------------------------------------------------------
class _ActivityEventTile extends ConsumerWidget {
  const _ActivityEventTile({
    required this.expense,
    required this.groupName,
    required this.isPersonal,
  });

  final ExpenseModel expense;
  final String       groupName;
  final bool         isPersonal;

  static const Map<String, IconData> _categoryIcons = {
    'Food & drink':      Icons.restaurant_outlined,
    'Transport':         Icons.directions_car_outlined,
    'Entertainment':     Icons.movie_outlined,
    'Bills & utilities': Icons.receipt_long_outlined,
    'Shopping':          Icons.shopping_bag_outlined,
    'Travel':            Icons.flight_outlined,
    'Other':             Icons.category_outlined,
  };

  String _buildEventTitle() {
    final desc = expense.description.isEmpty ? expense.category : expense.description;
    if (isPersonal) {
      return expense.isIncome ? 'Income: $desc' : 'Personal expense: $desc';
    }
    return desc;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme          = Theme.of(context);
    final accent         = isPersonal ? _purple : _teal;
    final icon           = expense.isIncome
        ? Icons.arrow_downward_rounded
        : (_categoryIcons[expense.category] ?? Icons.attach_money_outlined);
    final displayAmount  = formatAmount(expense.originalAmount ?? expense.amount);
    final displayCurrency = expense.originalCurrency ?? expense.currency;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: GlassCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: expense.groupId != null
              ? () {
                  HapticUtils.lightTap();
                  context.push(
                    '/group/${expense.groupId}/expense/${expense.id}',
                    extra: {'groupName': groupName},
                  );
                }
              : null,
          child: Row(
            children: [
              // ── Icon badge ───────────────────────────────────────────
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: accent.withAlpha(30),
                  borderRadius: BorderRadius.circular(13),
                ),
                child: Icon(icon, size: 19, color: accent),
              ),
              const SizedBox(width: 12),

              // ── Event description ────────────────────────────────────
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _buildEventTitle(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    // Context badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 2),
                          decoration: BoxDecoration(
                            color: accent.withAlpha(22),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            isPersonal ? 'Wallet' : groupName,
                            style: TextStyle(
                              fontSize: 10,
                              fontWeight: FontWeight.w600,
                              color: accent,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (expense.createdAt != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            _formatTime(expense.createdAt!),
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontSize: 10,
                              color: _slate,
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),

              // ── Amount ───────────────────────────────────────────────
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    '${expense.isIncome ? '+' : ''}$displayCurrency $displayAmount',
                    style: TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 13,
                      color: expense.isIncome ? _teal : accent,
                    ),
                  ),
                  if (expense.originalCurrency != null &&
                      expense.originalCurrency != expense.currency)
                    Text(
                      '${expense.currency} ${formatAmount(expense.amount)}',
                      style: TextStyle(fontSize: 10, color: _slate),
                    ),
                ],
              ),

              if (expense.groupId != null) ...[
                const SizedBox(width: 4),
                const Icon(Icons.chevron_right, color: Colors.white24, size: 18),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatTime(String iso) {
    try {
      final d = DateTime.parse(iso).toLocal();
      final h = d.hour.toString().padLeft(2, '0');
      final m = d.minute.toString().padLeft(2, '0');
      return '$h:$m';
    } catch (_) {
      return '';
    }
  }
}
