import 'package:flutter/material.dart';
import 'package:pdf_annotations/screens/pdf_editor_screen.dart';

class ShapeAnnotation {
  final Offset start;
  final Offset end;
  final Mode shapeType;
  final Color color;
  final double strokeWidth;

  ShapeAnnotation({
    required this.start,
    required this.end,
    required this.shapeType,
    required this.color,
    required this.strokeWidth,
  });

  // Add the copyWith method
  ShapeAnnotation copyWith({
    Offset? start,
    Offset? end,
    Mode? shapeType,
    Color? color,
    double? strokeWidth,
  }) {
    return ShapeAnnotation(
      start: start ?? this.start,
      end: end ?? this.end,
      shapeType: shapeType ?? this.shapeType,
      color: color ?? this.color,
      strokeWidth: strokeWidth ?? this.strokeWidth,
    );
  }
}
