import '../../domain/entities/group.dart';

class GroupModel extends Group {
  const GroupModel({
    required super.id,
    required super.name,
    required super.creatorId,
    super.type = GroupType.normal,
  });

  static GroupType _typeFromString(String? v) {
    if (v == 'direct') return GroupType.direct;
    return GroupType.normal;
  }

  factory GroupModel.fromJson(Map<String, dynamic> json) {
    return GroupModel(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      creatorId: json['creator_id'] as String,
      type: _typeFromString(json['type'] as String?),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'creator_id': creatorId,
        'type': type.name,
      };
}
