/// User profile entity.
class Profile {
  const Profile({
    required this.id,
    required this.name,
    this.defaultCurrency = 'USD',
  });

  final String id;
  final String name;
  final String defaultCurrency;
}
