import 'dart:ui' as ui;
import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart' as sf_pdf;
import 'package:path/path.dart' as path;
import 'package:permission_handler/permission_handler.dart';
import '../models/drawn_line.dart';
import '../models/text_annotation.dart';

class PdfUtils {
  static Future<Uint8List?> overlayDrawingOnPDF(
    String pdfPath,
    Map<int, List<DrawnLine>> pageLines,
    Map<int, List<DrawnLine>> pageHighlights,
    Map<int, List<TextAnnotation>> pageTexts,
  ) async {
    try {
      final file = File(pdfPath);
      if (!file.existsSync()) throw Exception('PDF file not found.');

      final existingPdf =
          sf_pdf.PdfDocument(inputBytes: file.readAsBytesSync());

      for (int pageIndex = 0;
          pageIndex < existingPdf.pages.count;
          pageIndex++) {
        final sf_pdf.PdfPage page = existingPdf.pages[pageIndex];
        final lines = pageLines[pageIndex + 1] ?? [];
        final highlights = pageHighlights[pageIndex + 1] ?? [];
        final texts = pageTexts[pageIndex + 1] ?? [];

        // Drawing highlights and lines on a layer
        final drawingLayer = page.layers.add(name: 'DrawingLayer');
        final annotationImage = await _generateAnnotationImage(
          _scaleLines(lines + highlights, page.size),
          page.size,
        );

        if (annotationImage != null) {
          final sf_pdf.PdfBitmap pdfBitmap = sf_pdf.PdfBitmap(annotationImage);
          drawingLayer.graphics.drawImage(
            pdfBitmap,
            Rect.fromLTWH(
              0,
              0,
              page.size.width, // Use unscaled page size
              page.size.height,
            ),
          );
        }

        // Adding text annotations to another layer
        final textLayer = page.layers.add(name: 'TextAnnotations');
        for (final annotation in texts) {
          final scaledPosition =
              _getAbsoluteOffset(annotation.position, page.size);
          final font = sf_pdf.PdfStandardFont(
            sf_pdf.PdfFontFamily.helvetica,
            annotation.style.fontSize ?? 12, // Keep original font size
          );

          final color = annotation.style.color ?? Colors.black;
          final pdfColor = sf_pdf.PdfColor(color.red, color.green, color.blue);
          textLayer.graphics.drawString(
            annotation.text,
            font,
            brush: sf_pdf.PdfSolidBrush(pdfColor),
            bounds: Rect.fromLTWH(
              scaledPosition.dx,
              scaledPosition.dy,
              page.size.width, // Adjusted bounds
              page.size.height,
            ),
          );
        }
      }

      // Save and return the modified PDF
      final List<int> pdfBytes = existingPdf.saveSync();
      existingPdf.dispose();
      return Uint8List.fromList(pdfBytes);
    } catch (e) {
      debugPrint('Error overlaying PDF: $e');
      return null;
    }
  }

  static List<DrawnLine> _scaleLines(
    List<DrawnLine> lines,
    Size pageSize,
  ) {
    return lines.map((line) {
      return DrawnLine(
        line.points
            .map((point) => _getAbsoluteOffset(point, pageSize))
            .toList(),
        line.color,
        line.strokeWidth, // Keep original stroke width
        isDrawing: line.isDrawing,
      );
    }).toList();
  }

  static Offset _getAbsoluteOffset(Offset normalizedOffset, Size pageSize) {
    return Offset(
      normalizedOffset.dx * pageSize.width,
      normalizedOffset.dy * pageSize.height,
    );
  }

  static Future<Uint8List?> _generateAnnotationImage(
    List<DrawnLine> lines,
    Size pageSize,
  ) async {
    try {
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
    } catch (e) {
      debugPrint('Error generating annotation image: $e');
      return null;
    }
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
    if (Platform.isAndroid) {
      var status = await Permission.storage.status;
      if (!status.isGranted) {
        status = await Permission.storage.request();
      }
      return status.isGranted;
    }
    return true;
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
