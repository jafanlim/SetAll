import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/setall_providers.dart';
import '../../../core/utils/haptic_utils.dart';
import 'receipt_entry_sheet.dart';

class ScanDestinationScreen extends ConsumerWidget {
  const ScanDestinationScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final baseCurrency = ref.watch(baseCurrencyProvider).value ?? 'USD';
    final groupsAsync = ref.watch(myGroupsProvider);

    return Scaffold(
      backgroundColor: theme.colorScheme.surface,
      appBar: AppBar(title: Text('receipt.scan_destination_title'.tr())),
      body: ListView(
        children: [
          // ── Personal wallet ───────────────────────────────────────────
          _DestinationTile(
            icon: Icons.wallet_rounded,
            label: 'receipt.destination_personal'.tr(),
            onTap: () => _openScanner(context, null, baseCurrency),
          ),
          const Divider(height: 1),

          // ── Groups ────────────────────────────────────────────────────
          groupsAsync.when(
            data: (groups) {
              if (groups.isEmpty) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Text(
                      'groups.no_groups'.tr(),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                );
              }
              return Column(
                children: groups.map((group) {
                  return _DestinationTile(
                    icon: Icons.group_rounded,
                    label: group.name,
                    onTap: () => _openScanner(context, group.id, baseCurrency),
                  );
                }).toList(),
              );
            },
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child: Center(child: CircularProgressIndicator()),
            ),
            error: (error, _) => Center(
              child: Padding(
                padding: const EdgeInsets.all(32),
                child: Text(
                  '$error',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _openScanner(
    BuildContext context,
    String? groupId,
    String baseCurrency,
  ) {
    HapticUtils.primaryTap();
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          ReceiptEntrySheet(groupId: groupId, defaultCurrency: baseCurrency),
    );
  }
}

class _DestinationTile extends StatelessWidget {
  const _DestinationTile({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: Icon(icon, color: theme.colorScheme.primary),
      title: Text(label),
      trailing: Icon(
        Icons.chevron_right,
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}
