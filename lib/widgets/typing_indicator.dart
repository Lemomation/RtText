import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Three-dot typing indicator shown while waiting for the AI reply.
class TypingIndicator extends StatelessWidget {
  const TypingIndicator({super.key, this.label = 'typing…'});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(left: 12, top: 6, bottom: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 5),
              _Dot(delay: Duration(milliseconds: 150 * i)),
            ],
            const SizedBox(width: 8),
            Text(
              label,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.delay});

  final Duration delay;

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.primary;
    return Container(
      width: 7,
      height: 7,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
    )
        .animate(delay: delay, onPlay: (c) => c.repeat(reverse: true))
        .moveY(begin: 0, end: -3.5, duration: 350.ms, curve: Curves.easeInOut)
        .scale(
          begin: const Offset(0.8, 0.8),
          end: const Offset(1.1, 1.1),
          duration: 350.ms,
        );
  }
}
