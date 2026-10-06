import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Themed centered placeholder used by screens not yet implemented.
/// Each milestone replaces these with real UI.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({super.key, required this.icon, required this.label});

  final IconData icon;
  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 56, color: theme.colorScheme.primary),
          const SizedBox(height: 16),
          Text(
            label,
            style: theme.textTheme.titleMedium
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            textAlign: TextAlign.center,
          ),
        ],
      )
          .animate()
          .fade(duration: 500.ms)
          .scale(
            begin: const Offset(0.92, 0.92),
            end: const Offset(1, 1),
            duration: 450.ms,
            curve: Curves.easeOutBack,
          )
          .blur(begin: const Offset(4, 4), end: Offset.zero, duration: 500.ms),
    );
  }
}
