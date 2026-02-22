import '../../domain/entities/profile.dart';

class ProfileModel extends Profile {
  const ProfileModel({
    required super.id,
    required super.name,
    super.nickname,
    super.avatarUrl,
    super.defaultCurrency = 'USD',
    super.isGhost = false,
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    final rawGhost = json['is_ghost'];
    // Strictly handle Supabase bool vs SQLite int
    final bool isGhost = rawGhost is bool ? rawGhost : (rawGhost == 1 || rawGhost == '1');

    return ProfileModel(
      id: json['id'] as String,
      name: (json['name'] as String?) ?? '',
      nickname: json['nickname'] as String?,
      avatarUrl: json['avatar_url'] as String?,
      defaultCurrency: (json['default_currency'] as String?) ?? 'USD',
      isGhost: isGhost,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        if (nickname != null) 'nickname': nickname,
        if (avatarUrl != null) 'avatar_url': avatarUrl,
        'default_currency': defaultCurrency,
        'is_ghost': isGhost,
      };
}
