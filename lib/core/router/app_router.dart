import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../layout/adaptive_shell.dart';
import '../services/biometric_service.dart';
import '../../features/auth/presentation/screens/biometric_gate_screen.dart';
import '../../features/auth/presentation/screens/login_screen.dart';
import '../../features/auth/presentation/screens/register_screen.dart';
import '../../features/dashboard/presentation/screens/dashboard_screen.dart';
import '../../features/dashboard/presentation/screens/group_detail_screen.dart';
import '../../features/dashboard/presentation/screens/invite_member_screen.dart';
import '../../features/expenses/presentation/screens/add_expense_screen.dart';
import '../../features/expenses/presentation/screens/edit_expense_screen.dart';
import '../../features/expenses/presentation/screens/group_picker_screen.dart';
import '../../features/activity/presentation/screens/activity_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import '../../features/wallet/presentation/screens/wallet_entry_type_screen.dart';
import '../../features/wallet/presentation/screens/wallet_entry_detail_screen.dart';
import '../../features/dashboard/presentation/screens/group_expense_detail_screen.dart';
import '../../data/models/expense_model.dart';
import '../../features/groups/presentation/screens/create_group_screen.dart';
import '../../features/groups/presentation/screens/edit_group_screen.dart';
import '../../features/groups/presentation/screens/group_info_screen.dart';
import '../../data/models/group_model.dart';
import '../../features/groups/presentation/screens/groups_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/friends/presentation/screens/invite_friend_screen.dart';

final class AppRouter {
  AppRouter._();

  static const String login = '/login';
  static const String register = '/register';
  static const String biometricGate = '/biometric-gate';
  static const String dashboard = '/';
  static const String activity = '/activity';
  static const String wallet = '/wallet';
  static const String groups = '/groups';
  static const String createGroup = '/create-group';
  static const String settings = '/settings';
  static const String addExpense       = '/add-expense';
  static const String editExpense      = '/group/:id/expense/:expenseId';
  static const String groupPicker      = '/add-expense/choose-group';
  static const String groupDetail      = '/group/:id';
  static const String inviteMember     = '/group/:id/invite';
  static const String inviteFriend     = '/invite-friend';
  static const String walletEntryType       = '/wallet/add';
  static const String walletEntryDetail      = '/wallet/entry';
  static const String groupExpenseDetail     = '/group-expense-detail';
  static const String groupInfo              = '/group-info';
  static const String editGroup              = '/group/:id/edit';

  static GoRouter create() {
    final bio = BiometricService.instance;
    return GoRouter(
      initialLocation: dashboard,
      debugLogDiagnostics: true,
      redirect: (context, state) async {
        try {
          final user = Supabase.instance.client.auth.currentUser;
          final isLogin    = state.matchedLocation == login;
          final isRegister = state.matchedLocation == register;
          final isBiometricGate = state.matchedLocation == biometricGate;
          if (user == null && !isLogin && !isRegister) return login;
          if (user != null && isLogin) {
            final useBio = await bio.getUseBiometric();
            if (useBio) return biometricGate;
            return dashboard;
          }
          if (user != null && isBiometricGate) return null;
          if (user != null) {
            // Only gate if biometric is enabled AND the session hasn't been
            // unlocked yet in this process. Without this guard, every in-app
            // navigation push (e.g. /group/:id/invite) triggers a redirect
            // back to the biometric gate, silently discarding the intended
            // destination.
            if (!bio.sessionUnlocked) {
              final useBio = await bio.getUseBiometric();
              if (useBio) return biometricGate;
            }
          }
        } catch (_) {}
        return null;
      },
      refreshListenable: _AuthRefresh(),
      errorBuilder: (context, state) => Material(
        color: Theme.of(context).colorScheme.surface,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Page not found',
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurface,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  state.uri.toString(),
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      routes: [
        GoRoute(
          path: login,
          name: 'login',
          pageBuilder: (context, state) => NoTransitionPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const LoginScreen(),
            ),
          ),
        ),
        GoRoute(
          path: register,
          name: 'register',
          pageBuilder: (context, state) => NoTransitionPage(
            child: Material(
              color: const Color(0xFF0F172A),
              child: const RegisterScreen(),
            ),
          ),
        ),
        GoRoute(
          path: biometricGate,
          name: 'biometricGate',
          pageBuilder: (context, state) => NoTransitionPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const BiometricGateScreen(),
            ),
          ),
        ),

