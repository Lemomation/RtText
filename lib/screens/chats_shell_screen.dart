import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';
import 'package:rttext/core/animations.dart';
import 'package:rttext/services/beads_service.dart';
import 'package:rttext/services/updater_service.dart';
import 'package:rttext/widgets/bead_icon.dart';
import 'package:rttext/widgets/rt_icons.dart';
import 'package:rttext/widgets/update_prompt_dialog.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Shell with bottom navigation (Chats / Discover) hosting tab routes.
///
/// On first load it tries the lazy daily bead claim; when the server says a
/// claim happened (first login of the day), a small celebration popup shows.
/// It then checks in the background for app updates and prompts the user if
/// a newer release is ready.
class ChatsShellScreen extends StatefulWidget {
  const ChatsShellScreen({super.key, required this.child});

  final Widget child;

  @override
  State<ChatsShellScreen> createState() => _ChatsShellScreenState();
}

class _ChatsShellScreenState extends State<ChatsShellScreen> {
  static bool _hasCheckedForUpdate = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _runStartupTasks());
  }

  Future<void> _runStartupTasks() async {
    // Daily bead giveaway is suspended to simulate the economy.
    if (!mounted) return;
    await _checkForUpdate();
  }

  Future<void> _checkForUpdate() async {
    if (_hasCheckedForUpdate) return;
    _hasCheckedForUpdate = true;
    try {
      final info = await UpdaterService().check();
      if (!mounted || info.status != UpdateStatus.updateAvailable) return;
      await showUpdatePromptDialog(context, info);
    } catch (_) {
      // Background check is non-intrusive; network issues are ignored.
    }
  }

  Future<void> _claimDailyBeads() async {
    try {
      final balance = await BeadsService(Supabase.instance.client).claimDaily();
      if (balance == null || !mounted) return;
      await showDialog<void>(
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

  int _indexFor(String location) {
    if (location.startsWith('/discover')) return 1;
    if (location.startsWith('/profile')) return 2;
    return 0;
  }

  @override
  Widget build(BuildContext context) {
    final location = GoRouterState.of(context).matchedLocation;
    final index = _indexFor(location);
    // The custom icon set ships a single filled variant per glyph, so the
    // selected tab is expressed through color strength instead of an
    // outline/fill pair.
    final scheme = Theme.of(context).colorScheme;
    final unselected = scheme.onSurfaceVariant.withValues(alpha: 0.55);
    return Scaffold(
      body: widget.child,
      bottomNavigationBar: NavigationBar(
        selectedIndex: index,
        onDestinationSelected: (i) {
          switch (i) {
            case 0:
              context.go('/chats');
            case 1:
              context.go('/discover');
            case 2:
              context.go('/profile');
          }
        },
        destinations: [
          NavigationDestination(
            icon: RtIcon(type: RtIconType.chatBubble, color: unselected),
            selectedIcon: RtIcon(
              type: RtIconType.chatBubble,
              color: scheme.primary,
            ),
            label: 'Chats',
          ),
          NavigationDestination(
            icon: RtIcon(type: RtIconType.explore, color: unselected),
            selectedIcon: RtIcon(
              type: RtIconType.explore,
              color: scheme.primary,
            ),
            label: 'Discover',
          ),
          NavigationDestination(
            icon: RtIcon(type: RtIconType.person, color: unselected),
            selectedIcon: RtIcon(
              type: RtIconType.person,
              color: scheme.primary,
            ),
            label: 'Profile',
          ),
        ],
      ),
    );
  }
}
