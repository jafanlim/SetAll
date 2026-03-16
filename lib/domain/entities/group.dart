/// Whether a group is a regular multi-person group or a 1-on-1 direct group.
enum GroupType { normal, direct }

/// Cost-sharing group entity.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.creatorId,
    this.type = GroupType.normal,
    this.iconName,
    this.colorValue,
    this.avatarUrl,
    this.defaultCurrency,
  });

  final String id;
  final String name;
  final String creatorId;

  /// 'normal' = shared group; 'direct' = 1-on-1 friend expense group.
  final GroupType type;

  /// Material icon name (e.g. 'home_outlined', 'flight_outlined'). NULL = default.
  final String? iconName;

  /// Accent colour as ARGB integer. NULL = use default teal.
  final int? colorValue;

  /// Supabase Storage path for the group avatar photo. NULL = use icon/initials.
  final String? avatarUrl;

  /// Default settlement currency for this group. NULL = use user's base currency.
  final String? defaultCurrency;

  bool get isDirect => type == GroupType.direct;
}
