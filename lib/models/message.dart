/// A single message in a conversation.
class Message {
  const Message({
    required this.id,
    required this.conversationId,
    required this.role,
    required this.content,
    this.createdAt,
    this.pending = false,
  });

  final String id;
  final String conversationId;
  final String role; // 'user' | 'assistant'
  final String content;
  final DateTime? createdAt;

  /// True while the message exists only locally (optimistic insert).
  final bool pending;

  bool get isUser => role == 'user';

  Message copyWith({bool? pending}) => Message(
        id: id,
        conversationId: conversationId,
        role: role,
        content: content,
        createdAt: createdAt,
        pending: pending ?? this.pending,
      );

  factory Message.fromMap(Map<String, dynamic> map) => Message(
        id: map['id'] as String,
        conversationId: map['conversation_id'] as String? ?? '',
        role: (map['role'] as String?) ?? 'user',
        content: (map['content'] as String?) ?? '',
        createdAt: map['created_at'] == null
            ? null
            : DateTime.parse(map['created_at'] as String),
      );

  Map<String, dynamic> toMap() => {
        'conversation_id': conversationId,
        'role': role,
        'content': content,
        if (createdAt != null) 'created_at': createdAt!.toIso8601String(),
      };
}
