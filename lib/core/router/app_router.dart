import 'package:flutter/foundation.dart';
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
import '../../features/expenses/presentation/screens/group_expense_entry_type_screen.dart';
import '../../features/expenses/presentation/screens/group_picker_screen.dart';
import '../../features/activity/presentation/screens/activity_screen.dart';
import '../../features/analytics/presentation/screens/analytics_screen.dart';
import '../../features/wallet/presentation/screens/wallet_screen.dart';
import '../../features/wallet/presentation/screens/wallet_entry_type_screen.dart';
import '../../features/wallet/presentation/screens/wallet_entry_detail_screen.dart';
import '../../features/dashboard/presentation/screens/group_expense_detail_screen.dart';
import '../../data/models/expense_model.dart';
import '../../data/models/wallet_entry_model.dart';
import '../../features/groups/presentation/screens/create_group_screen.dart';
import '../../features/groups/presentation/screens/edit_group_screen.dart';
import '../../features/groups/presentation/screens/group_info_screen.dart';
import '../../data/models/group_model.dart';
import '../../features/groups/presentation/screens/groups_screen.dart';
import '../../features/settings/presentation/screens/settings_screen.dart';
import '../../features/settings/presentation/screens/security_screen.dart';
import '../../features/settings/presentation/screens/notifications_screen.dart';
import '../../features/settings/presentation/screens/regional_screen.dart';
import '../../features/settings/presentation/screens/change_password_screen.dart';
import '../../features/settings/presentation/screens/data_usage_screen.dart';
import '../../features/friends/presentation/screens/invite_friend_screen.dart';
import '../../features/web/download_screen.dart';
import '../../features/web/legal_screen.dart';
import '../../features/insights/presentation/screens/insights_screen.dart';
import '../../features/receipt/presentation/scan_destination_screen.dart';

final class AppRouter {
  AppRouter._();

  /// Shared navigator key — allows non-widget code (e.g. DeepLinkService)
  /// to push routes without a BuildContext.
  static final navigatorKey = GlobalKey<NavigatorState>();

  static const String login = '/login';
  static const String register = '/register';
  static const String biometricGate = '/biometric-gate';
  static const String dashboard = '/';
  static const String activity   = '/activity';
  static const String analytics  = '/analytics';
  static const String wallet = '/wallet';
  static const String groups = '/groups';
  static const String createGroup = '/create-group';
  static const String settings            = '/settings';
  static const String settingsSecurity     = '/settings/security';
  static const String settingsNotifications = '/settings/notifications';
  static const String settingsDataUsage    = '/settings/data-usage';
  static const String settingsRegional     = '/settings/regional';
  static const String settingsChangePassword = '/settings/change-password';
  static const String addExpense       = '/add-expense';
  static const String editExpense      = '/group/:id/expense/:expenseId';
  static const String groupPicker      = '/add-expense/choose-group';
  static const String groupExpenseEntryType = '/add-expense/entry-type';
  static const String groupDetail      = '/group/:id';
  static const String inviteMember     = '/group/:id/invite';
  static const String inviteFriend     = '/invite-friend';
  static const String walletEntryType       = '/wallet/add';
  static const String walletEntryDetail      = '/wallet/entry';
  static const String walletEntryEdit        = '/wallet/entry/edit/:id';
  static const String walletImport           = '/wallet/import';
  static const String groupExpenseDetail     = '/group-expense-detail';
  static const String groupInfo              = '/group-info';
  static const String editGroup              = '/group/:id/edit';
  static const String insights = '/insights';
  static const String scanReceipt = '/scan-receipt';
  static const String budgets    = '/budgets';
  static const String recurring   = '/recurring';
  static const String alertPrefs  = '/alert-prefs';
  static const String download = '/download';
  static const String privacy  = '/privacy';
  static const String terms    = '/terms';

