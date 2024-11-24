import 'package:flutter/material.dart';

class TextAnnotation {
  Offset position;
  String text;
  TextStyle style;
  bool isSelected;

  TextAnnotation(this.position, this.text, this.style,
      {this.isSelected = false});
}
