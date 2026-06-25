import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/utils/amount_formatter.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../data/recurring_candidate.dart';

// ---------------------------------------------------------------------------
// RecurringScreen — confirm / dismiss detected recurring charges
// ---------------------------------------------------------------------------
class RecurringScreen extends ConsumerStatefulWidget {
  const RecurringScreen({super.key});

  @override
  ConsumerState<RecurringScreen> createState() => _RecurringScreenState();
}

class _RecurringScreenState extends ConsumerState<RecurringScreen> {
  final Set<String> _processing = {};

  String _candidateKey(RecurringCandidate c) =>
      '${c.description}:${c.currency}:${c.amount}';

  Future<void> _confirm(RecurringCandidate c) async {
    final key = _candidateKey(c);
    setState(() => _processing.add(key));
    try {
      final repo = ref.read(setAllRepositoryProvider);
      await repo.insertRecurringRule({
        'id': const Uuid().v4(),
        'description': c.description,
        'amount': c.amount.toString(),
        'currency': c.currency,
        'category': c.category,
        'interval_days': c.intervalDays,
        'last_seen_at': c.lastSeenAt.toIso8601String().substring(0, 10),
        'next_expected':
            c.nextExpected.toIso8601String().substring(0, 10),
        'status': 'confirmed',
      });
      ref.invalidate(recurringRulesProvider);
      ref.invalidate(recurringCandidatesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    } finally {
      if (mounted) setState(() => _processing.remove(key));
    }
  }

  Future<void> _dismiss(RecurringCandidate c) async {
    final key = _candidateKey(c);
    setState(() => _processing.add(key));
    // Dismissal: insert a dismissed rule so it won't re-surface.
    try {
      final repo = ref.read(setAllRepositoryProvider);
      await repo.insertRecurringRule({
        'id': const Uuid().v4(),
        'description': c.description,
        'amount': c.amount.toString(),
        'currency': c.currency,
        'category': c.category,
        'interval_days': c.intervalDays,
        'last_seen_at': c.lastSeenAt.toIso8601String().substring(0, 10),
        'next_expected':
            c.nextExpected.toIso8601String().substring(0, 10),
        'status': 'dismissed',
      });
      ref.invalidate(recurringCandidatesProvider);
    } catch (_) {} finally {
      if (mounted) setState(() => _processing.remove(key));
    }
  }

  Future<void> _deleteConfirmed(String id) async {
    try {
      await ref.read(setAllRepositoryProvider).deleteRecurringRule(id);
      ref.invalidate(recurringRulesProvider);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final candidatesAsync = ref.watch(recurringCandidatesProvider);
    final candidates = candidatesAsync.valueOrNull ?? [];
    final rulesAsync = ref.watch(recurringRulesProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'recurring.title'.tr(),
          style: const TextStyle(
              fontWeight: FontWeight.w800, fontSize: 20, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0.5,
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 40),
        children: [
          // ── Detected candidates ─────────────────────────────────────────
          if (candidates.isNotEmpty) ...[
            _SectionHeader(label: 'recurring.detected_section'.tr()),
            const SizedBox(height: 8),
            ...candidates.map((c) {
              final key = _candidateKey(c);
              final busy = _processing.contains(key);
              return _CandidateTile(
                candidate: c,
                busy: busy,
                onConfirm: busy
                    ? null
                    : () {
                        HapticUtils.primaryTap();
                        _confirm(c);
                      },
                onDismiss: busy
                    ? null
                    : () {
                        HapticUtils.selection();
                        _dismiss(c);
                      },
              );
            }),
            const SizedBox(height: 24),
          ],

          // ── Confirmed rules ─────────────────────────────────────────────
          _SectionHeader(label: 'recurring.confirmed_section'.tr()),
          const SizedBox(height: 8),
          rulesAsync.when(
            loading: () =>
                const Center(child: CircularProgressIndicator(strokeWidth: 2)),
            error: (e, _) => Text(e.toString()),
            data: (rules) {
              if (rules.isEmpty && candidates.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 40),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.repeat_outlined,
                          size: 48,
                          color: theme.colorScheme.onSurfaceVariant
                              .withAlpha(80)),
                      const SizedBox(height: 12),
                      Text(
                        'recurring.no_detected'.tr(),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                            fontSize: 14),
                      ),
                    ],
                  ),
                );
              }
              if (rules.isEmpty) {
                return Text(
                  'recurring.no_confirmed'.tr(),
                  style: TextStyle(
                      color: theme.colorScheme.onSurfaceVariant, fontSize: 13),
                );
              }
              return Column(
                children: rules
                    .map((r) => _ConfirmedRuleTile(
                          rule: r,
                          onDelete: () => _deleteConfirmed(r['id'] as String),
                        ))
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Section header
// ---------------------------------------------------------------------------
class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.label});
  final String label;
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Text(
      label.toUpperCase(),
      style: theme.textTheme.labelSmall?.copyWith(
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Candidate tile — confirm / dismiss
// ---------------------------------------------------------------------------
class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.busy,
    required this.onConfirm,
    required this.onDismiss,
  });

