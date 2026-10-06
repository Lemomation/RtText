/// A user profile row (public.profiles).
class Profile {
  const Profile({
    required this.id,
    required this.username,
    this.avatarUrl,
    this.beads = 0,
    this.createdAt,
  });

  final String id;
  final String username;
  final String? avatarUrl;
  final int beads;
  final DateTime? createdAt;

  factory Profile.fromMap(Map<String, dynamic> map) => Profile(
        id: map['id'] as String,
        username: (map['username'] as String?) ?? '',
        avatarUrl: map['avatar_url'] as String?,
        beads: (map['beads'] as num?)?.toInt() ?? 0,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'username': username,
        'avatar_url': avatarUrl,
        'beads': beads,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
