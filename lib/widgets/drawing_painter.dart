import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/text_annotation.dart';
import '../screens/pdf_editor_screen.dart';
import '/models/drawn_line.dart';

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final List<DrawnLine> highlights;
  final List<TextAnnotation> texts;

  DrawingPainter(this.lines, this.highlights, this.texts);

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

    for (final annotation in texts) {
      final textPainter = TextPainter(
        text: TextSpan(text: annotation.text, style: annotation.style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, annotation.position);

      // Highlight selected text
      if (annotation.isSelected) {
        final rect = Rect.fromLTWH(
          annotation.position.dx,
          annotation.position.dy,
          textPainter.width,
          textPainter.height,
        );
        final highlightPaint = Paint()
          ..color = Colors.blue.withOpacity(0.3)
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, highlightPaint);
      }
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
