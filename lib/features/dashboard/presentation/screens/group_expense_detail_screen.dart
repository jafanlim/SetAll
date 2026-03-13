import 'dart:io' as io;
import 'dart:typed_data';

import 'package:decimal/decimal.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:pdfx/pdfx.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../../core/widgets/glass_card.dart';
import '../../../../data/models/expense_model.dart';
import '../../../../data/models/profile_model.dart';
import '../../../../data/models/split_model.dart';
import '../../../../domain/entities/expense.dart' show SplitType;

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _purple      = Color(0xFF8B5CF6);
const _teal        = Color(0xFF00D9B0);
const _brandOrange = Color(0xFFF97316);

const Map<String, IconData> _kCategoryIcons = {
  'Food & drink':      Icons.restaurant_outlined,
  'Transport':         Icons.directions_car_outlined,
  'Entertainment':     Icons.movie_outlined,
  'Bills & utilities': Icons.receipt_long_outlined,
  'Shopping':          Icons.shopping_bag_outlined,
  'Travel':            Icons.flight_outlined,
  'General':           Icons.category_outlined,
  'Other':             Icons.category_outlined,
};

const Map<String, Color> _kCategoryColors = {
  'Food & drink':      Color(0xFFEF4444),
  'Transport':         Color(0xFF3B82F6),
  'Entertainment':     Color(0xFFA855F7),
  'Bills & utilities': Color(0xFFF59E0B),
  'Shopping':          Color(0xFFEC4899),
  'Travel':            Color(0xFF06B6D4),
  'General':           Color(0xFF8B5CF6),
  'Other':             Color(0xFF94A3B8),
};

// ---------------------------------------------------------------------------
// Screen
// ---------------------------------------------------------------------------
class GroupExpenseDetailScreen extends ConsumerStatefulWidget {
  const GroupExpenseDetailScreen({
    super.key,
    required this.expense,
    required this.groupId,
    required this.groupName,
  });

  final ExpenseModel expense;
  final String groupId;
  final String groupName;

  @override
  ConsumerState<GroupExpenseDetailScreen> createState() =>
      _GroupExpenseDetailScreenState();
}

