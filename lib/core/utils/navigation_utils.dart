import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../data/models/group_model.dart';

/// Navigate to a group — pushes the full-screen group detail route.
void navigateToGroup({
  required BuildContext context,
  required WidgetRef ref,
  required String groupId,
  required String groupName,
  GroupModel? group,
}) {
  context.push('/group/$groupId', extra: {'groupName': groupName});
}
