import 'package:go_router/go_router.dart';
import 'package:rttext/auth/auth_controller.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/models/conversation.dart';
import 'package:rttext/screens/bot_profile_screen.dart';
import 'package:rttext/screens/chat_screen.dart';
import 'package:rttext/screens/chats_screen.dart';
import 'package:rttext/screens/chats_shell_screen.dart';
import 'package:rttext/screens/discover_screen.dart';
import 'package:rttext/screens/create_bot_screen.dart';
import 'package:rttext/screens/login_screen.dart';
import 'package:rttext/screens/profile_screen.dart';

/// Central route table with an auth gate: unauthenticated users are
/// redirected to /login, and /login bounces back to /chats once signed in.
/// Every route uses [Motion.page] for a consistent fade-through transition.
abstract final class AppRouter {
  static GoRouter build(AuthController auth) => GoRouter(
        refreshListenable: auth,
        initialLocation: '/chats',
        redirect: (context, state) {
          final loggingIn = state.matchedLocation == '/login';
          if (!auth.isAuthenticated) return loggingIn ? null : '/login';
          return loggingIn ? '/chats' : null;
        },
        routes: [
          GoRoute(
            path: '/login',
            pageBuilder: (context, state) =>
                Motion.page(state: state, child: const LoginScreen()),
          ),
          ShellRoute(
            builder: (context, state, child) => ChatsShellScreen(child: child),
            routes: [
              GoRoute(
                path: '/chats',
                pageBuilder: (context, state) =>
                    Motion.page(state: state, child: const ChatsScreen()),
              ),
              GoRoute(
                path: '/discover',
                pageBuilder: (context, state) =>
                    Motion.page(state: state, child: const DiscoverScreen()),
              ),
            ],
          ),
          GoRoute(
            path: '/chat/:id',
            pageBuilder: (context, state) => Motion.page(
              state: state,
              child: ChatScreen(
                chatId: state.pathParameters['id'] ?? '',
                initialConversation: state.extra as Conversation?,
              ),
            ),
          ),
          GoRoute(
            path: '/bot/:id',
            pageBuilder: (context, state) => Motion.page(
              state: state,
              child: BotProfileScreen(botId: state.pathParameters['id'] ?? ''),
            ),
          ),
          GoRoute(
            path: '/create-bot',
            pageBuilder: (context, state) => Motion.page(
              state: state,
              child: CreateBotScreen(
                botId: state.uri.queryParameters['id'],
              ),
            ),
          ),
          GoRoute(
            path: '/profile',
            pageBuilder: (context, state) =>
                Motion.page(state: state, child: const ProfileScreen()),
          ),
        ],
      );
}
