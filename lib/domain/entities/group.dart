/// Cost-sharing group entity.
class Group {
  const Group({
    required this.id,
    required this.name,
    required this.creatorId,
  });

  final String id;
  final String name;
  final String creatorId;
}
