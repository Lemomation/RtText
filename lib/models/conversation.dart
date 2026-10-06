/// A chat thread with either a bot ([botId] set, [dmUserId] null) or another
/// human ([dmUserId] set, [botId] null).
///
/// [botName], [botPfpUrl], [peerName], [peerAvatarUrl], and
/// [lastMessagePreview] are enrichment fields filled in by the conversations
/// service (not stored on the row itself).
class Conversation {
  const Conversation({
    required this.id,
    required this.userId,
    required this.botId,
    this.dmUserId,
    this.lastMessageAt,
    this.createdAt,
    this.botName,
    this.botPfpUrl,
    this.peerName,
    this.peerAvatarUrl,
    this.lastMessagePreview,
  });

  final String id;
  final String userId;
  final String botId;

  /// The other human in a DM chat; null for bot chats.
  final String? dmUserId;

  final DateTime? lastMessageAt;
  final DateTime? createdAt;

  final String? botName;
  final String? botPfpUrl;

  final String? peerName;
  final String? peerAvatarUrl;
  final String? lastMessagePreview;

  bool get isDm => dmUserId != null;

  Conversation copyWith({
    String? botName,
    String? botPfpUrl,
    String? peerName,
    String? peerAvatarUrl,
    String? lastMessagePreview,
  }) =>
      Conversation(
        id: id,
        userId: userId,
        botId: botId,
        dmUserId: dmUserId,
        lastMessageAt: lastMessageAt,
        createdAt: createdAt,
        botName: botName ?? this.botName,
        botPfpUrl: botPfpUrl ?? this.botPfpUrl,
        peerName: peerName ?? this.peerName,
        peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
      );

  factory Conversation.fromMap(Map<String, dynamic> map) => Conversation(
        id: map['id'] as String,
        userId: map['user_id'] as String? ?? '',
        botId: map['bot_id'] as String? ?? '',
        dmUserId: map['dm_user_id'] as String?,
        lastMessageAt: map['last_message_at'] == null
            ? null
            : DateTime.parse(map['last_message_at'] as String),
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'bot_id': botId,
        if (lastMessageAt != null)
          'last_message_at': lastMessageAt!.toIso8601String(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
