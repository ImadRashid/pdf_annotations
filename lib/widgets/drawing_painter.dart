import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:pdf_annotations/models/drawn_line.dart';
import 'package:pdf_annotations/models/shape_annotation.dart';
import 'package:pdf_annotations/models/text_annotation.dart';
import 'package:pdf_annotations/screens/pdf_editor_screen.dart';

class DrawingPainter extends CustomPainter {
  final List<DrawnLine> lines;
  final List<DrawnLine> highlights;
  final List<TextAnnotation> texts;
  final List<ShapeAnnotation> shapes;
  final ShapeAnnotation? currentShape;

  DrawingPainter(
    this.lines,
    this.highlights,
    this.texts, {
    this.shapes = const [],
    this.currentShape,
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
      _drawPath(canvas, line);
    }

    // Draw highlights with pan offset
    for (final highlight in highlights) {
      paint.color = highlight.color;
      paint.strokeWidth = highlight.strokeWidth;
      _drawPath(canvas, highlight);
    }

    // Draw text annotations with pan offset
    for (final annotation in texts) {
      final textPainter = TextPainter(
        text: TextSpan(text: annotation.text, style: annotation.style),
        textDirection: TextDirection.ltr,
      );
      textPainter.layout();
      textPainter.paint(canvas, annotation.position);

      if (annotation.isSelected) {
        // Draw selection rectangle
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

    // Draw shapes with pan offset
    for (final shape in shapes) {
      _drawShape(canvas, shape);
    }

    // Draw the current shape (if any) with pan offset
    if (currentShape != null) {
      _drawShape(canvas, currentShape!);
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

  void _drawShape(Canvas canvas, ShapeAnnotation shape) {
    final paint = Paint()
      ..color = shape.color
      ..style = PaintingStyle.stroke
      ..strokeWidth = shape.strokeWidth;

    switch (shape.shapeType) {
      case Mode.line:
        canvas.drawLine(shape.start, shape.end, paint);
        break;

      case Mode.rectangle:
        canvas.drawRect(Rect.fromPoints(shape.start, shape.end), paint);
        break;

      case Mode.circle:
        final radius = (shape.end - shape.start).distance / 2;
        final center = Offset((shape.start.dx + shape.end.dx) / 2,
            (shape.start.dy + shape.end.dy) / 2);
        canvas.drawCircle(center, radius, paint);
        break;

      case Mode.arrow:
        _drawArrow(canvas, shape, paint);
        break;

      default:
        break;
    }
  }

  void _drawArrow(Canvas canvas, ShapeAnnotation shape, Paint paint) {
    final arrowLength = 15.0;
    final angle = 30.0 * (math.pi / 180.0);

    final dx = shape.end.dx - shape.start.dx;
    final dy = shape.end.dy - shape.start.dy;
    final theta = math.atan2(dy, dx);

    final arrowTip1 = Offset(
      shape.end.dx - arrowLength * math.cos(theta - angle),
      shape.end.dy - arrowLength * math.sin(theta - angle),
    );
    final arrowTip2 = Offset(
      shape.end.dx - arrowLength * math.cos(theta + angle),
      shape.end.dy - arrowLength * math.sin(theta + angle),
    );

    canvas.drawLine(shape.start, shape.end, paint);
    canvas.drawLine(shape.end, arrowTip1, paint);
    canvas.drawLine(shape.end, arrowTip2, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
