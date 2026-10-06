import 'package:go_router/go_router.dart';
import 'package:rttext/auth/auth_controller.dart';
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
            builder: (context, state) => const LoginScreen(),
          ),
          ShellRoute(
            builder: (context, state, child) => ChatsShellScreen(child: child),
            routes: [
              GoRoute(
                path: '/chats',
                builder: (context, state) => const ChatsScreen(),
              ),
              GoRoute(
                path: '/discover',
                builder: (context, state) => const DiscoverScreen(),
              ),
            ],
          ),
          GoRoute(
            path: '/chat/:id',
            builder: (context, state) =>
                ChatScreen(chatId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/bot/:id',
            builder: (context, state) =>
                BotProfileScreen(botId: state.pathParameters['id'] ?? ''),
          ),
          GoRoute(
            path: '/create-bot',
            builder: (context, state) => CreateBotScreen(
                  botId: state.uri.queryParameters['id'],
                ),
          ),
          GoRoute(
            path: '/profile',
            builder: (context, state) => const ProfileScreen(),
          ),
        ],
      );
}
