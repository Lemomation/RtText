import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:rttext/widgets/placeholder_view.dart';

/// Shell with bottom navigation (Chats / Discover) hosting tab routes.
class ChatsShellScreen extends StatelessWidget {
  const ChatsShellScreen({super.key, required this.child});

  final Widget child;

  int _indexFor(String location) =>
      location.startsWith('/discover') ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final location = state.matchedLocation;
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

/// Placeholder list for the Chats tab (populated in a later milestone).
class ChatsPlaceholder extends StatelessWidget {
  const ChatsPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('RtText'),
        actions: [
          IconButton(
            icon: const Icon(Icons.person_outline_rounded),
            tooltip: 'Profile',
            onPressed: () => context.go('/profile'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () => context.go('/create-bot'),
        child: const Icon(Icons.add_rounded),
      ).animate().fade(delay: 300.ms, duration: 400.ms).scale(
            begin: const Offset(0.6, 0.6),
            end: const Offset(1, 1),
            duration: 400.ms,
            curve: Curves.easeOutBack,
          ),
      body: const PlaceholderView(
        icon: Icons.forum_outlined,
        label: 'Your conversations will appear here',
      ),
    );
  }
}

/// Placeholder grid for the Discover tab (populated in a later milestone).
class DiscoverPlaceholder extends StatelessWidget {
  const DiscoverPlaceholder({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Discover')),
      body: const PlaceholderView(
        icon: Icons.explore_rounded,
        label: 'Find AI characters to chat with',
      ),
    );
  }
}
