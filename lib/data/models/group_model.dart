import '../../domain/entities/group.dart';

class GroupModel extends Group {
  const GroupModel({
    required super.id,
    required super.name,
    required super.creatorId,
    super.type = GroupType.normal,
    super.iconName,
    super.colorValue,
    super.avatarUrl,
    super.defaultCurrency,
    super.settledAt,
    super.settledBy,
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
      iconName: json['icon_name'] as String?,
      colorValue: json['color_value'] as int?,
      avatarUrl: json['avatar_url'] as String?,
      defaultCurrency: json['default_currency'] as String?,
      settledAt: json['settled_at'] as String?,
      settledBy: json['settled_by'] as String?,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'creator_id': creatorId,
        'type': type.name,
        if (iconName != null) 'icon_name': iconName,
        if (colorValue != null) 'color_value': colorValue,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        if (defaultCurrency != null) 'default_currency': defaultCurrency,
        'settled_at': settledAt,
        'settled_by': settledBy,
      };
}
