import 'package:flutter/material.dart';

/// The RtText bead: a small glossy sphere with a tri-color gradient and a
/// highlight. Custom-painted so the currency has an icon of its own (no
/// emoji anywhere in the UI).
class BeadIcon extends StatelessWidget {
  const BeadIcon({super.key, this.size = 24});

  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size.square(size),
      painter: _BeadPainter(),
    );
  }
}

class _BeadPainter extends CustomPainter {
  static const _gradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [
      Color(0xFFA78BFA), // violet
      Color(0xFFF472B6), // pink
      Color(0xFFFBBF24), // amber
    ],
  );

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final radius = rect.width / 2;

    canvas.drawCircle(
      rect.center,
      radius,
      Paint()..shader = _gradient.createShader(rect),
    );

    // Inner shading: darker bottom edge gives the sphere its depth.
    canvas.drawCircle(
      Offset(rect.center.dx, rect.center.dy + radius * 0.18),
      radius,
      Paint()
        ..shader = RadialGradient(
          center: Alignment.topLeft,
          colors: [
            Colors.white.withValues(alpha: 0.25),
            Colors.transparent,
            Colors.black.withValues(alpha: 0.25),
          ],
          stops: const [0, 0.55, 1],
        ).createShader(rect),
    );

    // Specular highlight.
    canvas.drawCircle(
      Offset(rect.center.dx - radius * 0.35, rect.center.dy - radius * 0.38),
      radius * 0.18,
      Paint()..color = Colors.white.withValues(alpha: 0.85),
    );
  }

  @override
  bool shouldRepaint(covariant _BeadPainter oldDelegate) => false;
}
