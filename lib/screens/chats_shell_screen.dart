import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/services/beads_service.dart';
import 'package:rttext/widgets/bead_icon.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shell with bottom navigation (Chats / Discover) hosting tab routes.
///
/// On first load it tries the lazy daily bead claim; when the server says a
/// claim happened (first login of the day), a small celebration popup shows.
class ChatsShellScreen extends StatefulWidget {
  const ChatsShellScreen({super.key, required this.child});

  final Widget child;

  @override
  State<ChatsShellScreen> createState() => _ChatsShellScreenState();
}

class _ChatsShellScreenState extends State<ChatsShellScreen> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _claimDailyBeads());
  }

  Future<void> _claimDailyBeads() async {
    try {
      final balance = await BeadsService(Supabase.instance.client).claimDaily();
      if (balance == null || !mounted) return;
      showDialog<void>(
        context: context,
        builder: (context) => AlertDialog(
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const BeadIcon(size: 72)
                  .animate()
                  .scale(
                    begin: const Offset(0.3, 0.3),
                    end: const Offset(1, 1),
                    duration: Motion.slow,
                    curve: Motion.springCurve,
                  )
                  .fade(duration: Motion.emphasized),
              const SizedBox(height: 20),
              Text(
                '+20 beads',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 6),
              Text(
                'Daily claim — enjoy! Come back tomorrow for more.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
              const SizedBox(height: 4),
              Text(
                'Balance: $balance',
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      color: Theme.of(context).colorScheme.primary,
                    ),
              ),
            ],
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Nice!'),
            ),
          ],
        ),
      );
    } catch (_) {
      // Claim is best-effort; the server keeps the last-claimed date.
    }
  }

  int _indexFor(String location) =>
      location.startsWith('/discover') ? 1 : 0;

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);
    return Scaffold(
      body: widget.child,
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