  static GoRouter create() {
    final bio = BiometricService.instance;
    return GoRouter(
      navigatorKey: navigatorKey,
      initialLocation: kIsWeb ? login : dashboard,
      debugLogDiagnostics: true,
      redirect: (context, state) async {
        try {
          final user = Supabase.instance.client.auth.currentUser;
          final loc = state.matchedLocation;
          final isLogin         = loc == login;
          final isRegister      = loc == register;
          final isBiometricGate = loc == biometricGate;
          final isPublic        = loc == download || loc == privacy || loc == terms;
          if (loc == '/dashboard') {
            if (user == null) return login;
            return dashboard;
          }
          if (user == null && !isLogin && !isRegister && !isPublic) {
            return login;
          }
          if (user != null && isLogin) {
            // Guard: only users who completed registration may proceed.
            // handle_new_user trigger creates a profile for every OAuth user
            // with registration_complete=false; only the register screen or
            // email confirmation sets it to true.
            try {
              final rows = await Supabase.instance.client
                  .from('profiles')
                  .select('registration_complete')
                  .eq('id', user.id)
                  .limit(1);
              final isComplete = (rows as List).isNotEmpty &&
                  rows.first['registration_complete'] == true;
              if (!isComplete) {
                LoginScreen.pendingNoAccountDialog = true;
                await Supabase.instance.client.auth.signOut();
                return login;
              }
            } catch (_) {
              // Allow through if the check fails — safer than locking out real users.
            }
            final useBio = await bio.getUseBiometric();
            if (useBio) return biometricGate;
            return dashboard;
          }
          if (user != null && isBiometricGate) return null;
          if (user != null) {
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
              path: analytics,
              name: 'analytics',
              pageBuilder: (context, state) => NoTransitionPage(
                child: Material(
                  color: Theme.of(context).colorScheme.surface,
                  child: const AnalyticsScreen(),
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

        // ── Settings sub-screens (outside shell so they push over everything) ──
        GoRoute(
          path: settingsSecurity,
          name: 'settingsSecurity',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const SecurityScreen(),
            ),
          ),
        ),
        GoRoute(
          path: settingsNotifications,
          name: 'settingsNotifications',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const NotificationsScreen(),
            ),
          ),
        ),
        GoRoute(
          path: settingsRegional,
          name: 'settingsRegional',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const RegionalScreen(),
            ),
          ),
        ),
        GoRoute(
          path: settingsDataUsage,
          name: 'settingsDataUsage',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const DataUsageScreen(),
            ),
          ),
        ),
        GoRoute(
          path: settingsChangePassword,
          name: 'settingsChangePassword',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const ChangePasswordScreen(),
            ),
          ),
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


        // ── Group expense: Step 0 — entry type chooser ────────────────────
        GoRoute(
          path: groupExpenseEntryType,
          name: 'groupExpenseEntryType',
          pageBuilder: (context, state) {
            final extra = state.extra as Map<String, dynamic>?;
            return MaterialPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: GroupExpenseEntryTypeScreen(
                  groupId: extra?['groupId'] as String? ?? '',
                  groupName: extra?['groupName'] as String? ?? 'Group',
                  groupCurrency: extra?['groupCurrency'] as String?,
                ),
              ),
            );
          },
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
            if (extra is! WalletEntryModel) {
              return const NoTransitionPage(child: SizedBox.shrink());
            }
            return MaterialPage(
              child: Material(
                color: Theme.of(context).colorScheme.surface,
                child: WalletEntryDetailScreen(expense: extra),
              ),
            );
          },
          routes: [
            // ── Wallet: entry edit screen (reuses WalletEntryTypeScreen flow)
            GoRoute(
              path: 'edit/:id',
              name: 'walletEntryEdit',
              pageBuilder: (context, state) {
                final extra = state.extra;
                if (extra is! WalletEntryModel) {
                  return const NoTransitionPage(child: SizedBox.shrink());
                }
                return MaterialPage(
                  child: AddExpenseScreen(
                    groupId: '',
                    existingWalletEntry: extra,
                  ),
                );
              },
            ),
          ],
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
                  initialCurrency: extra?['groupCurrency'] as String?,
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


        // ── Scan Receipt destination chooser (quick action) ─────────────
        GoRoute(
          path: scanReceipt,
          name: 'scanReceipt',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const ScanDestinationScreen(),
            ),
          ),
        ),

        // ── AI Insights Panel (pushed over dashboard, back-swipe supported) ──
        GoRoute(
          path: insights,
          name: 'insights',
          pageBuilder: (context, state) => MaterialPage(
            child: Material(
              color: Theme.of(context).colorScheme.surface,
              child: const InsightsScreen(),
            ),
          ),
        ),

        // ── Public web routes (no auth required) ──────────────────────────
        GoRoute(
          path: download,
          name: 'download',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: DownloadScreen(),
          ),
        ),
        GoRoute(
          path: privacy,
          name: 'privacy',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LegalScreen(
              title: 'Privacy Policy',
              assetPath: 'assets/legal/privacy.md',
            ),
          ),
        ),
        GoRoute(
          path: terms,
          name: 'terms',
          pageBuilder: (context, state) => const NoTransitionPage(
            child: LegalScreen(
              title: 'Terms of Service',
              assetPath: 'assets/legal/terms.md',
            ),
          ),
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
