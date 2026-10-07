import 'package:rttext/models/bot.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/models/message.dart';
import 'package:rttext/services/beads_service.dart';
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
    // Both DM participants must see the conversation, not just whoever
    // initiated it (the initiator is user_id; the other side is dm_user_id).
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .or('user_id.eq.$uid,dm_user_id.eq.$uid')
        .asyncMap(_enrich);
  }

  Future<List<Conversation>> fetchConversations() async {
    final uid = _uid;
    if (uid == null) return const [];
    final rows = await _client
        .from('conversations')
        .select()
        .or('user_id.eq.$uid,dm_user_id.eq.$uid')
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
    // DM conversations have no bot_id — a null/empty id in the filter list
    // poisons the whole query (400), which left every bot as "Unknown bot".
    final botIds = convs
        .where((c) => !c.isDm && c.botId.isNotEmpty)
        .map((c) => c.botId)
        .toList();
    if (botIds.isNotEmpty) {
      try {
      final botRows = await _client
          .from('public_bots')
          .select('id,name,pfp_url')
          .inFilter('id', botIds);
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
    }

    // Peer metadata for DM chats in one query via the people view
    // (never beads). Bot enrichment above is untouched.
    final dmIds = convs.where((c) => c.isDm).map((c) => c.dmUserId!).toList();
    if (dmIds.isNotEmpty) {
      try {
        final peerRows = await _client
            .from('people')
            .select('id,username,avatar_url')
            .inFilter('id', dmIds);
        final byId = <String, Map<String, dynamic>>{};
        for (final r in (peerRows as List)) {
          final m = r as Map<String, dynamic>;
          byId[m['id'] as String] = m;
        }
        convs = convs.map((c) {
          if (!c.isDm) return c;
          final p = byId[c.dmUserId!];
          return c.copyWith(
            peerName: p?['username'] as String?,
            peerAvatarUrl: p?['avatar_url'] as String?,
          );
        }).toList();
      } catch (_) {
        // Peer enrichment is best-effort; the list still renders.
      }
    }

    // Last message preview per conversation (small N, one query each).
    final previews = <String, String>{};
    for (final c in convs) {
      try {
        final last = await _client
            .from('messages')
            .select('content,role,sender_id')
            .eq('conversation_id', c.id)
            .order('created_at', ascending: false)
            .limit(1);
        if (last.isNotEmpty) {
          final m = last.first;
          final content = (m['content'] as String?) ?? '';
          // Bot chats: role distinguishes the sides. DM chats: both sides are
          // 'user', so attribute via sender_id instead.
          final mine = c.isDm
              ? m['sender_id'] == _uid
              : m['role'] == 'user';
          previews[c.id] = mine ? 'You: $content' : content;
        }
      } catch (_) {}
    }
    return convs
        .map((c) => c.copyWith(lastMessagePreview: previews[c.id]))
        .toList();
  }

  /// Realtime stream of messages in a conversation, oldest first.
  ///
  /// Sorted client-side: the realtime stream's own ordering has proven
  /// unreliable for late-arriving rows, which rendered new messages above
  /// older ones.
  Stream<List<Message>> watchMessages(String conversationId) => _client
      .from('messages')
      .stream(primaryKey: ['id'])
      .eq('conversation_id', conversationId)
      .map((rows) {
    // Realtime is at-least-once: reconnects can re-deliver the same row,
    // which rendered as duplicate reply bubbles. Dedupe by primary key.
    final seen = <String>{};
    final uniqueRows = [
      for (final r in rows)
        if (seen.add(r['id'] as String)) r,
    ];
    final messages = uniqueRows.map(Message.fromMap).toList()
      ..sort((a, b) => (a.createdAt ?? DateTime(0))
          .compareTo(b.createdAt ?? DateTime(0)));
    return messages;
  });

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

  /// Finds the 1:1 DM with [peerId] or creates it. DMs are free: this never
  /// touches beads or ai-reply.
  Future<Conversation> getOrCreateDm(String peerId) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    Future<Conversation?> find() async {
      final row = await _client
          .from('conversations')
          .select()
          .or('and(user_id.eq.$uid,dm_user_id.eq.$peerId),'
              'and(user_id.eq.$peerId,dm_user_id.eq.$uid)')
          .maybeSingle();
      return row == null ? null : Conversation.fromMap(row);
    }

    final existing = await find();
    if (existing != null) return existing;
    try {
      final row = await _client
          .from('conversations')
          .insert({'user_id': uid, 'dm_user_id': peerId})
          .select()
          .single();
      return Conversation.fromMap(row);
    } on PostgrestException catch (e) {
      // Lost a race against the unique pair index — the other side (or a
      // parallel call) created the conversation first; re-read it.
      if (e.code == '23505') {
        final raced = await find();
        if (raced != null) return raced;
      }
      rethrow;
    }
  }

  /// Username search for starting a DM: prefix match on the people view,
  /// excluding the caller. Returns raw rows of {id, username, avatar_url}.
  Future<List<Map<String, dynamic>>> searchPeople(String query) async {
    final uid = _uid;
    if (uid == null) return const [];
    final q = query.trim();
    if (q.isEmpty) return const [];
    final rows = await _client
        .from('people')
        .select('id,username,avatar_url')
        .ilike('username', '$q%')
        .neq('id', uid)
        .limit(20);
    return (rows as List).cast<Map<String, dynamic>>();
  }

  /// Inserts a user message and returns the persisted row.
  ///
  /// For DM chats pass [senderIdToWrite] (the caller's uid) so the peer's
  /// client can attribute the bubble; bot chats omit it and stay exactly as
  /// before.
  Future<Message> sendMessage(
    String conversationId,
    String content, {
    String? senderIdToWrite,
  }) async {
    final row = await _client.from('messages').insert({
      'conversation_id': conversationId,
      'role': 'user',
      'content': content,
      if (senderIdToWrite != null) 'sender_id': senderIdToWrite,
    }).select().single();
    await _client
        .from('conversations')
        .update({'last_message_at': DateTime.now().toIso8601String()})
        .eq('id', conversationId);
    return Message.fromMap(row);
  }

  /// Invokes the ai-reply edge function for this conversation.
  ///
  /// Returns the reply text and the caller's remaining bead balance as
  /// reported by the function. Throws [OutOfBeadsException] when the
  /// function answered 402 (balance reached zero).
  Future<AiReplyResult> requestAiReply(String conversationId) async {
    // The Authorization header must be sent explicitly: the shared
    // FunctionsClient captures its headers at construction time and can
    // carry the anon key instead of the caller's session token, which the
    // function then (correctly) rejects.
    final token = _client.auth.currentSession?.accessToken;
    final res = await _client.functions.invoke(
      'ai-reply',
      headers: {
        if (token != null) 'Authorization': 'Bearer $token',
      },
      body: {'conversation_id': conversationId},
    );
    if (res.status == 402) {
      throw const OutOfBeadsException();
    }
    if (res.status != 200) {
      throw StateError('ai-reply failed (${res.status})');
    }
    final data = res.data as Map<String, dynamic>?;
    final content = data?['content'];
    if (content is! String || content.isEmpty) {
      throw StateError('ai-reply returned no content');
    }
    return AiReplyResult(
      content: content,
      remainingBeads: (data?['beads'] as num?)?.toInt(),
    );
  }

  Future<void> delete(String conversationId) =>
      _client.from('conversations').delete().eq('id', conversationId);

  /// Bot helper reused by the chat screen for the app bar.
  Future<Bot?> botFor(String botId) async {
    final row = await _client
        .from('public_bots')
        .select('id,owner,name,bio,description,pfp_url,bubble_color,is_public,created_at')
        .eq('id', botId)
        .maybeSingle();
    return row == null ? null : Bot.fromMap(row);
  }
}
