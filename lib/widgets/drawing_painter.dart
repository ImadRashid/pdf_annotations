import 'dart:ui';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf_annotations/models/shape_annotation.dart';
import '../models/text_annotation.dart';
import '../screens/pdf_editor_screen.dart';
import '/models/drawn_line.dart';

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final List<DrawnLine> highlights;
  final List<TextAnnotation> texts;
  final List<ShapeAnnotation> shapes;
  final ShapeAnnotation? currentShape;
  final Offset panOffset; // Add panOffset here

  DrawingPainter(
    this.lines,
    this.highlights,
    this.texts, {
    this.shapes = const [],
    this.currentShape,
    required this.panOffset, // Initialize panOffset
  });

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    // Draw freehand lines with pan offset
    for (final line in lines) {
      paint.color = line.color;
      paint.strokeWidth = line.strokeWidth;
      _drawPath(canvas, line, panOffset); // Pass panOffset to _drawPath
    }

    // Draw highlights with pan offset
    for (final highlight in highlights) {
      paint.color = highlight.color;
      paint.strokeWidth = highlight.strokeWidth;
      _drawPath(canvas, highlight, panOffset); // Pass panOffset to _drawPath
    }

    // Draw text annotations with pan offset
    for (final annotation in texts) {
      final textPainter = TextPainter(
        text: TextSpan(text: annotation.text, style: annotation.style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas,
          annotation.position + panOffset); // Apply pan offset to position

      if (annotation.isSelected) {
        // Draw selection rectangle
        final rect = Rect.fromLTWH(
          annotation.position.dx + panOffset.dx,
          annotation.position.dy + panOffset.dy,
          textPainter.width,
          textPainter.height,
        );
        final highlightPaint = Paint()
          ..color = Colors.blue.withOpacity(0.3)
          ..style = PaintingStyle.fill;
        canvas.drawRect(rect, highlightPaint);
      }
    }

    // Draw shapes with pan offset
    for (final shape in shapes) {
      _drawShape(canvas, shape, panOffset); // Pass panOffset to _drawShape
    }

    // Draw the current shape (if any) with pan offset
    if (currentShape != null) {
      _drawShape(
          canvas, currentShape!, panOffset); // Pass panOffset to _drawShape
    }
  }

  void _drawPath(Canvas canvas, DrawnLine line, Offset panOffset) {
    if (line.points.isEmpty) return;

    final path = Path()
      ..moveTo(line.points.first.dx + panOffset.dx,
          line.points.first.dy + panOffset.dy);
    for (int i = 1; i < line.points.length; i++) {
      path.lineTo(
          line.points[i].dx + panOffset.dx, line.points[i].dy + panOffset.dy);
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = line.color
          ..style = PaintingStyle.stroke
          ..strokeWidth = line.strokeWidth
          ..strokeCap = StrokeCap.round);
  }

  void _drawShape(Canvas canvas, ShapeAnnotation shape, Offset panOffset) {
    final paint = Paint()
      ..color = shape.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.strokeWidth;

    switch (shape.shapeType) {
      case Mode.line:
        // Draw a straight line with pan offset
        canvas.drawLine(
          shape.start + panOffset,
          shape.end + panOffset,
          paint,
        );
        break;

      case Mode.rectangle:
        // Draw a rectangle with pan offset
        canvas.drawRect(
          Rect.fromPoints(shape.start + panOffset, shape.end + panOffset),
          paint,
        );
        break;

      case Mode.circle:
        // Draw a circle with pan offset
        final radius = (shape.end - shape.start).distance / 2;
        final center = Offset(
          (shape.start.dx + shape.end.dx) / 2 + panOffset.dx,
          (shape.start.dy + shape.end.dy) / 2 + panOffset.dy,
        );
        canvas.drawCircle(center, radius, paint);
        break;

      case Mode.arrow:
        // Draw an arrow with pan offset
        _drawArrow(canvas, shape, paint, panOffset);
        break;

      default:
        break;
    }
  }

  void _drawArrow(
      Canvas canvas, ShapeAnnotation shape, Paint paint, Offset panOffset) {
    final arrowLength = 15.0; // Length of the arrowhead lines
    final angle = 30.0 * (math.pi / 180.0); // Angle of the arrowhead

    final dx = shape.end.dx - shape.start.dx;
    final dy = shape.end.dy - shape.start.dy;
    final theta = math.atan2(dy, dx);

    // Calculate arrowhead points with pan offset
    final arrowTip1 = Offset(
      shape.end.dx - arrowLength * math.cos(theta - angle) + panOffset.dx,
      shape.end.dy - arrowLength * math.sin(theta - angle) + panOffset.dy,
    );
    final arrowTip2 = Offset(
      shape.end.dx - arrowLength * math.cos(theta + angle) + panOffset.dx,
      shape.end.dy - arrowLength * math.sin(theta + angle) + panOffset.dy,
    );

    // Draw the arrow body
    canvas.drawLine(shape.start + panOffset, shape.end + panOffset, paint);

    // Draw the arrowhead
    canvas.drawLine(shape.end + panOffset, arrowTip1, paint);
    canvas.drawLine(shape.end + panOffset, arrowTip2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
