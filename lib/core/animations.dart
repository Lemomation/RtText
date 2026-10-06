import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

/// Shared motion system: one duration/curve vocabulary used by every screen
/// so transitions feel consistent. Only transforms (scale/slide) and opacity
/// are animated — never layout-affecting properties — to keep 60fps.
abstract final class Motion {
  // Durations.
  static const fast = Duration(milliseconds: 150);
  static const standard = Duration(milliseconds: 250);
  static const emphasized = Duration(milliseconds: 320);
  static const slow = Duration(milliseconds: 450);

  /// Material 3 emphasized easing for entrances and page transitions.
  static const emphasizedCurve = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Decelerating curve for slides revealing content.
  static const decelerateCurve = Curves.easeOutCubic;

  /// Springy overshoot for playful pops (bubbles, buttons).
  static const springCurve = Curves.easeOutBack;

  /// Staggered entrance delay for item [index] in a list/grid, capped so long
  /// lists don't wait forever for their tail items.
  static Duration stagger(int index, {int stepMs = 40, int cap = 12}) =>
      Duration(milliseconds: (index < cap ? index * stepMs : cap * stepMs));

  /// Default route transition: fade-through with a subtle upward slide,
  /// emphasized-eased. Used for every routed screen via `pageBuilder`.
  static CustomTransitionPage<T> page<T>({
    required Widget child,
    required GoRouterState state,
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: emphasized,
      reverseTransitionDuration: standard,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curved = CurvedAnimation(
          parent: animation,
          curve: emphasizedCurve,
          reverseCurve: Curves.easeInToLinear,
        );
        return FadeTransition(
          opacity: curved,
          child: SlideTransition(
            position: Tween(
              begin: const Offset(0, 0.03),
              end: Offset.zero,
            ).animate(curved),
            child: child,
          ),
        );
      },
    );
  }
}
