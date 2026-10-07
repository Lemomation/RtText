import 'package:flutter_test/flutter_test.dart';
import 'package:rttext/models/conversation.dart';

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
}
