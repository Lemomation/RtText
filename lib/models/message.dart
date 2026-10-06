/// A single message in a conversation.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.senderId,
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

  final DateTime? createdAt;

  /// True while the message exists only locally (optimistic insert).
  final bool pending;

  bool get isUser => role == 'user';

  /// True when [myId] sent this message (DM chats).
  bool isMine(String myId) => senderId != null && senderId == myId;

  Message copyWith({bool? pending}) => Message(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content,
        senderId: senderId,
        createdAt: createdAt,
        pending: pending ?? this.pending,
      );

  factory Message.fromMap(Map<String, dynamic> map) => Message(
        id: map['id'] as String,
        conversationId: map['conversation_id'] as String? ?? '',
        role: (map['role'] as String?) ?? 'user',
        content: (map['content'] as String?) ?? '',
        senderId: map['sender_id'] as String?,
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        if (senderId != null) 'sender_id': senderId,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
