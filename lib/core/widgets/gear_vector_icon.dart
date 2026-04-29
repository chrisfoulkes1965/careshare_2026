import "dart:math" as math;

import "package:flutter/material.dart";

/// Settings-style gear drawn with [Canvas] — reliable on Flutter web release builds
/// where tree-shaken icon fonts sometimes omit glyphs for specific [Icon]s.
class GearVectorIcon extends StatelessWidget {
  const GearVectorIcon({
    super.key,
    required this.size,
    required this.color,
  });

  final double size;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(size, size),
      painter: _GearVectorPainter(color: color),
    );
  }
}

class _GearVectorPainter extends CustomPainter {
  _GearVectorPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.shortestSide;
    final cx = size.width / 2;
    final cy = size.height / 2;
    canvas.save();
    canvas.translate(cx, cy);

    final ring = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.11;

    canvas.drawCircle(Offset.zero, w * 0.28, ring);

    final tooth = Paint()..color = color..style = PaintingStyle.fill;
    const toothCount = 6;
    for (var i = 0; i < toothCount; i++) {
      canvas.save();
      final theta = math.pi / 2 + i * (2 * math.pi / toothCount);
      canvas.rotate(theta);
      final rrect = RRect.fromRectAndRadius(
        Rect.fromCenter(
          center: Offset(0, -w * 0.4),
          width: w * 0.26,
          height: w * 0.13,
        ),
        Radius.circular(w * 0.04),
      );
      canvas.drawRRect(rrect, tooth);
      canvas.restore();
    }

    canvas.drawCircle(Offset.zero, w * 0.1, tooth);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GearVectorPainter oldDelegate) =>
      oldDelegate.color != color;
}
