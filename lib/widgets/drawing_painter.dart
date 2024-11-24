import 'dart:ui';
import 'package:flutter/material.dart';
import '../models/text_annotation.dart';
import '../screens/pdf_editor_screen.dart';
import '/models/drawn_line.dart';

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final List<DrawnLine> highlights;
  final List<TextAnnotation>? textAnnotations;

  DrawingPainter(this.lines, this.highlights, {this.textAnnotations});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw lines
    for (final line in lines) {
      paint.color = line.color;
      paint.strokeWidth = line.strokeWidth;
      _drawPath(canvas, line);
    }

    // Draw highlights
    for (final highlight in highlights) {
      paint.color = highlight.color;
      paint.strokeWidth = highlight.strokeWidth;
      _drawPath(canvas, highlight);
    }

    // Draw text annotations
    if (textAnnotations != null) {
      for (final annotation in textAnnotations!) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: annotation.text,
            style: TextStyle(
              color: Colors.black,
              fontSize: 14, // Default text size
            ),
          ),
          textDirection: TextDirection.ltr,
        );

        textPainter.layout();
        textPainter.paint(canvas, annotation.position);
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
