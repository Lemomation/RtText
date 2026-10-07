import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/widgets.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Top-level background message handler for FCM.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  // If the app is terminated or in the background, FCM displays the
  // notification automatically via its notification payload on Android.
}

/// Manages Firebase Cloud Messaging registration and syncs device push tokens
/// to Supabase for delivering DM push notifications.
class NotificationsService {
  const NotificationsService._();

  static bool _initialized = false;

  /// Initializes Firebase and sets up notification listeners. Safe to call
  /// repeatedly or in test environments where Firebase is absent.
  static Future<void> initialize(SupabaseClient client) async {
    if (_initialized) return;
    try {
      await Firebase.initializeApp();
      FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
      _initialized = true;

      // Handle token refreshes from Google Play Services
      FirebaseMessaging.instance.onTokenRefresh.listen((token) {
        syncToken(client, explicitToken: token);
      });

      // Synchronize token for currently signed-in user
      await syncToken(client);
    } catch (e) {
      // Firebase initialization is best-effort (e.g. absent in test runners).
      debugPrint('Firebase messaging initialization skipped: $e');
    }
  }

  /// Requests notification permissions (Android 13+) and records the device
  /// FCM token in the Supabase user_push_tokens table.
  static Future<void> syncToken(
    SupabaseClient client, {
    String? explicitToken,
  }) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null || !_initialized) return;

    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      final isAuthorized =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
          settings.authorizationStatus == AuthorizationStatus.provisional;

      if (!isAuthorized) return;

      final token = explicitToken ?? await FirebaseMessaging.instance.getToken();
      if (token == null || token.isEmpty) return;

      await client.from('user_push_tokens').upsert(
        {
          'user_id': uid,
          'token': token,
          'platform': 'android',
          'updated_at': DateTime.now().toIso8601String(),
        },
        onConflict: 'user_id,token',
      );
    } catch (_) {
      // Token sync is best-effort; failures do not block the app.
    }
  }

  /// Removes the device token upon sign out so the user does not receive
  /// notifications for another account on the same phone.
  static Future<void> removeToken(SupabaseClient client) async {
    final uid = client.auth.currentUser?.id;
    if (uid == null || !_initialized) return;

    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await client
            .from('user_push_tokens')
            .delete()
            .eq('user_id', uid)
            .eq('token', token);
      }
    } catch (_) {
      // Cleanup is best-effort.
    }
  }

  /// Listens for notification tap events to navigate directly to the
  /// corresponding chat conversation.
  static void setupNavigation(GoRouter router) {
    if (!_initialized) return;

    // 1. App brought to foreground from background by tapping notification
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      final conversationId = message.data['conversation_id'] as String?;
      if (conversationId != null && conversationId.isNotEmpty) {
        router.push('/chat/$conversationId');
      }
    });

    // 2. App launched from terminated state by tapping notification
    FirebaseMessaging.instance.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        final conversationId = message.data['conversation_id'] as String?;
        if (conversationId != null && conversationId.isNotEmpty) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            router.push('/chat/$conversationId');
          });
        }
      }
    });
  }
}
