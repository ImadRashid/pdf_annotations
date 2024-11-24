import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import '../models/drawn_line.dart';

class PdfUtils {
  static Future<Uint8List?> overlayDrawingOnPDF(
    String pdfPath,
    Map<int, List<DrawnLine>> pageLines,
    Map<int, List<DrawnLine>> pageHighlights,
  ) async {
    // Load the existing PDF
    final file = File(pdfPath);
    final existingPdf = sf_pdf.PdfDocument(inputBytes: file.readAsBytesSync());

    // Iterate through each page
    for (int pageIndex = 0; pageIndex < existingPdf.pages.count; pageIndex++) {
      final sf_pdf.PdfPage page = existingPdf.pages[pageIndex];

      // Add a new layer for annotations
      final sf_pdf.PdfPageLayer layer = page.layers.add(name: 'Annotations');

      // Retrieve annotations for this page
      final lines = pageLines[pageIndex + 1] ?? [];
      final highlights = pageHighlights[pageIndex + 1] ?? [];

      // Create a drawing canvas
      final recorder = ui.PictureRecorder();
      final canvas = Canvas(
        recorder,
        Rect.fromLTWH(0, 0, page.size.width, page.size.height),
      );

      // Use a custom painter to draw annotations
      final painter = _AnnotationPainter(lines + highlights);
      painter.paint(canvas, Size(page.size.width, page.size.height));

      // Convert the canvas to an image
      final picture = recorder.endRecording();
      final image = await picture.toImage(
        page.size.width.toInt(),
        page.size.height.toInt(),
      );
      final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
      final overlayImage = byteData!.buffer.asUint8List();

      // Add the canvas image to the layer
      final sf_pdf.PdfBitmap pdfBitmap = sf_pdf.PdfBitmap(overlayImage);
      layer.graphics.drawImage(
        pdfBitmap,
        Rect.fromLTWH(0, 0, page.size.width, page.size.height),
      );
    }

    // Save the modified PDF
    final List<int> pdfBytes = existingPdf.saveSync();
    return Uint8List.fromList(pdfBytes);
  }

  static Future<File> saveToFile(Uint8List data, String fileName) async {
    // Request storage permission
    // if (!await requestStoragePermission()) {
    //   throw Exception("Storage permission not granted");
    // }
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

  // Static function to request storage permission
  static Future<bool> requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }
}

class _AnnotationPainter extends CustomPainter {
  final List<DrawnLine> lines;

  _AnnotationPainter(this.lines);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;

    for (final line in lines) {
      paint.color = line.color;
      paint.strokeWidth = line.strokeWidth;
      for (int i = 0; i < line.points.length - 1; i++) {
        canvas.drawLine(line.points[i], line.points[i + 1], paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
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
      canvas.drawPoints(PointMode.polygon, line.points, paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => true;
}
