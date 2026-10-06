import 'package:rttext/models/bot.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/models/message.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Conversation & message access backed by Supabase (with realtime streams).
class ConversationsService {
  const ConversationsService(this._client);

  final SupabaseClient _client;

  String? get _uid => _client.auth.currentUser?.id;

  /// Realtime stream of the caller's conversations, newest activity first,
  /// enriched with bot name/pfp and the last message preview.
  Stream<List<Conversation>> watchConversations() {
    final uid = _uid;
    if (uid == null) return const Stream.empty();
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .eq('user_id', uid)
        .asyncMap(_enrich);
  }

  Future<List<Conversation>> fetchConversations() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from('conversations')
        .select()
        .eq('user_id', uid)
        .order('last_message_at', ascending: false);
    return _enrich((rows as List).cast<Map<String, dynamic>>());
  }

  Future<List<Conversation>> _enrich(List<Map<String, dynamic>> rows) async {
    var convs = rows.map(Conversation.fromMap).toList()
      ..sort((a, b) =>
          (b.lastMessageAt ?? b.createdAt ?? DateTime(2000))
              .compareTo(a.lastMessageAt ?? a.createdAt ?? DateTime(2000)));
    if (convs.isEmpty) return convs;

    // Bot metadata in one query via the public view (never sys_prompt).
    try {
      final botRows = await _client
          .from('public_bots')
          .select('id,name,pfp_url')
          .inFilter('id', convs.map((c) => c.botId).toList());
      final byId = <String, Map<String, dynamic>>{};
      for (final r in (botRows as List)) {
        final m = r as Map<String, dynamic>;
        byId[m['id'] as String] = m;
      }
      convs = convs.map((c) {
        final b = byId[c.botId];
        return c.copyWith(
          botName: b?['name'] as String?,
          botPfpUrl: b?['pfp_url'] as String?,
        );
      }).toList();
    } catch (_) {
      // Bot enrichment is best-effort; the list still renders.
    }

    // Last message preview per conversation (small N, one query each).
    final previews = <String, String>{};
    for (final c in convs) {
      try {
        final last = await _client
            .from('messages')
            .select('content,role')
            .eq('conversation_id', c.id)
            .order('created_at', ascending: false)
            .limit(1);
        if (last.isNotEmpty) {
          final m = last.first;
          final content = (m['content'] as String?) ?? '';
          previews[c.id] = m['role'] == 'user' ? 'You: $content' : content;
        }
      } catch (_) {}
    }
    return convs
        .map((c) => c.copyWith(lastMessagePreview: previews[c.id]))
        .toList();
  }

  /// Realtime stream of messages in a conversation, oldest first.
  Stream<List<Message>> watchMessages(String conversationId) => _client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .order('created_at')
      .map((rows) => rows.map(Message.fromMap).toList());

  Future<Conversation> getOrCreate(String botId) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final existing = await _client
        .from('conversations')
        .select()
        .eq('user_id', uid)
        .eq('bot_id', botId)
        .maybeSingle();
    if (existing != null) return Conversation.fromMap(existing);
    final row = await _client
        .from('conversations')
        .insert({'user_id': uid, 'bot_id': botId})
        .select()
        .single();
    return Conversation.fromMap(row);
  }

  /// Inserts a user message and returns the persisted row.
  Future<Message> sendMessage(String conversationId, String content) async {
    final row = await _client.from('messages').insert({
      'conversation_id': conversationId,
      'role': 'user',
      'content': content,
    }).select().single();
    await _client
        .from('conversations')
        .update({'last_message_at': DateTime.now().toIso8601String()})
        .eq('id', conversationId);
    return Message.fromMap(row);
  }

  /// Invokes the ai-reply edge function for this conversation.
  Future<String> requestAiReply(String conversationId) async {
    final res = await _client.functions.invoke(
      'ai-reply',
      body: {'conversation_id': conversationId},
    );
    if (res.status != 200) {
      throw StateError('ai-reply failed (${res.status})');
    }
    final content = (res.data as Map<String, dynamic>?)?['content'];
    if (content is! String || content.isEmpty) {
      throw StateError('ai-reply returned no content');
    }
    return content;
  }

  Future<void> delete(String conversationId) =>
      _client.from('conversations').delete().eq('id', conversationId);

  /// Bot helper reused by the chat screen for the app bar.
  Future<Bot?> botFor(String botId) async {
    final row = await _client
        .from('public_bots')
        .select('id,owner,name,bio,description,pfp_url,is_public,created_at')
        .eq('id', botId)
        .maybeSingle();
    return row == null ? null : Bot.fromMap(row);
  }
}