class _GroupExpenseDetailScreenState
    extends ConsumerState<GroupExpenseDetailScreen> {
  List<SplitModel>  _splits  = [];
  List<ProfileModel> _members = [];
  bool _loadingData = true;
  String _currentUid = '';
  late ExpenseModel _liveExpense;

  @override
  void initState() {
    super.initState();
    _liveExpense = widget.expense;
    _load();
  }

  Future<void> _load() async {
    _currentUid = Supabase.instance.client.auth.currentUser?.id ?? '';
    final repo   = ref.read(setAllRepositoryProvider);
    final splits  = await repo.getSplitsForExpense(widget.expense.id);
    List<ProfileModel> members = [];
    if (widget.groupId.isNotEmpty) {
      members = await repo.getGroupMembers(widget.groupId);
    }
    if (!mounted) return;
    setState(() {
      _splits      = splits;
      _members     = members;
      _loadingData = false;
    });
  }

  // ── Delete (two-step confirm, same as GroupDetailScreen) ─────────────────
  Future<void> _delete() async {
    final exp = widget.expense;
    final label = exp.description.isEmpty ? exp.category : exp.description;

    HapticUtils.primaryTap();
    final confirm1 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete expense?'),
        content: Text('Remove "$label"?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirm1 != true || !mounted) return;

    final confirm2 = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
          'This action is irreversible. The expense and all its splits will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.redAccent,
              foregroundColor: Colors.white,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Yes, delete forever'),
          ),
        ],
      ),
    );
    if (confirm2 != true || !mounted) return;

    await ref.read(setAllRepositoryProvider).deleteExpense(widget.expense.id);
    if (!mounted) return;
    HapticUtils.success();
    ref.invalidate(groupExpensesProvider(widget.groupId));
    ref.invalidate(balanceSummaryProvider);
    ref.invalidate(omniActivityProvider);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Expense deleted')),
    );
    if (context.canPop()) context.pop();
  }

  Future<void> _edit() async {
    HapticUtils.primaryTap();
    await context.push(
      '/group/${widget.groupId}/expense/${widget.expense.id}',
      extra: {'groupName': widget.groupName},
    );
    if (!mounted) return;
    // Reload expense and splits after returning from edit screen.
    final repo = ref.read(setAllRepositoryProvider);
    final updated = await repo.getExpense(widget.expense.id);
    if (!mounted) return;
    if (updated != null) setState(() => _liveExpense = updated);
    _load();
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  String _memberName(String userId) {
    if (userId == _currentUid) return 'You';
    try {
      return _members.firstWhere((m) => m.id == userId).name;
    } catch (_) {
      return 'Member';
    }
  }

  // Initials for avatar circle
  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.isEmpty || parts.first.isEmpty) return '?';
    if (parts.length == 1) return parts.first[0].toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }

  Color _avatarColor(String userId) {
    const palette = [
      Color(0xFF8B5CF6), Color(0xFF3B82F6), Color(0xFF22C55E),
      Color(0xFFF59E0B), Color(0xFFEC4899), Color(0xFF06B6D4),
      Color(0xFFF97316), Color(0xFF14B8A6),
    ];
    final idx = userId.codeUnits.fold(0, (a, b) => a + b) % palette.length;
    return palette[idx];
  }

  // ---------------------------------------------------------------------------
  // Build
  // ---------------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    final theme   = Theme.of(context);
    final expense = _liveExpense;

    final accentColor     = _purple;
    final categoryColor   = _kCategoryColors[expense.category] ?? _purple;
    final categoryIcon    = _kCategoryIcons[expense.category]  ?? Icons.category_outlined;

    final entryColor = expense.iconColor != null
        ? Color(expense.iconColor!)
        : categoryColor;
    final entryIcon = expense.iconCodepoint != null
        ? IconData(expense.iconCodepoint!, fontFamily: 'MaterialIcons')
        : categoryIcon;

    // Currency
    final entryCcy = expense.currency.isEmpty ? 'USD' : expense.currency;
    final entryAmt = Decimal.tryParse(expense.amount) ?? Decimal.zero;

    // Base-currency providers
    final baseCcyAsync  = ref.watch(baseCurrencyProvider);
    final baseCcy       = baseCcyAsync.valueOrNull ?? 'USD';
    final showConversion = entryCcy != baseCcy;
    final rateUsdToBaseAsync = showConversion
        ? ref.watch(rateToBaseProvider((from: 'USD', base: baseCcy)))
        : null;
    final rateUsdToBase = Decimal.tryParse(
      rateUsdToBaseAsync?.valueOrNull ?? '1',
    ) ?? Decimal.one;

    // Exchange rate at entry (entryCcy → USD, used to convert split amounts back)
    final exchangeRate = Decimal.tryParse(expense.exchangeRateApplied ?? '') ??
        Decimal.one;

    // Total in USD / base
    final totalUsd  = Decimal.tryParse(expense.universalUsdAmount ?? '') ??
        (entryAmt * exchangeRate);
    final totalBase = (totalUsd * rateUsdToBase).round(scale: 2);

    // Payer name
    final payerName = _memberName(expense.payerId);

    // Date
    final dateStr = expense.createdAt != null
        ? () {
            try {
              final dt = DateTime.parse(expense.createdAt!).toLocal();
              return DateFormat('EEE, d MMM yyyy  HH:mm').format(dt);
            } catch (_) { return expense.createdAt!; }
          }()
        : '—';

    // ── Group analytics (monthly category spend in this group) ─────────────
    final groupExpAsync  = ref.watch(groupExpensesProvider(widget.groupId));
    final groupExpenses  = groupExpAsync.valueOrNull ?? [];
    final now            = DateTime.now();
    final monthStart     = DateTime(now.year, now.month, 1);
    Decimal catMonthUsd  = Decimal.zero;
    Decimal totalMonthUsd = Decimal.zero;
    for (final e in groupExpenses) {
      final dt = DateTime.tryParse(e.createdAt ?? '') ?? DateTime(2000);
      if (dt.isBefore(monthStart)) continue;
      final eUsd = Decimal.tryParse(e.universalUsdAmount ?? e.amount) ?? Decimal.zero;
      totalMonthUsd += eUsd;
      if (e.category == expense.category) catMonthUsd += eUsd;
    }
    final gaugeRatio = (totalMonthUsd > Decimal.zero)
        ? (catMonthUsd / totalMonthUsd)
            .toDecimal(scaleOnInfinitePrecision: 4)
            .toDouble()
            .clamp(0.0, 1.0)
        : 0.0;
    final catBase   = (catMonthUsd   * rateUsdToBase).round(scale: 0);
    final totalBase2 = (totalMonthUsd * rateUsdToBase).round(scale: 0);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          widget.groupName,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        actions: [
          TextButton.icon(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined, size: 16),
            label: const Text('Edit'),
            style: TextButton.styleFrom(foregroundColor: _teal),
          ),
          TextButton.icon(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline, size: 16),
            label: const Text('Delete'),
            style: TextButton.styleFrom(foregroundColor: _brandOrange),
          ),
          const SizedBox(width: 4),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [

          // ── Hero card ────────────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(20),
            child: Column(
              children: [
                Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        color: entryColor.withAlpha(36),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(entryIcon, color: entryColor, size: 22),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            expense.description.isEmpty
                                ? expense.category
                                : expense.description,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700, fontSize: 15,
                            ),
                            maxLines: 2,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            dateStr,
                            style: TextStyle(
                              fontSize: 11,
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 20),

                // Sum display
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.07),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: accentColor.withValues(alpha: 0.2)),
                  ),
                  child: Column(
                    children: [
                      Text(
                        '$entryCcy ${entryAmt.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.w800,
                          letterSpacing: -1,
                          color: accentColor,
                        ),
                      ),
                      if (showConversion) ...[
                        const SizedBox(height: 4),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.swap_horiz, size: 14,
                                color: Color(0xFF94A3B8)),
                            const SizedBox(width: 4),
                            Text(
                              '≈ $baseCcy ${totalBase.toStringAsFixed(2)}',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w600,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (expense.exchangeRateApplied != null && showConversion) ...[
                        const SizedBox(height: 6),
                        Text(
                          'Rate at entry: 1 $entryCcy = ${expense.exchangeRateApplied} $baseCcy',
                          style: TextStyle(
                            fontSize: 10,
                            color: theme.colorScheme.onSurfaceVariant
                                .withValues(alpha: 0.7),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Category card ────────────────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 44, height: 44,
                  decoration: BoxDecoration(
                    color: categoryColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(categoryIcon, color: categoryColor, size: 22),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Category',
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: theme.colorScheme.onSurfaceVariant,
                          letterSpacing: 0.5,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        expense.category.isEmpty ? 'General' : expense.category,
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                          color: categoryColor,
                        ),
                      ),
                    ],
                  ),
                ),
                // Split method badge
                _SplitBadge(splitType: expense.splitType),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Amount Breakdown (splits) ────────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.account_balance_wallet_outlined,
                        size: 16, color: accentColor),
                    const SizedBox(width: 6),
                    Text(
                      'Amount Breakdown',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // Payer row ─────────────────────────────────────────────────
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: accentColor.withValues(alpha: 0.06),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                        color: accentColor.withValues(alpha: 0.18)),
                  ),
                  child: Row(
                    children: [
                      _AvatarCircle(
                        initials: _initials(payerName),
                        color: _avatarColor(expense.payerId),
                        size: 36,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Paid by $payerName',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: theme.colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '$entryCcy ${entryAmt.toStringAsFixed(2)}'
                              '${showConversion ? '  ≈ $baseCcy ${totalBase.toStringAsFixed(2)}' : ''}',
                              style: TextStyle(
                                fontSize: 11,
                                color: accentColor,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                if (_loadingData) ...[
                  const SizedBox(height: 16),
                  const Center(
                    child: SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  ),
                ] else if (_splits.isEmpty) ...[
                  const SizedBox(height: 12),
                  Text(
                    'No split details recorded.',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  const SizedBox(height: 10),
                  const Divider(height: 1),
                  const SizedBox(height: 10),
                  // Each split branch
                  // Use stored entry_amount_owed (exact entry-currency amount) when
                  // available; fall back to ratio approach for legacy splits without it.
                  ...() {
                    final hasEntryAmounts = _splits.every(
                        (s) => s.entryAmountOwed != null);
                    final sumUsd = hasEntryAmounts ? Decimal.zero : _splits.fold<Decimal>(
                        Decimal.zero,
                        (a, s) => a + (Decimal.tryParse(s.universalUsdOwed) ?? Decimal.zero));
                    var allocated = Decimal.zero;
                    final widgets = <Widget>[];
                    for (var i = 0; i < _splits.length; i++) {
                      final split = _splits[i];
                      final name = _memberName(split.userId);
                      final isPayerSplit = split.userId == expense.payerId;
                      final usdOwed = Decimal.tryParse(split.universalUsdOwed) ?? Decimal.zero;

                      // Prefer stored entry amount; fall back to ratio approach.
                      final Decimal entryOwed;
                      if (hasEntryAmounts) {
                        entryOwed = Decimal.tryParse(split.entryAmountOwed!) ?? Decimal.zero;
                      } else if (sumUsd <= Decimal.zero) {
                        entryOwed = Decimal.zero;
                      } else if (i == _splits.length - 1) {
                        entryOwed = (entryAmt - allocated).round(scale: 2);
                      } else {
                        entryOwed = ((usdOwed * entryAmt) / sumUsd).toDecimal(scaleOnInfinitePrecision: 4).round(scale: 2);
                        allocated += entryOwed;
                      }
                      final baseOwed = (usdOwed * rateUsdToBase).round(scale: 2);

                      widgets.add(Padding(
                        padding: const EdgeInsets.only(bottom: 8),
                        child: _SplitRow(
                          initials:    _initials(name),
                          avatarColor: _avatarColor(split.userId),
                          name:        name,
                          isPayerSplit: isPayerSplit,
                          entryCcy:    entryCcy,
                          entryAmount: entryOwed,
                          baseCcy:     baseCcy,
                          baseAmount:  baseOwed,
                          showBase:    showConversion,
                        ),
                      ));
                    }
                    return widgets;
                  }(),
                ],
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Mini analytics (group-scoped) ────────────────────────────────
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.bar_chart_rounded, size: 16, color: accentColor),
                    const SizedBox(width: 6),
                    Text(
                      'Monthly Spending — ${expense.category.isEmpty ? 'General' : expense.category}',
                      style: theme.textTheme.labelMedium?.copyWith(
                        fontWeight: FontWeight.w700, fontSize: 12,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'This group · ${DateFormat('MMMM yyyy').format(now)}',
                  style: TextStyle(
                    fontSize: 10,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 14),

                Stack(
                  children: [
                    Container(
                      height: 10,
                      decoration: BoxDecoration(
                        color: accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                    FractionallySizedBox(
                      widthFactor: gaugeRatio,
                      child: Container(
                        height: 10,
                        decoration: BoxDecoration(
                          color: categoryColor,
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    _AnalyticPill(
                      label: expense.category.isEmpty ? 'General' : expense.category,
                      value: '≈ $baseCcy ${catBase.toStringAsFixed(0)}',
                      color: categoryColor,
                    ),
                    _AnalyticPill(
                      label: 'Group total',
                      value: '≈ $baseCcy ${totalBase2.toStringAsFixed(0)}',
                      color: accentColor,
                    ),
                    _AnalyticPill(
                      label: 'Share',
                      value: '${(gaugeRatio * 100).toStringAsFixed(1)}%',
                      color: _teal,
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  'Approximated in $baseCcy via USD anchor.',
                  style: TextStyle(
                    fontSize: 9,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
                  ),
                ),
              ],
            ),
          ),

          const SizedBox(height: 12),

          // ── Attachments ──────────────────────────────────────────────────
          if (expense.attachmentUrls != null &&
              expense.attachmentUrls!.isNotEmpty) ...[
            _AttachmentsCard(expense: expense),
            const SizedBox(height: 12),
          ],

          // ── Notes ────────────────────────────────────────────────────────
          if (expense.notes != null && expense.notes!.trim().isNotEmpty) ...[
            GlassCard(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(Icons.notes_outlined, size: 16, color: _teal),
                      const SizedBox(width: 6),
                      Text(
                        'Notes',
                        style: theme.textTheme.labelMedium?.copyWith(
                          fontWeight: FontWeight.w700, fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Text(
                    expense.notes!.trim(),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      fontSize: 13, height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
          ],

          // ── Original currency info (only shown when entry ≠ USD/base) ──────
          if (expense.originalCurrency != null &&
              expense.originalCurrency != entryCcy)
          GlassCard(
            padding: const EdgeInsets.all(16),
            child: _MetaRow(
              label: 'Original',
              value: '${expense.originalCurrency} '
                  '${expense.originalAmount ?? '—'}',
            ),
          ),

          const SizedBox(height: 16),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Split row widget
// ---------------------------------------------------------------------------
class _SplitRow extends StatelessWidget {
  const _SplitRow({
    required this.initials,
    required this.avatarColor,
    required this.name,
    required this.isPayerSplit,
    required this.entryCcy,
    required this.entryAmount,
    required this.baseCcy,
    required this.baseAmount,
    required this.showBase,
  });

  final String  initials;
  final Color   avatarColor;
  final String  name;
  final bool    isPayerSplit;
  final String  entryCcy;
  final Decimal entryAmount;
  final String  baseCcy;
  final Decimal baseAmount;
  final bool    showBase;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = isPayerSplit ? 'share' : 'owes';
    final labelColor = isPayerSplit
        ? const Color(0xFF64748B)
        : const Color(0xFF8B5CF6);

    return Row(
      children: [
        _AvatarCircle(initials: initials, color: avatarColor, size: 32),
        const SizedBox(width: 10),
        // Name + label chip
        Expanded(
          child: Row(
            children: [
              Flexible(
                child: Text(
                  name,
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: labelColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w700,
                    color: labelColor,
                    letterSpacing: 0.3,
                  ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        // Amounts (right-aligned)
        Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              '$entryCcy ${entryAmount.toStringAsFixed(2)}',
              style: TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w700,
                color: isPayerSplit
                    ? theme.colorScheme.onSurfaceVariant
                    : const Color(0xFF8B5CF6),
              ),
            ),
            if (showBase)
              Text(
                '≈ $baseCcy ${baseAmount.toStringAsFixed(2)}',
                style: TextStyle(
                  fontSize: 10,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Avatar circle
// ---------------------------------------------------------------------------
class _AvatarCircle extends StatelessWidget {
  const _AvatarCircle({
    required this.initials,
    required this.color,
    required this.size,
  });
  final String initials;
  final Color  color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size, height: size,
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.18),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: 0.4), width: 1.5),
      ),
      alignment: Alignment.center,
      child: Text(
        initials,
        style: TextStyle(
          fontSize: size * 0.35,
          fontWeight: FontWeight.w700,
          color: color,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Split method badge
// ---------------------------------------------------------------------------
class _SplitBadge extends StatelessWidget {
  const _SplitBadge({required this.splitType});
  final SplitType splitType;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (splitType) {
      SplitType.even   => ('Evenly',   const Color(0xFF22C55E)),
      SplitType.manual => ('Exact',    const Color(0xFF3B82F6)),
      SplitType.parts  => ('By Parts', const Color(0xFFF59E0B)),
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 9,
          fontWeight: FontWeight.w800,
          color: color,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Attachments card (local copy, same pattern as WalletEntryDetailScreen)
// ---------------------------------------------------------------------------
class _AttachmentsCard extends ConsumerStatefulWidget {
  const _AttachmentsCard({required this.expense});
  final ExpenseModel expense;

  @override
  ConsumerState<_AttachmentsCard> createState() => _AttachmentsCardState();
}

class _AttachmentsCardState extends ConsumerState<_AttachmentsCard> {
  final Map<String, String> _signedUrls = {};
  bool _loading = false;

  @override
  void initState() {
    super.initState();
    _generateUrls();
  }

  Future<void> _generateUrls() async {
    final paths = widget.expense.attachmentUrls ?? [];
    if (paths.isEmpty) return;
    setState(() => _loading = true);
    final repo = ref.read(setAllRepositoryProvider);
    for (final path in paths) {
      final url = await repo.generateAttachmentSignedUrl(path);
      if (url != null && mounted) {
        setState(() => _signedUrls[path] = url);
      }
    }
    if (mounted) setState(() => _loading = false);
  }

  static const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'gif', 'bmp'};
  String _ext(String p) => p.split('.').last.toLowerCase();
  bool _isImage(String p) => _imageExts.contains(_ext(p));
  bool _isPdf(String p)   => _ext(p) == 'pdf';

  IconData _iconFor(String p) {
    if (_isImage(p)) return Icons.image_outlined;
    if (_isPdf(p))   return Icons.picture_as_pdf_outlined;
    return Icons.insert_drive_file_outlined;
  }

  void _preview(String path, String signedUrl) {
    final name = path.split('/').last;
    if (_isImage(path)) {
      _showImage(name, signedUrl);
    } else if (_isPdf(path)) {
      _showPdf(name, signedUrl);
    } else {
      _launchExternal(signedUrl);
    }
  }

  void _showImage(String name, String url) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: Colors.black,
          appBar: AppBar(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            title: Text(name,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ),
          body: InteractiveViewer(
            minScale: 0.5,
            maxScale: 6,
            child: Center(
              child: Image.network(url, fit: BoxFit.contain,
                  loadingBuilder: (_, child, p) =>
                      p == null ? child : const Center(child: CircularProgressIndicator()),
                  errorBuilder: (_, _, _) => const Icon(Icons.broken_image_outlined,
                      color: Colors.white54, size: 64)),
            ),
          ),
        ),
      ),
    );
  }

  Future<Uint8List> _fetchBytes(String url) async {
    final req  = await io.HttpClient().getUrl(Uri.parse(url));
    final resp = await req.close();
    final chunks = <List<int>>[];
    await for (final chunk in resp) { chunks.add(chunk); }
    return Uint8List.fromList(chunks.expand((c) => c).toList());
  }

  void _showPdf(String name, String url) {
    final ctrl = PdfControllerPinch(
      document: _fetchBytes(url).then(PdfDocument.openData),
    );
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog.fullscreen(
        child: Scaffold(
          backgroundColor: const Color(0xFF1E293B),
          appBar: AppBar(
            backgroundColor: const Color(0xFF1E293B),
            foregroundColor: Colors.white,
            title: Text(name,
                style: const TextStyle(fontSize: 14),
                overflow: TextOverflow.ellipsis),
            leading: IconButton(
              icon: const Icon(Icons.close),
              onPressed: () { ctrl.dispose(); Navigator.of(ctx).pop(); },
            ),
          ),
          body: PdfViewPinch(controller: ctrl),
        ),
      ),
    );
  }

  Future<void> _launchExternal(String url) async {
    if (!await launchUrl(Uri.parse(url),
        mode: LaunchMode.externalApplication)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open attachment')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final paths = widget.expense.attachmentUrls ?? [];
    return GlassCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file_outlined, size: 16, color: _teal),
              const SizedBox(width: 6),
              Text(
                'Attachments (${paths.length})',
                style: theme.textTheme.labelMedium?.copyWith(
                  fontWeight: FontWeight.w700, fontSize: 12,
                ),
              ),
              if (_loading) ...[
                const SizedBox(width: 8),
                const SizedBox(
                  width: 12, height: 12,
                  child: CircularProgressIndicator(strokeWidth: 1.5),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          ...paths.map((path) {
            final filename   = path.split('/').last;
            final signedUrl  = _signedUrls[path];
            return InkWell(
              onTap: signedUrl != null ? () => _preview(path, signedUrl) : null,
              borderRadius: BorderRadius.circular(8),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Row(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: signedUrl != null && _isImage(path)
                          ? Image.network(signedUrl,
                              width: 52, height: 52, fit: BoxFit.cover,
                              errorBuilder: (_, _, _) => Container(
                                width: 52, height: 52,
                                color: _teal.withAlpha(24),
                                child: const Icon(Icons.broken_image_outlined,
                                    size: 22, color: _teal),
                              ))
                          : Container(
                              width: 52, height: 52,
                              color: _teal.withAlpha(24),
                              child: Icon(_iconFor(path), size: 22, color: _teal),
                            ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            filename,
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: signedUrl != null
                                  ? theme.colorScheme.onSurface
                                  : theme.colorScheme.onSurfaceVariant,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                          if (signedUrl == null)
                            Text('Loading…',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: theme.colorScheme.onSurfaceVariant,
                                )),
                        ],
                      ),
                    ),
                    if (signedUrl != null)
                      const Icon(Icons.fullscreen, size: 16, color: _teal),
                  ],
                ),
              ),
            );
          }),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics pill
// ---------------------------------------------------------------------------
class _AnalyticPill extends StatelessWidget {
  const _AnalyticPill({
    required this.label,
    required this.value,
    required this.color,
  });
  final String label;
  final String value;
  final Color  color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(value,
            style: TextStyle(
                fontSize: 13, fontWeight: FontWeight.w700, color: color)),
        const SizedBox(height: 2),
        Text(label,
            style: TextStyle(
                fontSize: 9, color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Meta row
// ---------------------------------------------------------------------------
class _MetaRow extends StatelessWidget {
  const _MetaRow({required this.label, required this.value});
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ),
        Expanded(
          child: Text(value,
              style: TextStyle(
                fontSize: 11,
                color: theme.colorScheme.onSurface,
                fontFamily: null,
              )),
        ),
      ],
    );
  }
}
