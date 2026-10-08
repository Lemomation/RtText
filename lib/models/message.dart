/// A single message in a conversation.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.senderId,
    this.mediaUrl,
    this.replyToId,
    this.replyToContent,
    this.replyToSender,
    this.createdAt,
    this.pending = false,
  });

  final String id;
  final String conversationId;
  final String role; // 'user' | 'assistant'
  final String content;

  /// The human who sent this message in a DM chat (null in bot chats, where
  /// [role] already distinguishes the sides).
  final String? senderId;

  /// Optional public URL to a media attachment (e.g. image in storage bucket).
  final String? mediaUrl;

  /// Optional ID of the message this one is replying to.
  final String? replyToId;

  /// Quoted content snippet of the message being replied to.
  final String? replyToContent;

  /// Display name of the sender of the quoted message.
  final String? replyToSender;

  final DateTime? createdAt;

  /// True while the message exists only locally (optimistic insert).
  final bool pending;

  bool get isUser => role == 'user';

  /// True when [myId] sent this message (DM chats).
  bool isMine(String myId) => senderId != null && senderId == myId;

  Message copyWith({
    bool? pending,
    String? mediaUrl,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) =>
      Message(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content,
        senderId: senderId,
        mediaUrl: mediaUrl ?? this.mediaUrl,
        replyToId: replyToId ?? this.replyToId,
        replyToContent: replyToContent ?? this.replyToContent,
        replyToSender: replyToSender ?? this.replyToSender,
        createdAt: createdAt,
        pending: pending ?? this.pending,
      );

  factory Message.fromMap(Map<String, dynamic> map) => Message(
        id: map['id'] as String,
        conversationId: map['conversation_id'] as String? ?? '',
        role: (map['role'] as String?) ?? 'user',
        content: (map['content'] as String?) ?? '',
        senderId: map['sender_id'] as String?,
        mediaUrl: map['media_url'] as String?,
        replyToId: map['reply_to_id'] as String?,
        replyToContent: map['reply_to_content'] as String?,
        replyToSender: map['reply_to_sender'] as String?,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        if (senderId != null) 'sender_id': senderId,
        if (mediaUrl != null) 'media_url': mediaUrl,
        if (replyToId != null) 'reply_to_id': replyToId,
        if (replyToContent != null) 'reply_to_content': replyToContent,
        if (replyToSender != null) 'reply_to_sender': replyToSender,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
