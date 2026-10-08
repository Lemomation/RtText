import 'package:flutter_test/flutter_test.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/models/message.dart';
import 'package:rttext/models/profile.dart';

void main() {
  group('Conversation.peerIdFor', () {
    test('returns null for bot conversation', () {
      const conv = Conversation(
        id: 'c1',
        userId: 'u1',
        botId: 'b1',
      );
      expect(conv.peerIdFor('u1'), isNull);
    });

    test('returns dmUserId when caller is creator', () {
      const conv = Conversation(
        id: 'c2',
        userId: 'lemomation',
        botId: '',
        dmUserId: 'anikait',
      );
      expect(conv.peerIdFor('lemomation'), 'anikait');
    });

    test('returns userId when caller is dm_user_id recipient', () {
      const conv = Conversation(
        id: 'c2',
        userId: 'lemomation',
        botId: '',
        dmUserId: 'anikait',
      );
      expect(conv.peerIdFor('anikait'), 'lemomation');
    });
  });

  group('Conversation serialization', () {
    test('roundtrips dmUserId in fromMap / toMap', () {
      final map = <String, dynamic>{
        'id': 'c2',
        'user_id': 'lemomation',
        'bot_id': '',
        'dm_user_id': 'anikait',
      };
      final conv = Conversation.fromMap(map);
      expect(conv.isDm, isTrue);
      expect(conv.dmUserId, 'anikait');
      expect(conv.toMap()['dm_user_id'], 'anikait');
    });

    test('roundtrips read receipt timestamps', () {
      final now = DateTime.now();
      final map = <String, dynamic>{
        'id': 'c3',
        'user_id': 'user-1',
        'bot_id': '',
        'dm_user_id': 'user-2',
        'user_last_read_at': now.toIso8601String(),
        'dm_user_last_read_at': now.toIso8601String(),
      };
      final conv = Conversation.fromMap(map);
      expect(conv.userLastReadAt, isNotNull);
      expect(conv.dmUserLastReadAt, isNotNull);
      expect(conv.lastReadAtFor('user-1'), conv.userLastReadAt);
      expect(conv.peerLastReadAtFor('user-1'), conv.dmUserLastReadAt);
      expect(conv.lastReadAtFor('user-2'), conv.dmUserLastReadAt);
      expect(conv.peerLastReadAtFor('user-2'), conv.userLastReadAt);
    });

    test('handles missing id and malformed timestamps gracefully', () {
      final map = <String, dynamic>{
        'user_id': 'user-1',
        'bot_id': '',
        'dm_user_id': 'user-2',
        'created_at': 'invalid-date',
      };
      final conv = Conversation.fromMap(map);
      expect(conv.id, '');
      expect(conv.createdAt, isNull);
      expect(conv.isDm, isTrue);
    });

    test('supports copying with lastMessageAt', () {
      const conv = Conversation(id: 'c1', userId: 'u1', botId: 'b1');
      final now = DateTime.now();
      final updated = conv.copyWith(lastMessageAt: now);
      expect(updated.lastMessageAt, now);
    });
  });

  group('Message model', () {
    test('attributes isMine correctly', () {
      const m1 = Message(
        id: 'm1',
        conversationId: 'c1',
        role: 'user',
        content: 'hello',
        senderId: 'user-a',
      );
      expect(m1.isMine('user-a'), isTrue);
      expect(m1.isMine('user-b'), isFalse);
    });

    test('preserves pending and createdAt', () {
      final now = DateTime.now();
      final m = Message(
        id: 'm2',
        conversationId: 'c1',
        role: 'user',
        content: 'pending msg',
        createdAt: now,
        pending: true,
      );
      expect(m.pending, isTrue);
      expect(m.createdAt, now);
      final confirmed = m.copyWith(pending: false);
      expect(confirmed.pending, isFalse);
    });

    test('roundtrips mediaUrl and reply fields in fromMap / toMap', () {
      final map = <String, dynamic>{
        'id': 'm3',
        'conversation_id': 'c1',
        'role': 'user',
        'content': 'look at this',
        'sender_id': 'user-a',
        'media_url': 'https://example.com/photo.jpg',
        'reply_to_id': 'm1',
        'reply_to_content': 'hello',
        'reply_to_sender': 'user-b',
      };
      final m = Message.fromMap(map);
      expect(m.mediaUrl, 'https://example.com/photo.jpg');
      expect(m.replyToId, 'm1');
      expect(m.replyToContent, 'hello');
      expect(m.replyToSender, 'user-b');

      final serialized = m.toMap();
      expect(serialized['media_url'], 'https://example.com/photo.jpg');
      expect(serialized['reply_to_id'], 'm1');
      expect(serialized['reply_to_content'], 'hello');
      expect(serialized['reply_to_sender'], 'user-b');
    });

    test('supports copyWith with mediaUrl and reply fields', () {
      const m = Message(
        id: 'm1',
        conversationId: 'c1',
        role: 'user',
        content: 'hello',
      );
      final updated = m.copyWith(
        mediaUrl: 'https://example.com/img.png',
        replyToId: 'm0',
        replyToContent: 'prior text',
        replyToSender: 'someone',
      );
      expect(updated.mediaUrl, 'https://example.com/img.png');
      expect(updated.replyToId, 'm0');
      expect(updated.replyToContent, 'prior text');
      expect(updated.replyToSender, 'someone');
    });
  });

  group('Profile serialization', () {
    test('roundtrips created_at in fromMap / toMap', () {
      final now = DateTime.now();
      final map = <String, dynamic>{
        'id': 'u1',
        'username': 'bilquees',
        'avatar_url': 'https://example.com/pfp.jpg',
        'beads': 42,
        'created_at': now.toIso8601String(),
      };
      final profile = Profile.fromMap(map);
      expect(profile.id, 'u1');
      expect(profile.username, 'bilquees');
      expect(profile.avatarUrl, 'https://example.com/pfp.jpg');
      expect(profile.beads, 42);
      expect(profile.createdAt, isNotNull);
      expect(profile.toMap()['created_at'], isNotNull);
    });
  });
}
