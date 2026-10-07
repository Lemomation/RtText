import 'package:flutter_test/flutter_test.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/models/message.dart';

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
  });
}
