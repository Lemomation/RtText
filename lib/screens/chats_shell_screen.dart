import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shell with bottom navigation (Chats / Discover) hosting tab routes.
class ChatsShellScreen extends StatelessWidget {
  const ChatsShellScreen({super.key, required this.child});

  final Widget child;

  int _indexFor(String location) =>
      location.startsWith('/discover') ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);
    return Scaffold(
      body: child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) =>
            i == 0 ? context.go('/chats') : context.go('/discover'),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.chat_bubble_outline_rounded),
            selectedIcon: Icon(Icons.chat_bubble_rounded),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: Icon(Icons.explore_outlined),
            selectedIcon: Icon(Icons.explore_rounded),
            label: 'Discover',
          ),
        ],
      ),
    );
  }
}
