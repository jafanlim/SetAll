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
    // SQLite stores booleans as integers (0/1); Supabase returns true Dart bools.
    // Handle both to avoid a TypeError on mobile.
    final rawGhost = json['is_ghost'];
    final isGhost = switch (rawGhost) {
      bool b  => b,
      int i   => i != 0,
      _       => false,
    };
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
