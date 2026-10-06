import 'package:flutter/material.dart';

/// RtText's hand-drawn icon set: flat, filled shapes with soft curves that
/// speak the same visual language as the bead orb (see BeadIcon). Each glyph
/// has a single filled variant, so selected/unselected states are expressed
/// through color strength rather than outline/fill pairs.
enum RtIconType { chatBubble, explore, person, plus, send, sparkle }

/// A custom-painted icon. Flat glyphs resolve [color] against the ambient
/// [IconTheme] exactly like [Icon] does, so they theme correctly inside
/// buttons, app bars and navigation bars. The sparkle instead wears its
/// bead-brand sheen unless handed an explicit color.
class RtIcon extends StatelessWidget {
  const RtIcon({
    super.key,
    required this.type,
    this.size = 24,
    this.color,
  });

  final RtIconType type;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final iconThemeColor = type == RtIconType.sparkle
        ? color
        : (color ?? IconTheme.of(context).color);
    return CustomPaint(
      size: Size.square(size),
      painter: switch (type) {
        RtIconType.chatBubble =>
          _ChatBubblePainter(iconThemeColor ?? Colors.black),
        RtIconType.explore => _ExplorePainter(iconThemeColor ?? Colors.black),
        RtIconType.person => _PersonPainter(iconThemeColor ?? Colors.black),
        RtIconType.plus => _PlusPainter(iconThemeColor ?? Colors.black),
        RtIconType.send => _SendPainter(iconThemeColor ?? Colors.black),
        RtIconType.sparkle => _SparklePainter(iconThemeColor),
      },
    );
  }
}

/// Filled speech bubble with a little comma tail drooping from its
/// bottom-left corner.
class _ChatBubblePainter extends CustomPainter {
  const _ChatBubblePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final bubble = RRect.fromRectAndRadius(
      Rect.fromLTWH(0, 0, s, s * 0.78),
      Radius.circular(s * 0.30),
    );
    final path = Path()..addRRect(bubble);
    // The tail starts a hair inside the bubble's bottom edge so the union
    // blends it seamlessly.
    final tail = Path()
      ..moveTo(s * 0.34, s * 0.76)
      ..quadraticBezierTo(s * 0.26, s * 0.92, s * 0.12, s * 0.96)
      ..quadraticBezierTo(s * 0.23, s * 0.80, s * 0.16, s * 0.76)
      ..close();
    canvas.drawPath(
      Path.combine(PathOperation.union, path, tail),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ChatBubblePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Filled compass dial with the needle carved out, pointing north-east.
class _ExplorePainter extends CustomPainter {
  const _ExplorePainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final center = Offset(s / 2, s / 2);
    final dial = Path()
      ..addOval(Rect.fromCircle(center: center, radius: s * 0.48));
    // A thin rhombus along the north-east / south-west axis.
    final needle = Path()
      ..moveTo(center.dx + s * 0.30, center.dy - s * 0.30)
      ..lineTo(center.dx + s * 0.09, center.dy + s * 0.09)
      ..lineTo(center.dx - s * 0.30, center.dy + s * 0.30)
      ..lineTo(center.dx - s * 0.09, center.dy - s * 0.09)
      ..close();
    canvas.drawPath(
      Path.combine(PathOperation.difference, dial, needle),
      Paint()..color = color,
    );
  }

  @override
  bool shouldRepaint(covariant _ExplorePainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Filled bust: a round head sitting on a dome-shaped shoulder blob.
class _PersonPainter extends CustomPainter {
  const _PersonPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()..color = color;
    canvas.drawCircle(Offset(s / 2, s * 0.32), s * 0.21, paint);
    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(s * 0.14, s * 0.52, s * 0.72, s * 0.48),
        topLeft: Radius.circular(s * 0.36),
        topRight: Radius.circular(s * 0.36),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PersonPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Rounded plus: two crossing stadium bars with fully rounded caps.
class _PlusPainter extends CustomPainter {
  const _PlusPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint()..color = color;
    final radius = Radius.circular(s * 0.11);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.10, s * 0.39, s * 0.80, s * 0.22),
        radius,
      ),
      paint,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(s * 0.39, s * 0.10, s * 0.22, s * 0.80),
        radius,
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _PlusPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Filled paper plane gliding to the right, complete with the classic fold
/// notch on its left edge.
class _SendPainter extends CustomPainter {
  const _SendPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final path = Path()
      ..moveTo(s * 0.09, s * 0.12)
      ..lineTo(s * 0.94, s * 0.50)
      ..lineTo(s * 0.09, s * 0.88)
      ..lineTo(s * 0.09, s * 0.60)
      ..lineTo(s * 0.70, s * 0.50)
      ..lineTo(s * 0.09, s * 0.40)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(covariant _SendPainter oldDelegate) =>
      oldDelegate.color != color;
}

/// Subtle sheen for the sparkle, borrowed from the bead orb (violet to pink).
const _sparkleSheen = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFA78BFA), Color(0xFFF472B6)],
);

/// Four-point sparkle with softly concave sides. Flat when a color resolves;
/// otherwise it wears the bead-brand sheen.
class _SparklePainter extends CustomPainter {
  const _SparklePainter(this.color);

  final Color? color;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final paint = Paint();
    final explicit = color;
    if (explicit != null) {
      paint.color = explicit;
    } else {
      paint.shader = _sparkleSheen.createShader(Offset.zero & size);
    }
    final path = Path()
      ..moveTo(s / 2, s * 0.04)
      ..quadraticBezierTo(s * 0.56, s * 0.44, s * 0.96, s / 2)
      ..quadraticBezierTo(s * 0.56, s * 0.56, s / 2, s * 0.96)
      ..quadraticBezierTo(s * 0.44, s * 0.56, s * 0.04, s / 2)
      ..quadraticBezierTo(s * 0.44, s * 0.44, s / 2, s * 0.04)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _SparklePainter oldDelegate) =>
      oldDelegate.color != color;
}
