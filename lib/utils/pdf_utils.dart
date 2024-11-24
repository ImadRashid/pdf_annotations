import 'dart:typed_data';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:path/path.dart' as path;

import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:flutter/material.dart';
import '/models/drawn_line.dart';
import 'package:path_provider/path_provider.dart';

class PdfUtils {
  static Future<Uint8List?> overlayDrawingOnPDF(
    String pdfPath,
    Map<int, List<DrawnLine>> pageLines, // Annotations for each page
    Map<int, List<DrawnLine>> pageHighlights,
  ) async {
    final file = File(pdfPath);
    final existingPdf = sf_pdf.PdfDocument(inputBytes: file.readAsBytesSync());

    for (int pageIndex = 0; pageIndex < existingPdf.pages.count; pageIndex++) {
      final sf_pdf.PdfPage page = existingPdf.pages[pageIndex];

      // Retrieve annotations for the current page
      final lines = pageLines[pageIndex + 1] ?? [];
      final highlights = pageHighlights[pageIndex + 1] ?? [];

      // Create a drawing canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, page.size.width, page.size.height),
      );

      // Use the custom painter to draw lines and highlights
      final painter = _TemporaryPainter(lines + highlights);
      painter.paint(canvas, Size(page.size.width, page.size.height));

      final picture = recorder.endRecording();
      final image = await picture.toImage(
        page.size.width.toInt(),
        page.size.height.toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final overlayImage = byteData!.buffer.asUint8List();

      // Add the image as an overlay on the PDF
      final overlayPdfImage = sf_pdf.PdfBitmap(overlayImage);
      page.graphics.drawImage(
        overlayPdfImage,
        Rect.fromLTWH(0, 0, page.size.width, page.size.height),
      );
    }

    // Save the modified PDF and convert List<int> to Uint8List
    final List<int> pdfBytes = await existingPdf.save();
    return Uint8List.fromList(pdfBytes);
  }

  static Future<File> saveToFile(Uint8List data, String fileName) async {
    // Get the Downloads directory
    final directory = Directory('/storage/emulated/0/Download');

    // Check if the directory exists, and create it if not
    if (!await directory.exists()) {
      await directory.create(recursive: true);
    }

    // Create the file path
    final filePath = path.join(directory.path, fileName);

    // Save the file
    final file = File(filePath);
    await file.writeAsBytes(data);
    return file;
  }
}

class _TemporaryPainter extends CustomPainter {
  final List<DrawnLine> lines;

  _TemporaryPainter(this.lines);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final line in lines) {
      paint.color = line.color;
      paint.strokeWidth = line.strokeWidth;
      for (int j = 0; j < line.points.length - 1; j++) {
        canvas.drawLine(line.points[j], line.points[j + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
