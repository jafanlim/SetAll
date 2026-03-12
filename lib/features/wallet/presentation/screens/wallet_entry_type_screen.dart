import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/router/app_router.dart';
import '../../../../core/utils/haptic_utils.dart';

// ---------------------------------------------------------------------------
// Palette
// ---------------------------------------------------------------------------
const _purple     = Color(0xFF8B5CF6);
const _purpleDim  = Color(0x1A8B5CF6);
const _green      = Color(0xFF22C55E);
const _greenDim   = Color(0x1A22C55E);

/// Step 0 of the two-step wallet entry flow.
/// The user chooses between [ADD AN INCOME] and [ADD AN EXPENSE].
/// The choice is forwarded to [AddExpenseScreen] via route extras.
class WalletEntryTypeScreen extends StatelessWidget {
  const WalletEntryTypeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(
        title: const Text(
          'Add Wallet Entry',
          style: TextStyle(fontWeight: FontWeight.w800, fontSize: 18, letterSpacing: -0.3),
        ),
        backgroundColor: theme.colorScheme.surface,
        foregroundColor: theme.colorScheme.onSurface,
        elevation: 0,
        scrolledUnderElevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () {
            HapticUtils.lightTap();
            context.pop();
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
                'What type of entry?',
                style: theme.textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  fontSize: 22,
                  letterSpacing: -0.4,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                'Choose the direction of this wallet entry.',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 36),

              // ── Income Card ──────────────────────────────────────────────
              _EntryTypeCard(
                icon: Icons.arrow_downward_rounded,
                iconColor: _green,
                iconBg: _greenDim,
                title: 'ADD AN INCOME',
                subtitle: 'Salary, freelance, gift, investment return…',
                accentColor: _green,
                onTap: () {
                  HapticUtils.primaryTap();
                  context.push(
                    AppRouter.addExpense,
                    extra: {
                      'groupId':   '',
                      'groupName': '',
                      'isIncome':  true,
                    },
                  );
                },
              ),

              const SizedBox(height: 16),

              // ── Expense Card ─────────────────────────────────────────────
              _EntryTypeCard(
                icon: Icons.arrow_upward_rounded,
                iconColor: _purple,
                iconBg: _purpleDim,
                title: 'ADD AN EXPENSE',
                subtitle: 'Food, transport, bills, shopping, travel…',
                accentColor: _purple,
                onTap: () {
                  HapticUtils.primaryTap();
                  context.push(
                    AppRouter.addExpense,
                    extra: {
                      'groupId':   '',
                      'groupName': '',
                      'isIncome':  false,
                    },
                  );
                },
              ),

              const Spacer(),

              // ── Hint ─────────────────────────────────────────────────────
              Center(
                child: Text(
                  'You can also add group expenses from the Groups tab.',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  ),
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
