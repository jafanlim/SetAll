/// User profile entity.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.nickname,
    this.avatarUrl,
    this.defaultCurrency = 'USD',
    this.isGhost = false,
  });

  final String id;

  /// Display name (required, set on signup).
  final String name;

  /// Optional @handle, unique across the platform.
  final String? nickname;

  /// Optional avatar URL (future: file upload).
  final String? avatarUrl;

  final String defaultCurrency;

  /// True for synthetic ghost users who have not yet signed up.
  final bool isGhost;

  /// The short label shown in avatars: nickname if set, else first character of name.
  String get displayInitial {
    if (nickname != null && nickname!.isNotEmpty) {
      return nickname![0].toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  /// The displayed label: nickname (@handle) if set, else name.
  String get displayLabel {
    if (nickname != null && nickname!.isNotEmpty) return '@$nickname';
    return name;
  }
}
