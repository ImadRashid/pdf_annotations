import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf_render/pdf_render.dart';
import 'dart:ui' as ui;
import 'dart:typed_data';

void main() {
  runApp(MaterialApp(home: PDFDrawingApp()));
}

class PDFDrawingApp extends StatefulWidget {
  @override
  _PDFDrawingAppState createState() => _PDFDrawingAppState();
}

class _PDFDrawingAppState extends State<PDFDrawingApp> {
  ui.Image? pdfImage;
  List<Offset?> points = [];
  Size? originalPDFSize;
  Rect? pdfBounds; // Store the bounds of the PDF on screen

  Future<void> pickAndLoadPDF() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      final path = result.files.single.path!;
      final doc = await PdfDocument.openFile(path);
      final page = await doc.getPage(1);

      originalPDFSize = Size(page.width, page.height);

      final int renderWidth = (page.width * 2).toInt();
      final int renderHeight = (page.height * 2).toInt();

      final image = await page.render(
        width: renderWidth,
        height: renderHeight,
      );

      final ui.Image renderedImage = await image.createImageDetached();

      setState(() {
        if (pdfImage != null) {
          pdfImage!.dispose();
        }
        pdfImage = renderedImage;
        points.clear();
      });
    }
  }

  bool isPointInPDFBounds(Offset point) {
    return pdfBounds?.contains(point) ?? false;
  }

  Offset? transformPoint(Offset point, Size screenSize) {
    if (originalPDFSize == null ||
        pdfImage == null ||
        !isPointInPDFBounds(point)) {
      return null;
    }

    final double scaleX = screenSize.width / pdfImage!.width;
    final double scaleY = screenSize.height / pdfImage!.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    final double left = (screenSize.width - (pdfImage!.width * scale)) / 2;
    final double top = (screenSize.height - (pdfImage!.height * scale)) / 2;

    return Offset(
      (point.dx - left) / scale,
      (point.dy - top) / scale,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PDF Drawing App'),
        actions: [
          IconButton(
            icon: Icon(Icons.file_upload),
            onPressed: pickAndLoadPDF,
          ),
          IconButton(
            icon: Icon(Icons.clear),
            onPressed: () => setState(() => points.clear()),
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final screenSize = Size(constraints.maxWidth, constraints.maxHeight);

          if (pdfImage != null) {
            final double scaleX = screenSize.width / pdfImage!.width;
            final double scaleY = screenSize.height / pdfImage!.height;
            final double scale = scaleX < scaleY ? scaleX : scaleY;

            final double left =
                (screenSize.width - (pdfImage!.width * scale)) / 2;
            final double top =
                (screenSize.height - (pdfImage!.height * scale)) / 2;

            // Update PDF bounds
            pdfBounds = Rect.fromLTWH(
              left,
              top,
              pdfImage!.width * scale,
              pdfImage!.height * scale,
            );
          }

          return pdfImage == null
              ? Center(child: Text('Please select a PDF file'))
              : Stack(
                  children: [
                    // Gray background
                    Container(color: Colors.grey[300]),
                    // PDF drawing area
                    GestureDetector(
                      onPanUpdate: (details) {
                        final RenderBox renderBox =
                            context.findRenderObject() as RenderBox;
                        final Offset localPosition =
                            renderBox.globalToLocal(details.globalPosition);

                        if (isPointInPDFBounds(localPosition)) {
                          final transformedPoint =
                              transformPoint(localPosition, screenSize);
                          if (transformedPoint != null) {
                            setState(() {
                              points.add(transformedPoint);
                            });
                          }
                        }
                      },
                      onPanEnd: (details) {
                        setState(() {
                          points.add(null);
                        });
                      },
                      child: CustomPaint(
                        painter: PDFDrawingPainter(
                          pdfImage: pdfImage!,
                          points: points,
                          originalPDFSize: originalPDFSize!,
                        ),
                        size: Size.infinite,
                      ),
                    ),
                  ],
                );
        },
      ),
    );
  }

  @override
  void dispose() {
    pdfImage?.dispose();
    super.dispose();
  }
}

class PDFDrawingPainter extends CustomPainter {
  final ui.Image pdfImage;
  final List<Offset?> points;
  final Size originalPDFSize;

  PDFDrawingPainter({
    required this.pdfImage,
    required this.points,
    required this.originalPDFSize,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final double scaleX = size.width / pdfImage.width;
    final double scaleY = size.height / pdfImage.height;
    final double scale = scaleX < scaleY ? scaleX : scaleY;

    final double left = (size.width - (pdfImage.width * scale)) / 2;
    final double top = (size.height - (pdfImage.height * scale)) / 2;

    // Draw PDF page
    canvas.save();
    canvas.translate(left, top);
    canvas.scale(scale);
    canvas.drawImage(pdfImage, Offset.zero, Paint());

    // Draw lines in PDF coordinates
    Paint paint = Paint()
      ..color = Colors.red
      ..strokeCap = StrokeCap.round
      ..strokeWidth = 4.0 / scale;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(PDFDrawingPainter oldDelegate) => true;
}
