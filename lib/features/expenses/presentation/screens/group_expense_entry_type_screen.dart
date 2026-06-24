import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/providers/setall_providers.dart';
import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';
import '../../../receipt/presentation/receipt_entry_sheet.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _purple    = Color(0xFF8B5CF6);
const _purpleDim = Color(0x1A8B5CF6);
const _blue      = Color(0xFF3B82F6);
const _blueDim   = Color(0x1A3B82F6);

/// Step 0 of the group expense entry flow.
/// The user chooses between [ENTER MANUALLY] or [SCAN OR UPLOAD].
class GroupExpenseEntryTypeScreen extends ConsumerWidget {
  const GroupExpenseEntryTypeScreen({
    required this.groupId,
    required this.groupName,
    this.groupCurrency,
    super.key,
  });

  final String groupId;
  final String groupName;
  final String? groupCurrency;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: Text(
          groupName,
          style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            HapticUtils.lightTap();
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/');
            }
          },
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'receipt.add_how'.tr(),
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 36),

              // ── Manual Card ──────────────────────────────────────────────
              _EntryTypeCard(
                icon: Icons.edit_note_rounded,
                iconColor: _purple,
                iconBg: _purpleDim,
                title: 'receipt.enter_manually'.tr(),
                subtitle: 'receipt.entry_manual_subtitle'.tr(),
                accentColor: _purple,
                onTap: () {
                  HapticUtils.primaryTap();
                  context.pop(); // pop the chooser
                  context.push(AppRouter.addExpense, extra: {
                    'groupId': groupId,
                    'groupName': groupName,
                    if (groupCurrency != null) 'groupCurrency': groupCurrency,
                  });
                },
              ),

              const SizedBox(height: 16),

              // ── Scan Card ─────────────────────────────────────────────────
              _EntryTypeCard(
                icon: Icons.document_scanner_rounded,
                iconColor: _blue,
                iconBg: _blueDim,
                title: 'receipt.scan_bill'.tr(),
                subtitle: 'receipt.scan_bill_subtitle'.tr(),
                accentColor: _blue,
                onTap: () {
                  HapticUtils.primaryTap();
                  final baseCurrency = ref.read(baseCurrencyProvider).valueOrNull ?? 'USD';
                  showModalBottomSheet<void>(
                    context: context,
                    isScrollControlled: true,
                    backgroundColor: Colors.transparent,
                    builder: (_) => ReceiptEntrySheet(
                      groupId: groupId,
                      defaultCurrency: groupCurrency ?? baseCurrency,
                    ),
                  );
                },
              ),

              const Spacer(),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Entry type card
// ---------------------------------------------------------------------------
class _EntryTypeCard extends StatefulWidget {
  const _EntryTypeCard({
    required this.icon,
    required this.iconColor,
    required this.iconBg,
    required this.title,
    required this.subtitle,
    required this.accentColor,
    required this.onTap,
  });

  final IconData icon;
  final Color    iconColor;
  final Color    iconBg;
  final String   title;
  final String   subtitle;
  final Color    accentColor;
  final VoidCallback onTap;

  @override
  State<_EntryTypeCard> createState() => _EntryTypeCardState();
}

class _EntryTypeCardState extends State<_EntryTypeCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double>    _scale;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 120),
    );
    _scale = Tween<double>(begin: 1.0, end: 0.97).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return GestureDetector(
      onTapDown: (_) => _ctrl.forward(),
      onTapUp: (_) {
        _ctrl.reverse();
        widget.onTap();
      },
      onTapCancel: () => _ctrl.reverse(),
      child: ScaleTransition(
        scale: _scale,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: widget.accentColor.withValues(alpha: 0.25),
              width: 1.5,
            ),
          ),
          child: Row(
            children: [
              // Icon badge
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: widget.iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(widget.icon, color: widget.iconColor, size: 26),
              ),
              const SizedBox(width: 16),

              // Text
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      widget.title,
                      style: TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 15,
                        letterSpacing: 0.4,
                        color: widget.accentColor,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      widget.subtitle,
                      style: TextStyle(
                        fontSize: 12,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),

              // Chevron
              Icon(
                Icons.chevron_right_rounded,
                color: widget.accentColor.withValues(alpha: 0.7),
                size: 22,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
