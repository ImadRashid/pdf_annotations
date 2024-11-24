import 'dart:ui';

import 'package:flutter/material.dart';
import '/models/drawn_line.dart';

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final List<DrawnLine> highlights;

  DrawingPainter(this.lines, this.highlights);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final line in lines) {
      paint.color = line.color;
      paint.strokeWidth = line.strokeWidth;
      _drawPath(canvas, line);
    }

    for (final highlight in highlights) {
      paint.color = highlight.color;
      paint.strokeWidth = highlight.strokeWidth;
      _drawPath(canvas, highlight);
    }
  }

  void _drawPath(Canvas canvas, DrawnLine line) {
    if (line.points.isEmpty) return;

    final path = Path()..moveTo(line.points.first.dx, line.points.first.dy);
    for (int i = 1; i < line.points.length; i++) {
      path.lineTo(line.points[i].dx, line.points[i].dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = line.strokeWidth
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
