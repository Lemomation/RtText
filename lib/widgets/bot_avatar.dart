import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

/// Bot avatar: cached network image when available, otherwise a themed
/// fallback with the bot's initial. Animates in on first appearance.
class BotAvatar extends StatelessWidget {
  const BotAvatar({super.key, required this.name, this.url, this.radius = 24});

  final String name;
  final String? url;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final fallback = CircleAvatar(
      radius: radius,
      backgroundColor: theme.colorScheme.primary.withValues(alpha: 0.15),
      child: Text(
        name.isEmpty ? '?' : name.characters.first.toUpperCase(),
        style: TextStyle(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          fontSize: radius * 0.8,
        ),
      ),
    );

    final avatar = (url == null || url!.isEmpty)
        ? fallback
        : CircleAvatar(
            radius: radius,
            backgroundColor: theme.colorScheme.surface,
            foregroundImage: CachedNetworkImageProvider(url!),
            onForegroundImageError: (_, __) {},
            child: fallback.child,
          );

    return avatar
        .animate()
        .fade(duration: 350.ms)
        .scale(
          begin: const Offset(0.7, 0.7),
          end: const Offset(1, 1),
          duration: 350.ms,
          curve: Curves.easeOutBack,
        );
  }
}