  final RecurringCandidate candidate;
  final bool busy;
  final VoidCallback? onConfirm;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final c = candidate;
    final nextFmt =
        DateFormat('d MMM').format(c.nextExpected);
    final pct = (c.confidence * 100).round();

    return Card(
      margin: const EdgeInsets.only(bottom: 10),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
            color: theme.colorScheme.outlineVariant.withAlpha(120)),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    c.description,
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: const Color(0xFF14B8A6).withAlpha(30),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    'recurring.confidence'.tr(
                        namedArgs: {'pct': '$pct'}),
                    style: const TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF14B8A6)),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${c.currency} ${formatAmountForCurrency(c.amount.toString(), c.currency)} · '
              '${'recurring.every_days'.tr(namedArgs: {'days': '${c.intervalDays}'})} · next: $nextFmt',
              style: TextStyle(
                  fontSize: 12,
                  color: theme.colorScheme.onSurfaceVariant),
            ),
            const SizedBox(height: 10),
            if (busy)
              const Center(
                  child: SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2)))
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: onDismiss,
                      style: OutlinedButton.styleFrom(
                        foregroundColor: theme.colorScheme.onSurfaceVariant,
                        side: BorderSide(
                            color: theme.colorScheme.outlineVariant),
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('recurring.dismiss_btn'.tr(),
                          style: const TextStyle(fontSize: 13)),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: FilledButton(
                      onPressed: onConfirm,
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF14B8A6),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(10)),
                      ),
                      child: Text('recurring.confirm_btn'.tr(),
                          style: const TextStyle(
                              fontSize: 13, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Confirmed rule tile — display only + delete
// ---------------------------------------------------------------------------
class _ConfirmedRuleTile extends StatelessWidget {
  const _ConfirmedRuleTile({required this.rule, required this.onDelete});
  final Map<String, dynamic> rule;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final desc = rule['description'] as String? ?? '';
    final amt = rule['amount']?.toString() ?? '0';
    final ccy = rule['currency'] as String? ?? '';
    final days = rule['interval_days']?.toString() ?? '';
    final next = rule['next_expected'] as String?;
    String nextFmt = '';
    if (next != null) {
      try {
        nextFmt = DateFormat('d MMM').format(DateTime.parse(next));
      } catch (_) {}
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
            color: const Color(0xFF14B8A6).withAlpha(60)),
      ),
      child: ListTile(
        dense: true,
        leading: const Icon(Icons.repeat_rounded,
            color: Color(0xFF14B8A6), size: 20),
        title: Text(desc,
            style:
                const TextStyle(fontWeight: FontWeight.w600, fontSize: 13)),
        subtitle: Text(
          '$ccy ${formatAmountForCurrency(amt, ccy)} · '
          '${'recurring.every_days'.tr(namedArgs: {'days': days})}${nextFmt.isNotEmpty ? ' · next: $nextFmt' : ''}',
          style: TextStyle(
              fontSize: 11, color: theme.colorScheme.onSurfaceVariant),
        ),
        trailing: IconButton(
          icon: Icon(Icons.delete_outline,
              size: 18, color: theme.colorScheme.onSurfaceVariant),
          onPressed: onDelete,
        ),
      ),
    );
  }
}
