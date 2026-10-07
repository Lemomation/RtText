import 'package:flutter_test/flutter_test.dart';
import 'package:rttext/services/notifications_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

class _FakeGoTrueClient extends Fake implements GoTrueClient {
  @override
  User? get currentUser => null;
}

class _FakeSupabaseClient extends Fake implements SupabaseClient {
  @override
  GoTrueClient get auth => _FakeGoTrueClient();
}

void main() {
  test('syncToken exits gracefully when user is not logged in', () async {
    final client = _FakeSupabaseClient();
    // Must not throw even when Firebase is not initialized or user is null
    await expectLater(NotificationsService.syncToken(client), completes);
  });

  test('removeToken exits gracefully when user is not logged in', () async {
    final client = _FakeSupabaseClient();
    await expectLater(NotificationsService.removeToken(client), completes);
  });
}
