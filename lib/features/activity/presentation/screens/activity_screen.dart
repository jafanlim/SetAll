import 'dart:ui';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../data/models/group_model.dart';
import '../../../../domain/entities/activity_event.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _teal   = Color(0xFF00D9B0);
const _purple = Color(0xFF8B5CF6);
const _green  = Color(0xFF22C55E);
const _slate  = Color(0xFF94A3B8);
const _indigo = Color(0xFF818CF8);
const _red    = Colors.redAccent;

// ---------------------------------------------------------------------------
// Sort / group-by enums
// ---------------------------------------------------------------------------
enum _ActivitySort   { newest, oldest, largest, smallest }
enum _ActivityFilter { all, wallet, groups, income }
enum _GroupBy        { date, type }

/// Omni Activity Hub — premium financial audit trail.
class ActivityScreen extends ConsumerStatefulWidget {
  const ActivityScreen({super.key});

  @override
  ConsumerState<ActivityScreen> createState() => _ActivityScreenState();
}

class _ActivityScreenState extends ConsumerState<ActivityScreen> {
  _ActivityFilter _filter = _ActivityFilter.all;
  _ActivitySort   _sort   = _ActivitySort.newest;
  _GroupBy        _groupBy = _GroupBy.date;
  final _searchCtrl = TextEditingController();
  String _search = '';

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(() {
      if (_searchCtrl.text != _search) {
        setState(() => _search = _searchCtrl.text);
      }
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // ── Search matching ───────────────────────────────────────────────────────
  bool _matchesSearch(ActivityEvent ev, String q) {
    if (q.isEmpty) return true;
    final lower = q.toLowerCase();
    if (ev is ExpenseEvent) {
      return ev.expense.description.toLowerCase().contains(lower) ||
          ev.expense.category.toLowerCase().contains(lower) ||
          ev.groupName.toLowerCase().contains(lower) ||
          ev.payerName.toLowerCase().contains(lower);
    }
    if (ev is GroupCreatedEvent) return ev.groupName.toLowerCase().contains(lower);
    if (ev is GroupDeletedEvent) return ev.groupName.toLowerCase().contains(lower);
    if (ev is MemberAddedEvent)  return ev.groupName.toLowerCase().contains(lower) || ev.addedUserName.toLowerCase().contains(lower);
    if (ev is ExpenseDeletedEvent) return ev.description.toLowerCase().contains(lower) || ev.groupName.toLowerCase().contains(lower);
    if (ev is ExpenseEditedEvent)  return ev.newDescription.toLowerCase().contains(lower) || ev.groupName.toLowerCase().contains(lower);
    if (ev is SettlementEvent) return ev.fromName.toLowerCase().contains(lower) || ev.toName.toLowerCase().contains(lower);
    return false;
  }

  List<ActivityEvent> _applyFilterSort(List<ActivityEvent> feed) {
    var result = feed.where((ev) {
      // filter tab
      final passFilter = switch (_filter) {
        _ActivityFilter.all    => true,
        _ActivityFilter.wallet => ev is ExpenseEvent && ev.expense.groupId == null,
        _ActivityFilter.groups => (ev is ExpenseEvent && ev.expense.groupId != null) ||
            ev is GroupCreatedEvent || ev is GroupDeletedEvent || ev is MemberAddedEvent ||
            (ev is ExpenseDeletedEvent && ev.groupId != null) ||
            (ev is ExpenseEditedEvent  && ev.groupId != null),
        _ActivityFilter.income => ev is ExpenseEvent && ev.expense.isIncome,
      };
      if (!passFilter) return false;
      return _matchesSearch(ev, _search);
    }).toList();

    switch (_sort) {
      case _ActivitySort.newest:
        result.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      case _ActivitySort.oldest:
        result.sort((a, b) => a.timestamp.compareTo(b.timestamp));
      case _ActivitySort.largest:
        result.sort((a, b) => _eventAmount(b).compareTo(_eventAmount(a)));
      case _ActivitySort.smallest:
        result.sort((a, b) => _eventAmount(a).compareTo(_eventAmount(b)));
    }
    return result;
  }

  Decimal _eventAmount(ActivityEvent ev) {
    if (ev is ExpenseEvent)      return Decimal.tryParse(ev.expense.universalUsdAmount ?? ev.expense.amount) ?? Decimal.zero;
    if (ev is SettlementEvent)   return Decimal.tryParse(ev.amount)    ?? Decimal.zero;
    if (ev is ExpenseDeletedEvent) return Decimal.tryParse(ev.amount)  ?? Decimal.zero;
    if (ev is ExpenseEditedEvent)  return Decimal.tryParse(ev.newAmount) ?? Decimal.zero;
    return Decimal.zero;
  }

  // ── Section label helpers ────────────────────────────────────────────────
  String _dateSectionLabel(String? iso) {
    if (iso == null || iso.isEmpty) return 'Earlier';
    try {
      final d   = DateTime.parse(iso).toLocal();
      final now = DateTime.now();
      if (d.year == now.year && d.month == now.month && d.day == now.day) return 'Today';
      final yesterday = now.subtract(const Duration(days: 1));
      if (d.year == yesterday.year && d.month == yesterday.month && d.day == yesterday.day) return 'Yesterday';
      if (now.difference(d).inDays < 7) return 'This Week';
      return '${d.day}/${d.month}/${d.year}';
    } catch (_) {
      return 'Earlier';
    }
  }

  String _typeSectionLabel(ActivityEvent ev) {
    if (ev is ExpenseEvent) {
      if (ev.expense.isIncome) return 'Income';
      if (ev.expense.groupId == null) return 'Wallet';
      if (ev.expense.category == 'Settlement') return 'Settlements';
      return 'Group Expenses';
    }
    if (ev is SettlementEvent)    return 'Settlements';
    if (ev is GroupCreatedEvent || ev is GroupDeletedEvent || ev is MemberAddedEvent) return 'Group Events';
    if (ev is ExpenseDeletedEvent || ev is ExpenseEditedEvent) return 'Edits & Deletes';
    return 'Other';
  }

  // ── Build grouped feed items ─────────────────────────────────────────────
  List<_FeedItem> _buildFeedItems(List<ActivityEvent> feed) {
    final items = <_FeedItem>[];
    final useDate = _sort == _ActivitySort.newest || _sort == _ActivitySort.oldest;
    final showHeaders = _groupBy == _GroupBy.date ? useDate : true;

    String? lastLabel;
    for (final ev in feed) {
      final label = _groupBy == _GroupBy.date
          ? _dateSectionLabel(ev.timestamp)
          : _typeSectionLabel(ev);
      if (showHeaders && label != lastLabel) {
        items.add(_FeedItem.header(label));
        lastLabel = label;
      }
      items.add(_FeedItem.event(ev));
    }
    return items;
  }

  // ── Sort pill cycle ─────────────────────────────────────────────────────
  void _cycleSortOrder() {
    HapticUtils.selection();
    setState(() {
      _sort = switch (_sort) {
        _ActivitySort.newest   => _ActivitySort.oldest,
        _ActivitySort.oldest   => _ActivitySort.largest,
        _ActivitySort.largest  => _ActivitySort.smallest,
        _ActivitySort.smallest => _ActivitySort.newest,
      };
    });
  }

  void _toggleGroupBy() {
    HapticUtils.selection();
    setState(() {
      _groupBy = _groupBy == _GroupBy.date ? _GroupBy.type : _GroupBy.date;
    });
  }

  // ── Sort label ─────────────────────────────────────────────────────────
  String get _sortLabel => switch (_sort) {
    _ActivitySort.newest   => 'Newest',
    _ActivitySort.oldest   => 'Oldest',
    _ActivitySort.largest  => 'Largest',
    _ActivitySort.smallest => 'Smallest',
  };

  @override
  Widget build(BuildContext context) {
    final theme     = Theme.of(context);
    final feedAsync = ref.watch(omniActivityProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // ── Glass control header ────────────────────────────────────
            _ControlHeader(
              searchCtrl:  _searchCtrl,
              sort:        _sort,
              sortLabel:   _sortLabel,
              groupBy:     _groupBy,
              filter:      _filter,
              onCycleSort: _cycleSortOrder,
              onToggleGroupBy: _toggleGroupBy,
              onFilterChanged: (f) {
                HapticUtils.selection();
                setState(() => _filter = f);
              },
              onRefresh: () async {
                HapticUtils.lightTap();
                await ref.read(syncServiceProvider).performFullSync();
                if (!mounted) return;
                ref.invalidate(omniActivityProvider);
              },
            ),

            // ── Feed ───────────────────────────────────────────────────
            Expanded(
              child: RefreshIndicator(
                color: _teal,
                onRefresh: () async {
                  HapticUtils.lightTap();
                  await ref.read(syncServiceProvider).performFullSync();
                  if (!mounted) return;
                  ref.invalidate(omniActivityProvider);
                },
                child: feedAsync.when(
                  skipLoadingOnReload: true,
                  data: (feed) {
                    final filtered = _applyFilterSort(feed);
                    if (filtered.isEmpty) {
                      return _EmptyActivityState(theme: theme, hasSearch: _search.isNotEmpty);
                    }
                    final items = _buildFeedItems(filtered);
                    return ListView.builder(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(0, 4, 0, 96),
                      itemCount: items.length,
                      itemBuilder: (_, i) {
                        final item = items[i];
                        if (item.isHeader) {
                          return _SectionHeader(label: item.header!, theme: theme);
                        }
                        final ev = item.event!;
                        if (ev is ExpenseEvent)        return _ExpenseTile(event: ev);
                        if (ev is GroupCreatedEvent)   return _GroupCreatedTile(event: ev);
                        if (ev is GroupDeletedEvent)   return _GroupDeletedTile(event: ev);
                        if (ev is MemberAddedEvent)    return _MemberAddedTile(event: ev);
                        if (ev is SettlementEvent)     return _SettlementTile(event: ev);
                        if (ev is ExpenseDeletedEvent) return _ExpenseDeletedTile(event: ev);
                        if (ev is ExpenseEditedEvent)  return _ExpenseEditedTile(event: ev);
                        return const SizedBox.shrink();
                      },
                    );
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
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Glass control header: title + refresh, search bar, filter chips + pills
// ---------------------------------------------------------------------------
class _ControlHeader extends StatelessWidget {
  const _ControlHeader({
    required this.searchCtrl,
    required this.sort,
    required this.sortLabel,
    required this.groupBy,
    required this.filter,
    required this.onCycleSort,
    required this.onToggleGroupBy,
    required this.onFilterChanged,
    required this.onRefresh,
  });

  final TextEditingController searchCtrl;
  final _ActivitySort  sort;
  final String         sortLabel;
  final _GroupBy       groupBy;
  final _ActivityFilter filter;
  final VoidCallback   onCycleSort;
  final VoidCallback   onToggleGroupBy;
  final ValueChanged<_ActivityFilter> onFilterChanged;
  final VoidCallback   onRefresh;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface.withAlpha(isDark ? 200 : 240),
            border: Border(
              bottom: BorderSide(
                color: theme.colorScheme.outlineVariant.withAlpha(60),
              ),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Title row ─────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 8, 0),
                child: Row(
                  children: [
                    const Text(
                      'Activity',
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 22,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.refresh_rounded, size: 20),
                      tooltip: 'Refresh',
                      onPressed: onRefresh,
                    ),
                  ],
                ),
              ),

              // ── Search bar ────────────────────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Container(
                  height: 40,
                  decoration: BoxDecoration(
                    color: isDark
                        ? const Color(0xFF1E293B)
                        : const Color(0xFFF1F5F9),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: searchCtrl.text.isNotEmpty
                          ? _teal.withAlpha(160)
                          : Colors.transparent,
                      width: 1.5,
                    ),
                  ),
                  child: TextField(
                    controller: searchCtrl,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search expenses, groups, people…',
                      hintStyle: const TextStyle(fontSize: 13, color: _slate),
                      prefixIcon: const Icon(Icons.search_rounded, size: 18, color: _slate),
                      suffixIcon: searchCtrl.text.isNotEmpty
                          ? GestureDetector(
                              onTap: () => searchCtrl.clear(),
                              child: const Icon(Icons.close_rounded, size: 16, color: _slate),
                            )
                          : null,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                      isDense: true,
                    ),
                  ),
                ),
              ),

              // ── Filter chips + pill row ───────────────────────────────
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
                child: Row(
                  children: [
                    // Filter chips (scrollable)
                    Expanded(
                      child: SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            for (final f in _ActivityFilter.values) ...[
                              _FilterChip(
                                label: switch (f) {
                                  _ActivityFilter.all    => 'All',
                                  _ActivityFilter.wallet => 'Wallet',
                                  _ActivityFilter.groups => 'Groups',
                                  _ActivityFilter.income => 'Income',
                                },
                                selected: filter == f,
                                onTap: () => onFilterChanged(f),
                              ),
                              if (f != _ActivityFilter.income) const SizedBox(width: 6),
                            ],
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Sort pill
                    _PillButton(
                      icon: Icons.swap_vert_rounded,
                      label: sortLabel,
                      active: sort != _ActivitySort.newest,
                      onTap: onCycleSort,
                    ),
                    const SizedBox(width: 6),
                    // Group-by pill
                    _PillButton(
                      icon: Icons.layers_outlined,
                      label: groupBy == _GroupBy.date ? 'Date' : 'Type',
                      active: groupBy != _GroupBy.date,
                      onTap: onToggleGroupBy,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Pill button
// ---------------------------------------------------------------------------
class _PillButton extends StatelessWidget {
  const _PillButton({
    required this.icon,
    required this.label,
    required this.active,
    required this.onTap,
  });
  final IconData icon;
  final String   label;
  final bool     active;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: active ? _teal.withAlpha(30) : Colors.transparent,
          border: Border.all(
            color: active ? _teal : const Color(0xFF334155),
            width: 1,
          ),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 13, color: active ? _teal : _slate),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? _teal : _slate,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Filter chip
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
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
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
// Group avatar provider (signed URL, 1 h TTL)
// ---------------------------------------------------------------------------
final _activityAvatarProvider =
    FutureProvider.family<String?, String>((ref, path) async {
  return ref.watch(setAllRepositoryProvider).generateGroupAvatarSignedUrl(path);
});

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
        label.toUpperCase(),
        style: theme.textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.w700,
          fontSize: 10,
          letterSpacing: 1.0,
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
  const _EmptyActivityState({required this.theme, this.hasSearch = false});
  final ThemeData theme;
  final bool hasSearch;

  @override
  Widget build(BuildContext context) {
    return ListView(
      children: [
        SizedBox(height: MediaQuery.of(context).size.height * 0.25),
        Icon(
          hasSearch ? Icons.search_off_rounded : Icons.history_rounded,
          size: 52,
          color: theme.colorScheme.onSurfaceVariant,
        ),
        const SizedBox(height: 16),
        Text(
          hasSearch ? 'No results' : 'No activity yet',
          textAlign: TextAlign.center,
          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
        ),
        const SizedBox(height: 8),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            hasSearch
                ? 'Try a different search term or filter.'
                : 'Your complete financial history — group expenses, wallet entries, and settlements — will appear here.',
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
// LookBook card: 16px radius, subtle 1px border, 0 elevation
// ---------------------------------------------------------------------------
Widget _lookbookCard({
  required BuildContext context,
  required Widget child,
  EdgeInsetsGeometry padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
}) {
  final theme = Theme.of(context);
  return Container(
    decoration: BoxDecoration(
      color: theme.colorScheme.surface,
      borderRadius: BorderRadius.circular(16),
      border: Border.all(
        color: theme.colorScheme.outlineVariant.withAlpha(50),
        width: 1,
      ),
    ),
    child: Padding(padding: padding, child: child),
  );
}

// ---------------------------------------------------------------------------
// Shared tile builder helper (LookBook style)
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
  String? amountSub,
  bool amountPositive = false,
  VoidCallback? onTap,
  Widget? leadingOverride,
  List<_ContextAction>? contextActions,
}) {
  Widget tile = InkWell(
    borderRadius: BorderRadius.circular(16),
    onTap: onTap,
    child: Row(
      children: [
        leadingOverride ?? _DefaultLeading(accent: accent, icon: icon),
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
        if (amount != null) ...[
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                amount,
                style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  color: amountPositive ? _green : accent,
                ),
              ),
              if (amountSub != null)
                Text(
                  amountSub,
                  style: const TextStyle(fontSize: 10, color: _slate),
                ),
            ],
          ),
        ],
        if (onTap != null) ...[
          const SizedBox(width: 4),
          const Icon(Icons.chevron_right_rounded, color: _slate, size: 16),
        ],
      ],
    ),
  );

  if (contextActions != null && contextActions.isNotEmpty) {
    tile = _ContextMenuWrapper(actions: contextActions, child: tile);
  }

  return Padding(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
    child: _lookbookCard(context: context, child: tile),
  );
}

// ---------------------------------------------------------------------------
// Default leading: stripe + icon box
// ---------------------------------------------------------------------------
class _DefaultLeading extends StatelessWidget {
  const _DefaultLeading({required this.accent, required this.icon});
  final Color accent;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4, height: 44,
          decoration: BoxDecoration(
            color: accent, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 10),
        Container(
          width: 34, height: 34,
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withAlpha(80),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, size: 16,
              color: theme.colorScheme.onSurface.withAlpha(180)),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Context menu wrapper (long-press / right-click)
// ---------------------------------------------------------------------------
class _ContextAction {
  const _ContextAction({required this.label, required this.icon, required this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback onTap;
}

class _ContextMenuWrapper extends StatelessWidget {
  const _ContextMenuWrapper({required this.child, required this.actions});
  final Widget child;
  final List<_ContextAction> actions;

  void _show(BuildContext context, Offset? position) {
    HapticUtils.selection();
    final items = actions.map((a) => PopupMenuItem<_ContextAction>(
      value: a,
      child: Row(children: [
        Icon(a.icon, size: 16),
        const SizedBox(width: 10),
        Text(a.label, style: const TextStyle(fontWeight: FontWeight.w500)),
      ]),
    )).toList();

    final renderBox = context.findRenderObject() as RenderBox?;
    final offset = renderBox != null
        ? renderBox.localToGlobal(Offset.zero)
        : position ?? Offset.zero;
    final size = renderBox?.size ?? Size.zero;

    showMenu<_ContextAction>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy + size.height,
        offset.dx + size.width,
        offset.dy + size.height + 8,
      ),
      items: items,
    ).then((a) => a?.onTap());
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPress: () => _show(context, null),
      onSecondaryTapUp: (d) => _show(context, d.globalPosition),
      child: child,
    );
  }
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
// Expense event tile (with currency fix + context menu + avatar)
// ---------------------------------------------------------------------------
class _ExpenseTile extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final theme        = Theme.of(context);
    final e            = event.expense;
    final isPersonal   = e.groupId == null;
    final isSettlement = e.category == 'Settlement';

    final groups = ref.watch(myGroupsProvider).valueOrNull ?? <GroupModel>[];
    GroupModel? group;
    if (e.groupId != null) {
      final matches = groups.where((g) => g.id == e.groupId);
      if (matches.isNotEmpty) group = matches.first;
    }

    final groupAccent = group?.colorValue != null ? Color(group!.colorValue!) : null;
    final defaultAccent = isSettlement ? _green : isPersonal ? _purple : _teal;
    final accent = isSettlement
        ? _green
        : groupAccent ?? (e.iconColor != null ? Color(e.iconColor!) : defaultAccent);

    final defaultIcon = isSettlement
        ? Icons.check_circle_outline
        : e.isIncome
            ? Icons.arrow_downward_rounded
            : (_categoryIcons[e.category] ?? Icons.attach_money_outlined);
    final icon = (e.iconCodepoint != null && !isSettlement)
        ? IconData(e.iconCodepoint!, fontFamily: 'MaterialIcons')
        : defaultIcon;

    final desc   = e.description.isEmpty ? e.category : e.description;
    final byWhom = event.payerName.isEmpty ? 'You' : event.payerName;
    final title  = isSettlement
        ? 'Settlement: $desc'
        : e.isIncome
            ? '$desc · Income by $byWhom'
            : '$desc · by $byWhom';

    final badge = isPersonal ? 'Wallet' : (event.groupName.isEmpty ? 'Group' : event.groupName);

    // ── Currency fix: always use the expense's own currency ──────────────
    final primaryAmt = formatAmount(e.amount);
    final primaryCcy = e.currency;
    final prefix     = e.isIncome ? '+' : '';
    final amountStr  = '$prefix$primaryCcy $primaryAmt';

    // Sub-text: show original foreign currency if different from expense currency
    String? amountSub;
    if (e.originalCurrency != null &&
        e.originalAmount != null &&
        e.originalCurrency != e.currency) {
      amountSub = '${e.originalCurrency} ${formatAmount(e.originalAmount!)}';
    }

    final leadingOverride = group?.avatarUrl != null
        ? _AvatarLeading(storagePath: group!.avatarUrl!, accent: accent, fallbackIcon: icon)
        : null;

    // Context menu actions
    final actions = [
      _ContextAction(
        label: 'Edit',
        icon: Icons.edit_outlined,
        onTap: () {
          HapticUtils.lightTap();
          if (e.groupId != null) {
            context.push(
              '/group/${e.groupId}/expense/${e.id}',
              extra: {'groupName': event.groupName},
            );
          } else {
            context.push('/group/wallet/expense/${e.id}');
          }
        },
      ),
    ];

    return _buildEventTile(
      context:         context,
      theme:           theme,
      accent:          accent,
      icon:            icon,
      leadingOverride: leadingOverride,
      title:           title,
      badge:           badge,
      timestamp:       e.createdAt,
      amount:          amountStr,
      amountSub:       amountSub,
      amountPositive:  e.isIncome || isSettlement,
      contextActions:  actions,
      onTap: () {
        HapticUtils.lightTap();
        if (e.groupId != null) {
          context.push(
            '/group-expense-detail',
            extra: {
              'expense':   e,
              'groupId':   e.groupId,
              'groupName': event.groupName,
            },
          );
        } else {
          context.push('/wallet/entry', extra: e);
        }
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar leading widget — stripe + group photo
// ---------------------------------------------------------------------------
class _AvatarLeading extends ConsumerWidget {
  const _AvatarLeading({
    required this.storagePath,
    required this.accent,
    required this.fallbackIcon,
  });
  final String storagePath;
  final Color accent;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme    = Theme.of(context);
    final urlAsync = ref.watch(_activityAvatarProvider(storagePath));
    final neutral  = theme.colorScheme.surfaceContainerHighest.withAlpha(80);
    final iconWidget = Icon(fallbackIcon, size: 16,
        color: theme.colorScheme.onSurface.withAlpha(180));
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 4, height: 44,
          decoration: BoxDecoration(
            color: accent, borderRadius: BorderRadius.circular(4)),
        ),
        const SizedBox(width: 10),
        ClipRRect(
          borderRadius: BorderRadius.circular(10),
          child: SizedBox(
            width: 34, height: 34,
            child: urlAsync.when(
              data: (url) => url != null
                  ? Image.network(url, fit: BoxFit.cover,
                      errorBuilder: (_, e, s) =>
                          Container(color: neutral, child: iconWidget))
                  : Container(color: neutral, child: iconWidget),
              loading: () => Container(color: neutral),
              error: (_, e) => Container(color: neutral, child: iconWidget),
            ),
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Group created event tile — deep-links to group detail
// ---------------------------------------------------------------------------
class _GroupCreatedTile extends StatelessWidget {
  const _GroupCreatedTile({required this.event});
  final GroupCreatedEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = event.createdByYou
        ? 'You created "${event.groupName}"'
        : 'Joined "${event.groupName}"';

    return _buildEventTile(
      context:   context,
      theme:     theme,
      accent:    _teal,
      icon:      Icons.add_circle_outline_rounded,
      title:     title,
      badge:     'Group Created',
      timestamp: event.timestamp,
      onTap: () {
        HapticUtils.lightTap();
        context.push('/group/${event.groupId}', extra: {'groupName': event.groupName});
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Member added event tile — deep-links to group detail
// ---------------------------------------------------------------------------
class _MemberAddedTile extends StatelessWidget {
  const _MemberAddedTile({required this.event});
  final MemberAddedEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = event.addedByYou
        ? 'You added ${event.addedUserName} to "${event.groupName}"'
        : event.addedYou
            ? '${event.addedByName} added you to "${event.groupName}"'
            : '${event.addedByName} added ${event.addedUserName} to "${event.groupName}"';

    return _buildEventTile(
      context:   context,
      theme:     theme,
      accent:    _teal,
      icon:      Icons.person_add_outlined,
      title:     title,
      badge:     'Member Added',
      timestamp: event.timestamp,
      onTap: () {
        HapticUtils.lightTap();
        context.push('/group/${event.groupId}', extra: {'groupName': event.groupName});
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Group deleted event tile
// ---------------------------------------------------------------------------
class _GroupDeletedTile extends ConsumerStatefulWidget {
  const _GroupDeletedTile({required this.event});
  final GroupDeletedEvent event;

  @override
  ConsumerState<_GroupDeletedTile> createState() => _GroupDeletedTileState();
}

class _GroupDeletedTileState extends ConsumerState<_GroupDeletedTile> {
  bool _restoring = false;

  Future<void> _restore() async {
    setState(() => _restoring = true);
    final ok = await ref.read(setAllRepositoryProvider).restoreGroup(widget.event.groupId);
    if (!mounted) return;
    setState(() => _restoring = false);
    if (ok) {
      ref.invalidate(omniActivityProvider);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Group "${widget.event.groupName}" restored'),
          backgroundColor: _teal.withAlpha(220),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore group')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currentUid = ref.read(setAllRepositoryProvider).currentUserId;
    final isOwner = currentUid != null && currentUid == widget.event.creatorId;
    final withinWindow = DateTime.now().difference(widget.event.deletedAt).inDays < 365;
    final canRestore = isOwner && withinWindow;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _lookbookCard(
        context: context,
        child: Row(
          children: [
            _DefaultLeading(accent: _red, icon: Icons.delete_outline_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'You deleted "${widget.event.groupName}"',
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _red.withAlpha(22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text('Deleted',
                          style: TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _red)),
                    ),
                    const SizedBox(width: 6),
                    Text(_fmtTime(widget.event.timestamp),
                        style: const TextStyle(fontSize: 10, color: _slate)),
                  ]),
                ],
              ),
            ),
            if (canRestore)
              _restoring
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
                    )
                  : TextButton(
                      onPressed: _restore,
                      style: TextButton.styleFrom(
                        foregroundColor: _teal,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('RESTORE',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expense edited event tile — deep-links to edit screen
// ---------------------------------------------------------------------------
class _ExpenseEditedTile extends StatelessWidget {
  const _ExpenseEditedTile({required this.event});
  final ExpenseEditedEvent event;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ev    = event;
    final label = ev.newDescription.isEmpty ? ev.newCategory : ev.newDescription;
    final title = ev.editedByYou
        ? 'You edited "$label"'
        : '${ev.editedByName} edited "$label"';
    final badge = ev.groupId != null
        ? (ev.groupName.isEmpty ? 'Group' : ev.groupName)
        : 'Wallet';

    final changes = <String>[];
    if (ev.oldDescription != ev.newDescription) {
      changes.add('"${ev.oldDescription.isEmpty ? ev.oldCategory : ev.oldDescription}" → "${ev.newDescription.isEmpty ? ev.newCategory : ev.newDescription}"');
    }
    if (ev.oldCategory != ev.newCategory) {
      changes.add('${ev.oldCategory} → ${ev.newCategory}');
    }
    if (ev.oldAmount != ev.newAmount) {
      changes.add('${ev.currency} ${formatAmount(ev.oldAmount)} → ${ev.currency} ${formatAmount(ev.newAmount)}');
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _lookbookCard(
        context: context,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            HapticUtils.lightTap();
            if (ev.groupId != null) {
              context.push('/group/${ev.groupId}',
                  extra: {'groupName': ev.groupName});
            } else {
              context.push(AppRouter.wallet);
            }
          },
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _DefaultLeading(accent: _indigo, icon: Icons.edit_outlined),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600, fontSize: 13,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Row(children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: _indigo.withAlpha(22),
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Text(badge,
                            style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _indigo)),
                      ),
                      const SizedBox(width: 6),
                      Text(_fmtTime(ev.timestamp),
                          style: const TextStyle(fontSize: 10, color: _slate)),
                    ]),
                    if (changes.isNotEmpty) ...
                      changes.map((c) => Padding(
                        padding: const EdgeInsets.only(top: 3),
                        child: Text(c,
                          style: const TextStyle(fontSize: 10, color: _slate),
                          overflow: TextOverflow.ellipsis),
                      )),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _slate, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Expense deleted event tile
// ---------------------------------------------------------------------------
enum _RestoreChoice { expenseOnly, wholeGroup }

class _ExpenseDeletedTile extends ConsumerStatefulWidget {
  const _ExpenseDeletedTile({required this.event});
  final ExpenseDeletedEvent event;

  @override
  ConsumerState<_ExpenseDeletedTile> createState() => _ExpenseDeletedTileState();
}

class _ExpenseDeletedTileState extends ConsumerState<_ExpenseDeletedTile> {
  bool _restoring = false;

  void _invalidateProviders() {
    ref.invalidate(omniActivityProvider);
    ref.invalidate(personalExpensesProvider);
    ref.invalidate(walletBalanceProvider);
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(myGroupsProvider);
  }

  Future<void> _doRestoreExpense() async {
    setState(() => _restoring = true);
    final ok = await ref.read(setAllRepositoryProvider).restoreExpense(widget.event.expenseId);
    if (!mounted) return;
    setState(() => _restoring = false);
    if (ok) {
      _invalidateProviders();
      final label = widget.event.description.isEmpty ? widget.event.category : widget.event.description;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('"$label" restored'), backgroundColor: _teal.withAlpha(220)),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore expense')),
      );
    }
  }

  Future<void> _doRestoreGroup(String groupId) async {
    setState(() => _restoring = true);
    final repo = ref.read(setAllRepositoryProvider);
    final ok = await repo.restoreGroup(groupId);
    if (!mounted) return;
    setState(() => _restoring = false);
    if (ok) {
      _invalidateProviders();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${widget.event.groupName}" and all its expenses restored'),
          backgroundColor: _teal.withAlpha(220),
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not restore group')),
      );
    }
  }

  Future<void> _restore() async {
    final ev = widget.event;
    if (ev.deletedWithGroupId != null) {
      final repo = ref.read(setAllRepositoryProvider);
      final groupStillDeleted = await repo.isGroupSoftDeleted(ev.deletedWithGroupId!);
      if (!mounted) return;
      if (groupStillDeleted) {
        final choice = await showDialog<_RestoreChoice>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore options'),
            content: Text('The group "${ev.groupName}" was also deleted. What would you like to restore?'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, _RestoreChoice.expenseOnly),
                child: const Text('This expense only'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, _RestoreChoice.wholeGroup),
                child: const Text('Whole group + all expenses'),
              ),
            ],
          ),
        );
        if (!mounted || choice == null) return;
        if (choice == _RestoreChoice.wholeGroup) {
          await _doRestoreGroup(ev.deletedWithGroupId!);
          return;
        }
      }
    }
    await _doRestoreExpense();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ev    = widget.event;
    final label = ev.description.isEmpty ? ev.category : ev.description;
    final title = ev.deletedByYou
        ? 'You deleted "$label"'
        : '${ev.deletedByName} deleted "$label"';
    final badge = ev.deletedWithGroupId != null
        ? '${ev.groupName.isEmpty ? 'Group' : ev.groupName} (deleted)'
        : ev.groupId != null
            ? (ev.groupName.isEmpty ? 'Group' : ev.groupName)
            : 'Wallet';
    final amountStr = '${ev.currency} ${formatAmount(ev.amount)}';
    final withinWindow = DateTime.now().difference(ev.deletedAt).inDays < 30;
    final canRestore = ev.deletedByYou && withinWindow;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: _lookbookCard(
        context: context,
        child: Row(
          children: [
            _DefaultLeading(accent: _red, icon: Icons.delete_outline_rounded),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600, fontSize: 13,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: _red.withAlpha(22),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(badge,
                          style: const TextStyle(fontSize: 10, fontWeight: FontWeight.w600, color: _red)),
                    ),
                    const SizedBox(width: 6),
                    Text(_fmtTime(ev.timestamp),
                        style: const TextStyle(fontSize: 10, color: _slate)),
                  ]),
                ],
              ),
            ),
            Text(amountStr,
                style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13, color: _red)),
            const SizedBox(width: 8),
            if (canRestore)
              _restoring
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _teal),
                    )
                  : TextButton(
                      onPressed: _restore,
                      style: TextButton.styleFrom(
                        foregroundColor: _teal,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      child: const Text('RESTORE',
                          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
                    ),
          ],
        ),
      ),
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
      icon:           Icons.check_circle_outline_rounded,
      title:          title,
      badge:          'Settlement',
      timestamp:      event.timestamp,
      amount:         '${event.currency} ${formatAmount(event.amount)}',
      amountPositive: true,
    );
  }
}
