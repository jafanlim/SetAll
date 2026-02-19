/// Whether a group is a regular multi-person group or a 1-on-1 direct group.
enum GroupType { normal, direct }

/// Cost-sharing group entity.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.creatorId,
    this.type = GroupType.normal,
  });

  final String id;
  final String name;
  final String creatorId;

  /// 'normal' = shared group; 'direct' = 1-on-1 friend expense group.
  final GroupType type;

  bool get isDirect => type == GroupType.direct;
}
