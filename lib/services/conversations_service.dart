import 'dart:typed_data';

import 'package:rttext/core/uuid.dart';
import 'package:rttext/models/bot.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/models/conversation_member.dart';
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
    // initiated it (initiator = user_id, the other side = dm_user_id). The
    // realtime stream builder has no .or(), so subscribe unfiltered and
    // filter client-side — realtime enforces the same participant-only RLS
    // the table has, so only authorized rows ever arrive.
    return _client
        .from('conversations')
        .stream(primaryKey: ['id'])
        .asyncMap((rows) {
      final mine = rows
          .where((r) =>
              r['user_id'] == uid ||
              r['dm_user_id'] == uid ||
              r['is_group'] == true)
          .toList();
      return _enrich(mine.cast<Map<String, dynamic>>());
    });
  }

  Future<List<Conversation>> fetchConversations() async {
    final uid = _uid;
    if (uid == null) return const [];
    // RLS scopes rows to participant bot chats, DMs, and group memberships.
    final rows = await _client
        .from('conversations')
        .select()
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
    final uid = _uid;
    final peerIds = convs
        .where((c) => c.isDm)
        .map((c) => c.peerIdFor(uid ?? ''))
        .whereType<String>()
        .toSet()
        .toList();
    if (peerIds.isNotEmpty) {
      try {
        final peerRows = await _client
            .from('people')
            .select('id,username,avatar_url')
            .inFilter('id', peerIds);
        final byId = <String, Map<String, dynamic>>{};
        for (final r in (peerRows as List)) {
          final m = r as Map<String, dynamic>;
          byId[m['id'] as String] = m;
        }
        convs = convs.map((c) {
          if (!c.isDm) return c;
          final peerId = c.peerIdFor(uid ?? '');
          final p = peerId != null ? byId[peerId] : null;
          return c.copyWith(
            peerName: p?['username'] as String?,
            peerAvatarUrl: p?['avatar_url'] as String?,
          );
        }).toList();
      } catch (_) {
        // Peer enrichment is best-effort; the list still renders.
      }
    }

    // Last message preview, timestamp, and unread count per conversation.
    final previews = <String, String>{};
    final unreadCounts = <String, int>{};
    final lastMessageAts = <String, DateTime>{};
    for (final c in convs) {
      try {
        final last = await _client
            .from('messages')
            .select('content,role,sender_id,created_at,media_url')
            .eq('conversation_id', c.id)
            .order('created_at', ascending: false)
            .limit(1);
        if (last.isNotEmpty) {
          final m = last.first;
          final content = (m['content'] as String?) ?? '';
          final mediaUrl = m['media_url'] as String?;
          final String displayBody;
          if (content.trim().isNotEmpty) {
            displayBody = mediaUrl != null ? '📷 $content' : content;
          } else if (mediaUrl != null) {
            displayBody = '📷 Photo';
          } else {
            displayBody = '';
          }
          final lastCreatedAt = m['created_at'] != null
              ? DateTime.tryParse(m['created_at'] as String)
              : null;
          if (lastCreatedAt != null) {
            lastMessageAts[c.id] = lastCreatedAt;
          }
          // Bot chats: role distinguishes the sides. DM chats: both sides are
          // 'user', so attribute via sender_id instead.
          final mine = c.isDm
              ? m['sender_id'] == _uid
              : m['role'] == 'user';
          previews[c.id] = mine ? 'You: $displayBody' : displayBody;

          final myLastRead = c.lastReadAtFor(_uid ?? '');
          if (!mine && myLastRead != null && lastCreatedAt != null) {
            if (lastCreatedAt.isAfter(myLastRead)) {
              final unreadRows = await _client
                  .from('messages')
                  .select('id')
                  .eq('conversation_id', c.id)
                  .gt('created_at', myLastRead.toUtc().toIso8601String());
              unreadCounts[c.id] = (unreadRows as List).length;
            }
          }
        }
      } catch (_) {}
    }
    return convs
        .map((c) => c.copyWith(
              lastMessageAt: lastMessageAts[c.id] ?? c.lastMessageAt,
              lastMessagePreview: previews[c.id],
              unreadCount: unreadCounts[c.id] ?? 0,
            ))
        .toList();
  }

  /// Stream of a single conversation's state (for real-time read receipts).
  Stream<Conversation?> watchConversation(String conversationId) => _client
      .from('conversations')
      .stream(primaryKey: ['id'])
      .eq('id', conversationId)
      .map((rows) => rows.isEmpty ? null : Conversation.fromMap(rows.first));

  /// Marks a conversation as read up to current time for the authenticated user.
  Future<void> markAsRead(String conversationId) async {
    final uid = _uid;
    if (uid == null) return;
    try {
      final conv = await _client
          .from('conversations')
          .select('user_id,dm_user_id')
          .eq('id', conversationId)
          .maybeSingle();
      if (conv == null) return;
      final isCreator = conv['user_id'] == uid;
      final columnToUpdate =
          isCreator ? 'user_last_read_at' : 'dm_user_last_read_at';
      await _client
          .from('conversations')
          .update({columnToUpdate: DateTime.now().toUtc().toIso8601String()})
          .eq('id', conversationId);
    } catch (_) {
      // Best-effort
    }
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

  /// Uploads an image to the `chat_media` storage bucket and returns its public URL.
  Future<String> uploadChatImage(
    String conversationId,
    Uint8List bytes, {
    String extension = 'jpg',
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');
    final ext = extension.toLowerCase().replaceAll('.', '');
    final contentType = ext == 'png' ? 'image/png' : 'image/jpeg';
    final path = '$conversationId/${uuidV4()}.$ext';
    await _client.storage.from('chat_media').uploadBinary(
          path,
          bytes,
          fileOptions: FileOptions(
            upsert: true,
            contentType: contentType,
          ),
        );
    return _client.storage.from('chat_media').getPublicUrl(path);
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
    String? mediaUrl,
    String? replyToId,
    String? replyToContent,
    String? replyToSender,
  }) async {
    final row = await _client.from('messages').insert({
      'conversation_id': conversationId,
      'role': 'user',
      'content': content,
      if (senderIdToWrite != null) 'sender_id': senderIdToWrite,
      if (mediaUrl != null) 'media_url': mediaUrl,
      if (replyToId != null) 'reply_to_id': replyToId,
      if (replyToContent != null) 'reply_to_content': replyToContent,
      if (replyToSender != null) 'reply_to_sender': replyToSender,
    }).select().single();
    await _client
        .from('conversations')
        .update({'last_message_at': DateTime.now().toUtc().toIso8601String()})
        .eq('id', conversationId);

    if (senderIdToWrite != null) {
      // Human DM: asynchronously dispatch push notification via Edge Function.
      // Explicit Authorization header passed in case client headers differ.
      final pushContent =
          content.trim().isEmpty && mediaUrl != null ? '📷 Photo' : content;
      final token = _client.auth.currentSession?.accessToken;
      _client.functions.invoke(
        'send-push',
        headers: {
          if (token != null) 'Authorization': 'Bearer $token',
        },
        body: {
          'conversation_id': conversationId,
          'content': pushContent,
        },
      ).ignore();
    }

    return Message.fromMap(row);
  }

  /// Invokes the ai-reply edge function for this conversation.
  /// Pass [botId] when calling in a group chat to specify which bot is replying.
  ///
  /// Returns the reply text and the caller's remaining bead balance as
  /// reported by the function. Throws [OutOfBeadsException] when the
  /// function answered 402 (balance reached zero).
  Future<AiReplyResult> requestAiReply(
    String conversationId, {
    String? botId,
  }) async {
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
      body: {
        'conversation_id': conversationId,
        if (botId != null) 'bot_id': botId,
      },
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

  /// Creates a new group conversation and populates initial members.
  Future<Conversation> createGroup({
    required String title,
    String? avatarUrl,
    required List<String> memberUserIds,
    required List<String> memberBotIds,
  }) async {
    final uid = _uid;
    if (uid == null) throw StateError('Not signed in');

    final row = await _client
        .from('conversations')
        .insert({
          'is_group': true,
          'title': title,
          'avatar_url': avatarUrl,
          'created_by': uid,
          'user_id': uid,
        })
        .select()
        .single();

    final convId = row['id'] as String;

    final membersToInsert = <Map<String, dynamic>>[
      {
        'conversation_id': convId,
        'user_id': uid,
        'role': 'admin',
      },
    ];

    for (final mUid in memberUserIds) {
      if (mUid != uid) {
        membersToInsert.add({
          'conversation_id': convId,
          'user_id': mUid,
          'role': 'member',
        });
      }
    }

    for (final bId in memberBotIds) {
      membersToInsert.add({
        'conversation_id': convId,
        'bot_id': bId,
        'role': 'member',
      });
    }

    await _client.from('conversation_members').insert(membersToInsert);

    return Conversation.fromMap(row).copyWith(
      title: title,
      avatarUrl: avatarUrl,
    );
  }

  /// Fetches all members in a group conversation (humans and bots).
  Future<List<ConversationMember>> getGroupMembers(
      String conversationId) async {
    final rows = await _client
        .from('group_members_view')
        .select()
        .eq('conversation_id', conversationId);
    return (rows as List)
        .map((r) => ConversationMember.fromMap(r as Map<String, dynamic>))
        .toList();
  }

  /// Adds a human or bot member to an existing group.
  Future<void> addGroupMember(
    String conversationId, {
    String? userId,
    String? botId,
    String role = 'member',
  }) async {
    await _client.from('conversation_members').insert({
      'conversation_id': conversationId,
      if (userId != null) 'user_id': userId,
      if (botId != null) 'bot_id': botId,
      'role': role,
    });
  }

  /// Removes a member from a group.
  Future<void> removeGroupMember(String memberId) =>
      _client.from('conversation_members').delete().eq('id', memberId);

  Future<void> delete(String conversationId) =>
      _client.from('conversations').delete().eq('id', conversationId);

  /// Clears all messages in a conversation without deleting the conversation row.
  Future<void> clearConversationMessages(String conversationId) =>
      _client.from('messages').delete().eq('conversation_id', conversationId);

  /// Deletes a single message from the database.
  Future<void> deleteMessage(String messageId) =>
      _client.from('messages').delete().eq('id', messageId);

  /// Fetches public profile details of a DM peer from the people view.
  Future<Map<String, dynamic>?> getPeerProfile(String peerId) async {
    final row = await _client
        .from('people')
        .select('id,username,avatar_url,created_at,last_seen_at')
        .eq('id', peerId)
        .maybeSingle();
    return row;
  }

  /// Loads media attachments shared in a conversation.
  Future<List<Map<String, dynamic>>> getSharedMedia(
      String conversationId) async {
    final rows = await _client
        .from('messages')
        .select('id,media_url,content,created_at')
        .eq('conversation_id', conversationId)
        .not('media_url', 'is', null)
        .order('created_at', ascending: false)
        .limit(100);
    return (rows as List).cast<Map<String, dynamic>>();
  }

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
