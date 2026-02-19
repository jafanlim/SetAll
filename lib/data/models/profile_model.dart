import '../../domain/entities/profile.dart';

class ProfileModel extends Profile {
  const ProfileModel({
    required super.id,
    required super.name,
    super.defaultCurrency = 'USD',
  });

  factory ProfileModel.fromJson(Map<String, dynamic> json) {
    return ProfileModel(
      id: json['id'] as String,
      name: json['name'] as String,
      defaultCurrency: (json['default_currency'] as String?) ?? 'USD',
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'default_currency': defaultCurrency,
      };
}
