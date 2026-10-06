/// An AI character. `sysPrompt` is only ever populated for bots the current
/// user owns (the public `public_bots` view never exposes it).
class Bot {
  const Bot({
    required this.id,
    this.ownerId,
    required this.name,
    this.bio,
    this.description,
    this.pfpUrl,
    this.isPublic = true,
    this.sysPrompt,
    this.bubbleColor,
    this.createdAt,
  });

  final String id;
  final String? ownerId;
  final String name;
  final String? bio;
  final String? description;
  final String? pfpUrl;
  final bool isPublic;
  final String? sysPrompt;

  /// Hex tint (`#RRGGBB`) for this bot's chat bubbles; null = theme default.
  final String? bubbleColor;
  final DateTime? createdAt;

  factory Bot.fromMap(Map<String, dynamic> map) => Bot(
        id: map['id'] as String,
        ownerId: map['owner'] as String?,
        name: (map['name'] as String?) ?? '',
        bio: map['bio'] as String?,
        description: map['description'] as String?,
        pfpUrl: map['pfp_url'] as String?,
        isPublic: (map['is_public'] as bool?) ?? true,
        sysPrompt: map['sys_prompt'] as String?,
        bubbleColor: map['bubble_color'] as String?,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'owner': ownerId,
        'name': name,
        'bio': bio,
        'description': description,
        'pfp_url': pfpUrl,
        'is_public': isPublic,
        if (sysPrompt != null) 'sys_prompt': sysPrompt,
        if (bubbleColor != null) 'bubble_color': bubbleColor,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
