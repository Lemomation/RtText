/// A participant in a group conversation (human or AI bot).
class ConversationMember {
  const ConversationMember({
    required this.id,
    required this.conversationId,
    this.userId,
    this.botId,
    this.role = 'member',
    this.name = '',
    this.avatarUrl,
    this.isBot = false,
    this.joinedAt,
    this.lastReadAt,
  });

  final String id;
  final String conversationId;
  final String? userId;
  final String? botId;
  final String role;
  final String name;
  final String? avatarUrl;
  final bool isBot;
  final DateTime? joinedAt;
  final DateTime? lastReadAt;

  bool get isAdmin => role == 'admin';

  factory ConversationMember.fromMap(Map<String, dynamic> map) =>
      ConversationMember(
        id: (map['member_id'] ?? map['id'] ?? '') as String,
        conversationId: (map['conversation_id'] ?? '') as String,
        userId: map['user_id'] as String?,
        botId: map['bot_id'] as String?,
        role: (map['role'] as String?) ?? 'member',
        name: (map['name'] as String?) ?? '',
        avatarUrl: map['avatar_url'] as String?,
        isBot: (map['is_bot'] as bool?) ?? (map['bot_id'] != null),
        joinedAt: map['joined_at'] == null
            ? null
            : DateTime.tryParse(map['joined_at'] as String),
        lastReadAt: map['last_read_at'] == null
            ? null
            : DateTime.tryParse(map['last_read_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'conversation_id': conversationId,
        if (userId != null) 'user_id': userId,
        if (botId != null) 'bot_id': botId,
        'role': role,
        if (joinedAt != null) 'joined_at': joinedAt!.toIso8601String(),
        if (lastReadAt != null) 'last_read_at': lastReadAt!.toIso8601String(),
      };
}
