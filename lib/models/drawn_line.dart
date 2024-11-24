import 'dart:ui';

class DrawnLine {
  List<Offset> points;
  final Color color;
  final double strokeWidth;
  bool isDrawing;

  DrawnLine(this.points, this.color, this.strokeWidth,
      {this.isDrawing = false});
}
