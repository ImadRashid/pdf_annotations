import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:isolate';
import 'dart:io';
import 'package:flutter/foundation.dart';
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
    final file = File(pdfPath);
    final existingPdf = sf_pdf.PdfDocument(inputBytes: file.readAsBytesSync());

    for (int pageIndex = 0; pageIndex < existingPdf.pages.count; pageIndex++) {
      final sf_pdf.PdfPage page = existingPdf.pages[pageIndex];

      final sf_pdf.PdfPageLayer layer = page.layers.add(name: 'Annotations');

      final lines = pageLines[pageIndex + 1] ?? [];
      final highlights = pageHighlights[pageIndex + 1] ?? [];

      // Generate annotation image on the main isolate
      final imageBytes =
          await _generateAnnotationImage(lines + highlights, page.size);

      if (imageBytes != null) {
        final sf_pdf.PdfBitmap pdfBitmap = sf_pdf.PdfBitmap(imageBytes);
        layer.graphics.drawImage(
          pdfBitmap,
          Rect.fromLTWH(0, 0, page.size.width, page.size.height),
        );
      }
    }

    final List<int> pdfBytes = existingPdf.saveSync();
    return Uint8List.fromList(pdfBytes);
  }

  static Future<Uint8List?> _generateAnnotationImage(
    List<DrawnLine> lines,
    Size pageSize,
  ) async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(
      recorder,
      Rect.fromLTWH(0, 0, pageSize.width, pageSize.height),
    );

    final painter = _AnnotationPainter(lines);
    painter.paint(canvas, Size(pageSize.width, pageSize.height));

    final picture = recorder.endRecording();
    final image = await picture.toImage(
      pageSize.width.toInt(),
      pageSize.height.toInt(),
    );

    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData?.buffer.asUint8List();
  }

  static Future<File> saveToFile(Uint8List data, String fileName) async {
    final args = SaveArgs(data, fileName);
    return compute(_processSaveToFile, args);
  }

  static File _processSaveToFile(SaveArgs args) {
    final directory = Directory('/storage/emulated/0/Download');

    if (!directory.existsSync()) {
      directory.createSync(recursive: true);
    }

    final filePath = path.join(directory.path, args.fileName);
    final file = File(filePath);
    file.writeAsBytesSync(args.data);
    return file;
  }

  static Future<bool> requestStoragePermission() async {
    var status = await Permission.storage.status;
    if (!status.isGranted) {
      status = await Permission.storage.request();
    }
    return status.isGranted;
  }
}

class SaveArgs {
  final Uint8List data;
  final String fileName;

  SaveArgs(this.data, this.fileName);
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
