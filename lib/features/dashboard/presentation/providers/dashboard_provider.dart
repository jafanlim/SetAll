import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Summary balance: "You are owed" / "You owe" for dashboard.
class BalanceSummary {
  const BalanceSummary({
    this.youAreOwed = '0',
    this.youOwe = '0',
    this.currency = 'USD',
  });

  final String youAreOwed;
  final String youOwe;
  final String currency;
}

final dashboardSummaryProvider = FutureProvider<BalanceSummary>((ref) async {
  // TODO: Replace with Supabase fetch (expenses + splits aggregated by user)
  await Future<void>.delayed(const Duration(milliseconds: 300));
  return const BalanceSummary(youAreOwed: '0', youOwe: '0', currency: 'USD');
});

/// Placeholder list of groups for dashboard.
final dashboardGroupsProvider = FutureProvider<List<Map<String, String>>>((ref) async {
  // TODO: Replace with Supabase groups + group_members
  await Future<void>.delayed(const Duration(milliseconds: 200));
  return [
    {'id': '1', 'name': 'Trip to Paris'},
    {'id': '2', 'name': 'Household'},
  ];
});
