import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_actions/quick_actions.dart';

// HOTFIX-03: Fixed quick actions.
// Fix 1: Static Info.plist entries removed — Dart is sole registration source.
// Fix 2: Pending shortcut stored; navigation fires after GoRouter is ready,
//         not during initialize() which fires before the shell mounts.
class QuickActionsService {
  static const _qa = QuickActions();
  static String? _pending;

  static void init(BuildContext context) {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    _qa.initialize((type) {
      _pending = type;
      _tryNavigate(context); // succeeds on warm launch, no-ops on cold launch
    });
    _qa.setShortcutItems(const [
      ShortcutItem(
        type: 'action_add_expense',
        localizedTitle: 'Add Expense',
        icon: 'plus.circle',
      ),
      ShortcutItem(
        type: 'action_wallet_entry',
        localizedTitle: 'Wallet Entry',
        icon: 'creditcard',
      ),
      ShortcutItem(
        type: 'action_open_groups',
        localizedTitle: 'Groups',
        icon: 'person.3',
      ),
    ]);
  }

  // Call once from the first mounted screen after auth (dashboard).
  // Drains any shortcut that arrived before GoRouter was ready.
  static void drainPending(BuildContext context) {
    if (_pending != null) _tryNavigate(context);
  }

  static void _tryNavigate(BuildContext context) {
    final t = _pending;
    if (t == null) return;
    try {
      final router = GoRouter.of(context);
      switch (t) {
        case 'action_add_expense':
          router.go('/add-expense');
        case 'action_wallet_entry':
          router.go('/wallet/add');
        case 'action_open_groups':
          router.go('/groups');
      }
      _pending = null;
    } catch (_) {
      // Router not ready — _pending preserved for next drain attempt.
    }
  }
}
