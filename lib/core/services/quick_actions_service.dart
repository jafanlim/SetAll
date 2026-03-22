import 'dart:io';
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:quick_actions/quick_actions.dart';

// HOTFIX-03: Fixed quick actions.
// Fix 1: Static Info.plist entries removed — Dart is sole registration source.
// Fix 2: Pending shortcut stored; navigation fires after GoRouter is ready.
// Fix 3: Store GoRouter ref (not BuildContext) so warm-launch nav works even
//         when the dashboard context has been unmounted/replaced.
class QuickActionsService {
  static const _qa = QuickActions();
  static String? _pending;
  static GoRouter? _router;

  static void init(BuildContext context) {
    if (!Platform.isIOS && !Platform.isAndroid) return;
    _qa.initialize((type) {
      _pending = type;
      // Warm launch: router already stored — navigate immediately.
      // Cold launch: router not yet set — dashboard drain will fire later.
      if (_router != null) _tryNavigate();
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
    try {
      _router = GoRouter.of(context);
    } catch (_) {
      return;
    }
    if (_pending != null) _tryNavigate();
  }

  static void _tryNavigate() {
    final t = _pending;
    final r = _router;
    if (t == null || r == null) return;
    _pending = null;
    // go() to dashboard first to establish a back-stack root, then
    // push() the target after a microtask so GoRouter has settled.
    // Without the delay, push() fires before the new stack is ready
    // and close/back gets "nothing to pop".
    switch (t) {
      case 'action_add_expense':
        r.go('/');
        Future.microtask(() => r.push('/add-expense/choose-group'));
      case 'action_wallet_entry':
        r.go('/');
        Future.microtask(() => r.push('/wallet/add'));
      case 'action_open_groups':
        r.go('/groups');
    }
  }
}
