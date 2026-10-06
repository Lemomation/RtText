import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Themed centered placeholder. Real screens still use it for error / empty
/// states; an optional [actionLabel] renders an animated action button.
class PlaceholderView extends StatelessWidget {
  const PlaceholderView({
    super.key,
    required this.icon,
    required this.label,
    this.actionLabel,
    this.onAction,
  });

  final IconData icon;
  final String label;
  final String? actionLabel;
  final VoidCallback? onAction;

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
          if (actionLabel != null) ...[
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onAction,
              child: Text(actionLabel!),
            ),
          ],
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
