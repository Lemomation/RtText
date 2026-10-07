/// A chat thread with either a bot ([botId] set, [dmUserId] null) or another
/// human ([dmUserId] set, [botId] null).
///
/// [botName], [botPfpUrl], [peerName], [peerAvatarUrl], [lastMessagePreview],
/// and [unreadCount] are enrichment fields filled in by the conversations
/// service (not stored on the row itself).
class Conversation {
  const Conversation({
    required this.id,
    required this.userId,
    required this.botId,
    this.dmUserId,
    this.lastMessageAt,
    this.createdAt,
    this.userLastReadAt,
    this.dmUserLastReadAt,
    this.botName,
    this.botPfpUrl,
    this.peerName,
    this.peerAvatarUrl,
    this.lastMessagePreview,
    this.unreadCount = 0,
  });

  final String id;
  final String userId;
  final String botId;

  /// The other human in a DM chat; null for bot chats.
  final String? dmUserId;

  final DateTime? lastMessageAt;
  final DateTime? createdAt;
  final DateTime? userLastReadAt;
  final DateTime? dmUserLastReadAt;

  final String? botName;
  final String? botPfpUrl;

  final String? peerName;
  final String? peerAvatarUrl;
  final String? lastMessagePreview;
  final int unreadCount;

  bool get isDm => dmUserId != null;

  /// Returns the other participant's user id in a DM given the caller's [myUid].
  /// Returns null if this is a bot chat.
  String? peerIdFor(String myUid) {
    if (!isDm) return null;
    return userId == myUid ? dmUserId : userId;
  }

  /// Returns when [myUid] last read this conversation.
  DateTime? lastReadAtFor(String myUid) {
    if (userId == myUid) return userLastReadAt;
    if (dmUserId == myUid) return dmUserLastReadAt;
    return null;
  }

  /// Returns when the other participant in a DM last read this conversation.
  DateTime? peerLastReadAtFor(String myUid) {
    if (!isDm) return null;
    if (userId == myUid) return dmUserLastReadAt;
    if (dmUserId == myUid) return userLastReadAt;
    return null;
  }

  Conversation copyWith({
    String? botName,
    String? botPfpUrl,
    String? peerName,
    String? peerAvatarUrl,
    String? lastMessagePreview,
    int? unreadCount,
    DateTime? userLastReadAt,
    DateTime? dmUserLastReadAt,
  }) =>
      Conversation(
        id: id,
        userId: userId,
        botId: botId,
        dmUserId: dmUserId,
        lastMessageAt: lastMessageAt,
        createdAt: createdAt,
        userLastReadAt: userLastReadAt ?? this.userLastReadAt,
        dmUserLastReadAt: dmUserLastReadAt ?? this.dmUserLastReadAt,
        botName: botName ?? this.botName,
        botPfpUrl: botPfpUrl ?? this.botPfpUrl,
        peerName: peerName ?? this.peerName,
        peerAvatarUrl: peerAvatarUrl ?? this.peerAvatarUrl,
        lastMessagePreview: lastMessagePreview ?? this.lastMessagePreview,
        unreadCount: unreadCount ?? this.unreadCount,
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
        userLastReadAt: map['user_last_read_at'] == null
            ? null
            : DateTime.parse(map['user_last_read_at'] as String),
        dmUserLastReadAt: map['dm_user_last_read_at'] == null
            ? null
            : DateTime.parse(map['dm_user_last_read_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'id': id,
        'user_id': userId,
        'bot_id': botId,
        if (dmUserId != null) 'dm_user_id': dmUserId,
        if (lastMessageAt != null)
          'last_message_at': lastMessageAt!.toIso8601String(),
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
        if (userLastReadAt != null)
          'user_last_read_at': userLastReadAt!.toIso8601String(),
        if (dmUserLastReadAt != null)
          'dm_user_last_read_at': dmUserLastReadAt!.toIso8601String(),
      };
}
