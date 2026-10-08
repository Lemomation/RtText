import 'package:flutter/foundation.dart';
import 'package:rttext/core/supabase_config.dart';
import 'package:rttext/services/notifications_service.dart';
import 'package:rttext/services/presence_service.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Listens to Supabase auth state and exposes it to the router/widgets.
class AuthController extends ChangeNotifier {
  AuthController(this._client);

  final SupabaseClient _client;
  Session? _session;
  bool _isListening = false;

  Session? get session => _session;
  bool get isAuthenticated => _session != null;

  String? get avatarUrl => _session?.user.userMetadata?['avatar_url']
      as String?;
  String? get displayName =>
      (_session?.user.userMetadata?['full_name'] as String?) ??
      _session?.user.email;

  /// Idempotent so tests can call it safely.
  void start() {
    if (_isListening) return;
    _isListening = true;
    _session = _client.auth.currentSession;
    if (_session != null) {
      PresenceService.instance.start(_session!.user.id);
    }
    _client.auth.onAuthStateChange.listen((data) {
      _session = data.session;
      if (data.session != null) {
        NotificationsService.syncToken(_client);
        PresenceService.instance.start(data.session!.user.id);
      } else {
        PresenceService.instance.stop();
      }
      notifyListeners();
    });
  }

  Future<void> signInWithGoogle() async {
    await _client.auth.signInWithOAuth(
      OAuthProvider.google,
      redirectTo: SupabaseConfig.oauthRedirectUrl,
    );
  }

  Future<void> signOut() async {
    await PresenceService.instance.stop();
    await NotificationsService.removeToken(_client);
    await _client.auth.signOut();
  }
}

