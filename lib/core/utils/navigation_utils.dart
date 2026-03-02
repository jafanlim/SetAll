import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../layout/adaptive_shell.dart';
import '../providers/desktop_providers.dart';

/// Navigate to a group — on desktop (≥ kDesktopBreakpoint) sets the detail
/// pane via [selectedGroupProvider]; on mobile/tablet pushes the full route.
void navigateToGroup({
  required BuildContext context,
  required WidgetRef ref,
  required String groupId,
  required String groupName,
}) {
  final isDesktop = defaultTargetPlatform == TargetPlatform.macOS ||
      defaultTargetPlatform == TargetPlatform.windows ||
      defaultTargetPlatform == TargetPlatform.linux;
  final width = MediaQuery.sizeOf(context).width;

  if (isDesktop && width >= kDesktopBreakpoint) {
    ref.read(selectedGroupProvider.notifier).select(groupId, groupName);
  } else {
    context.push('/group/$groupId', extra: {'groupName': groupName});
  }
}
