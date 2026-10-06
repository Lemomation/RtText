import 'package:flutter/material.dart';
import 'package:rttext/core/animations.dart';

/// Wraps a child in a springy press-down scale for tactile feedback.
/// Transform-only, so it composes safely with ripples and heroes.
class PressableScale extends StatefulWidget {
  const PressableScale({
    super.key,
    required this.onTap,
    required this.child,
    this.pressedScale = 0.96,
  });

  final VoidCallback? onTap;
  final Widget child;
  final double pressedScale;

  @override
  State<PressableScale> createState() => _PressableScaleState();
}

class _PressableScaleState extends State<PressableScale> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapUp: (_) => setState(() => _pressed = false),
      onTapCancel: () => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? widget.pressedScale : 1,
        duration: Motion.fast,
        curve: Motion.emphasizedCurve,
        child: widget.child,
      ),
    );
  }
}
