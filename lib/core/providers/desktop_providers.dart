import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Holds the group ID + name currently shown in the desktop detail pane.
/// Null means no group is selected (show placeholder).
class SelectedGroupState {
  const SelectedGroupState({this.groupId, this.groupName});
  final String? groupId;
  final String? groupName;
}

class SelectedGroupNotifier extends Notifier<SelectedGroupState> {
  @override
  SelectedGroupState build() => const SelectedGroupState();

  void select(String groupId, String groupName) {
    state = SelectedGroupState(groupId: groupId, groupName: groupName);
  }

  void clear() {
    state = const SelectedGroupState();
  }
}

final selectedGroupProvider =
    NotifierProvider<SelectedGroupNotifier, SelectedGroupState>(
  SelectedGroupNotifier.new,
);
