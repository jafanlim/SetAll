import 'dart:io';

import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_actions/quick_actions.dart';

// FEAT-09: iOS Home Screen Quick Actions.
// Registers 3 shortcuts on the home screen icon long-press.
// Must be initialized AFTER GoRouter is ready (call from SetAllApp.initState or
// the first frame after MaterialApp.router is mounted).
class QuickActionsService {
  static const _quickActions = QuickActions();

  static void init(BuildContext context) {
    if (!Platform.isIOS && !Platform.isAndroid) return;

    _quickActions.initialize((shortcutType) {
      switch (shortcutType) {
        case 'add_expense':
          context.go('/add-expense');
          break;
        case 'add_wallet_entry':
          context.go('/wallet/add');
          break;
        case 'open_groups':
          context.go('/groups');
          break;
      }
    });

    _quickActions.setShortcutItems([
      const ShortcutItem(
        type: 'add_expense',
        localizedTitle: 'Add Expense',
        icon: 'plus.circle',
      ),
      const ShortcutItem(
        type: 'add_wallet_entry',
        localizedTitle: 'Wallet Entry',
        icon: 'wallet.pass',
      ),
      const ShortcutItem(
        type: 'open_groups',
        localizedTitle: 'Groups',
        icon: 'person.3',
      ),
    ]);
  }
}