        // ── Shell: AdaptiveShell wraps Dashboard, Wallet, Groups, Activity, Settings ──
        ShellRoute(
          builder: (context, state, child) => AdaptiveShell(
            currentPath: state.matchedLocation,
            child: child,
          ),
          routes: [
            GoRoute(
              path: dashboard,
              name: 'dashboard',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: const DashboardScreen(),
                ),
              ),
            ),
            GoRoute(
              path: wallet,
              name: 'wallet',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: const WalletScreen(),
                ),
              ),
            ),
            GoRoute(
              path: activity,
              name: 'activity',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: const ActivityScreen(),
                ),
              ),
            ),
            GoRoute(
              path: groups,
              name: 'groups',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: const GroupsScreen(),
                ),
              ),
            ),
            GoRoute(
              path: settings,
              name: 'settings',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: const SettingsScreen(),
                ),
              ),
            ),
          ],
        ),

        // ── Invite friend (modal push, no shell nav bar) ─────────────────
        GoRoute(
          path: inviteFriend,
          name: 'inviteFriend',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const InviteFriendScreen(),
            ),
          ),
        ),

        // ── Create group (modal push, no shell nav bar) ───────────────────
        GoRoute(
          path: createGroup,
          name: 'createGroup',
          pageBuilder: (context, state) {
            final cb = state.extra as void Function(String, String)?;
            return MaterialPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: CreateGroupScreen(onGroupCreated: cb),
              ),
            );
          },
        ),

        // ── Modal flows (push on top, no shell nav bar) ────────────────────
        GoRoute(
          path: groupPicker,
          name: 'groupPicker',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const GroupPickerScreen(),
            ),
          ),
        ),
        // ── Wallet: Step 0 — entry type chooser ──────────────────────────
        GoRoute(
          path: walletEntryType,
          name: 'walletEntryType',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const WalletEntryTypeScreen(),
            ),
          ),
        ),

        // ── Group: info screen (tap from groups list) ─────────────────
        GoRoute(
          path: groupInfo,
          name: 'groupInfo',
          pageBuilder: (context, state) {
            final extra = state.extra;
            if (extra is! GroupModel) {
              return const NoTransitionPage(child: SizedBox.shrink());
            }
            return MaterialPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: GroupInfoScreen(group: extra),
              ),
            );
          },
        ),

        // ── Group: expense detail (info) screen ─────────────────────────
        GoRoute(
          path: groupExpenseDetail,
          name: 'groupExpenseDetail',
          pageBuilder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            if (extra == null || extra['expense'] is! ExpenseModel) {
              return const NoTransitionPage(child: SizedBox.shrink());
            }
            return MaterialPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: GroupExpenseDetailScreen(
                  expense:   extra['expense']  as ExpenseModel,
                  groupId:   extra['groupId']  as String? ?? '',
                  groupName: extra['groupName'] as String? ?? 'Group',
                ),
              ),
            );
          },
        ),

        // ── Wallet: entry detail (info) screen ────────────────────────────
        GoRoute(
          path: walletEntryDetail,
          name: 'walletEntryDetail',
          pageBuilder: (context, state) {
            final extra = state.extra;
            if (extra is! ExpenseModel) {
              return const NoTransitionPage(child: SizedBox.shrink());
            }
            return MaterialPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: WalletEntryDetailScreen(expense: extra),
              ),
            );
          },
        ),

        GoRoute(
          path: addExpense,
          name: 'addExpense',
          pageBuilder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return NoTransitionPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: AddExpenseScreen(
                  groupId: extra?['groupId'] as String? ?? '',
                  groupName: extra?['groupName'] as String? ?? 'Group',
                  initialIsIncome: extra?['isIncome'] as bool? ?? false,
                ),
              ),
            );
          },
        ),
        GoRoute(
          path: '/group/:id',
          name: 'groupDetail',
          pageBuilder: (context, state) {
            final id = state.pathParameters['id']!;
            final extra = state.extra as Map<String, dynamic>?;
            final name = extra?['groupName'] as String? ?? 'Group';
            return MaterialPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: GroupDetailScreen(groupId: id, groupName: name),
              ),
            );
          },
          routes: [
            GoRoute(
              path: 'expense/:expenseId',
              name: 'editExpense',
              pageBuilder: (context, state) {
                final groupId   = state.pathParameters['id']!;
                final expenseId = state.pathParameters['expenseId']!;
                // extra can be an ExpenseModel (from wallet tap-to-edit)
                // or a Map<String, dynamic> (from group detail screen).
                final extra = state.extra;
                final String groupName;
                if (extra is Map<String, dynamic>) {
                  groupName = extra['groupName'] as String? ?? 'Group';
                } else {
                  groupName = 'Wallet';
                }
                return MaterialPage(
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: EditExpenseScreen(
                      expenseId: expenseId,
                      groupId: groupId == 'wallet' ? '' : groupId,
                      groupName: groupName,
                    ),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'edit',
              name: 'editGroup',
              pageBuilder: (context, state) {
                final extra = state.extra;
                if (extra is! GroupModel) {
                  return const NoTransitionPage(child: SizedBox.shrink());
                }
                return MaterialPage(
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: EditGroupScreen(group: extra),
                  ),
                );
              },
            ),
            GoRoute(
              path: 'invite',
              name: 'inviteMember',
              pageBuilder: (context, state) {
                final groupId = state.pathParameters['id']!;
                final extra = state.extra as Map<String, dynamic>?;
                final groupName = extra?['groupName'] as String? ?? 'Group';
                return MaterialPage(
                  child: Material(
                    color: Theme.of(context).colorScheme.surface,
                    child: InviteMemberScreen(
                      groupId: groupId,
                      groupName: groupName,
                    ),
                  ),
                );
              },
            ),
          ],
        ),
      ],
    );
  }
}

/// Notifies when Supabase auth state changes so the router can redirect.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    try {
      Supabase.instance.client.auth.onAuthStateChange.listen((_) {
        notifyListeners();
      });
    } catch (_) {
      // Supabase not initialized (e.g. widget tests without credentials) — skip.
    }
  }
}
