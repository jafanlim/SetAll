import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/providers/setall_providers.dart';

/// Small chip that shows "from `group`" when a wallet entry is a mirror of a
/// group expense. Resolves the group name once on mount.
class GroupBadge extends StatefulWidget {
  const GroupBadge({super.key, required this.sourceExpenseId});
  final String sourceExpenseId;

  @override
  State<GroupBadge> createState() => _GroupBadgeState();
}

class _GroupBadgeState extends State<GroupBadge> {
  String? _groupName;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    try {
      // listen: false → getElementForInheritedWidgetOfExactType, which is safe
      // to call from initState. The default (listen: true) does a dependency
      // lookup that throws "before initState() completed" in debug builds; that
      // throw was being swallowed by the catch below, so the badge silently fell
      // back to "from a group" (never the real name) in every debug build.
      final container = ProviderScope.containerOf(context, listen: false);
      final repo = container.read(setAllRepositoryProvider);
      final name = await repo.sourceGroupName(widget.sourceExpenseId);
      if (mounted) setState(() { _groupName = name; _loaded = true; });
    } catch (_) {
      if (mounted) setState(() => _loaded = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!_loaded) return const SizedBox.shrink();
    final label = _groupName ?? 'a group';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: const Color(0xFF8B5CF6).withAlpha(25),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Text(
        'from $label',
        style: const TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w600,
          color: Color(0xFF8B5CF6),
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }
}
