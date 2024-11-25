import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';

class PdfPageViewCanvas extends StatefulWidget {
  @override
  _PdfPageViewCanvasState createState() => _PdfPageViewCanvasState();
}

class _PdfPageViewCanvasState extends State<PdfPageViewCanvas> {
  List<ui.Image> _pdfImages = [];
  int _totalPages = 0;
  String? _selectedPdfPath;
  List<List<Offset?>> _drawings = []; // Store drawing points for each page
  int _currentPage = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('PDF Viewer with Drawing'),
        actions: [
          IconButton(
            icon: Icon(Icons.folder_open),
            onPressed: _pickPdfFile,
          ),
        ],
      ),
      body: _selectedPdfPath == null
          ? Center(
              child: Text('Please select a PDF file to display'),
            )
          : _pdfImages.isEmpty
              ? Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onScaleUpdate: (details) {
                          setState(() {
                            final localPosition = details.localFocalPoint;
                            _drawings[_currentPage].add(localPosition);
                          });
                        },
                        onScaleEnd: (_) {
                          setState(() {
                            _drawings[_currentPage].add(null);
                          });
                        },
                        child: Stack(
                          children: [
                            CustomPaint(
                              painter: PdfPagePainter(_pdfImages[_currentPage]),
                              child: Container(),
                            ),
                            CustomPaint(
                              painter: DrawingPainter(_drawings[_currentPage]),
                            ),
                          ],
                        ),
                      ),
                    ),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        ElevatedButton(
                          onPressed: _currentPage > 0
                              ? () {
                                  setState(() {
                                    _currentPage--;
                                  });
                                }
                              : null,
                          child: Text('Back'),
                        ),
                        Text(
                          'Page ${_currentPage + 1} of $_totalPages',
                          style: TextStyle(fontSize: 16),
                        ),
                        ElevatedButton(
                          onPressed: _currentPage < _totalPages - 1
                              ? () {
                                  setState(() {
                                    _currentPage++;
                                  });
                                }
                              : null,
                          child: Text('Next'),
                        ),
                      ],
                    ),
                  ],
                ),
    );
  }

  Future<void> _pickPdfFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null) {
        String? filePath = result.files.single.path;

        if (filePath != null) {
          setState(() {
            _selectedPdfPath = filePath;
            _pdfImages = [];
            _totalPages = 0;
            _drawings = [];
          });

          _loadAndRasterizePdf(filePath);
        }
      }
    } catch (e) {
      print('Error picking file: $e');
    }
  }

  Future<void> _loadAndRasterizePdf(String filePath) async {
    try {
      // Load the PDF file
      final file = File(filePath);
      final documentBytes = await file.readAsBytes();

      // Determine optimal DPI based on screen dimensions
      final screenSize = MediaQuery.of(context).size;
      final targetWidth =
          screenSize.width * MediaQuery.of(context).devicePixelRatio;
      const baseDpi = 72; // Default DPI for PDF
      final dpi = (targetWidth / baseDpi)
          .clamp(150, 500); // Limit DPI between 150 and 300

      // Use Printing to rasterize the PDF with optimal DPI
      final pages = Printing.raster(documentBytes, dpi: 300);

      int pageCount = 0;
      final List<ui.Image> images = [];
      await for (var page in pages) {
        final image = await page.toImage();
        images.add(image);
        _drawings.add([]); // Initialize an empty list for each page's drawings
        pageCount++;
      }

      setState(() {
        _pdfImages = images;
        _totalPages = pageCount;
      });
    } catch (e) {
      print('Error loading or rasterizing PDF: $e');
    }
  }

  Future<void> _loadPage(int pageIndex) async {
    try {
      final file = File(_selectedPdfPath!);
      final documentBytes = await file.readAsBytes();

      final dpi = 300; // Fixed DPI or dynamically calculated
      final page = await Printing.raster(documentBytes,
          dpi: dpi.toDouble(), pages: [pageIndex]).first;
      final image = await page.toImage();

      setState(() {
        if (_pdfImages.length <= pageIndex) {
          _pdfImages.add(image);
        } else {
          _pdfImages[pageIndex] = image;
        }
      });
    } catch (e) {
      print('Error loading page: $e');
    }
  }
}

class PdfPagePainter extends CustomPainter {
  final ui.Image pdfImage;

  PdfPagePainter(this.pdfImage);

  @override
  void paint(Canvas canvas, Size size) {
    // Calculate the scaling factor while maintaining aspect ratio
    final imageAspectRatio = pdfImage.width / pdfImage.height;
    final canvasAspectRatio = size.width / size.height;

    Rect imageRect;
    if (imageAspectRatio > canvasAspectRatio) {
      // Image is wider than the canvas
      final scaledHeight = size.width / imageAspectRatio;
      imageRect = Rect.fromLTWH(
        0,
        (size.height - scaledHeight) / 2, // Center vertically
        size.width,
        scaledHeight,
      );
    } else {
      // Image is taller than the canvas
      final scaledWidth = size.height * imageAspectRatio;
      imageRect = Rect.fromLTWH(
        (size.width - scaledWidth) / 2, // Center horizontally
        0,
        scaledWidth,
        size.height,
      );
    }

    final imageRectSource = Rect.fromLTWH(
      0,
      0,
      pdfImage.width.toDouble(),
      pdfImage.height.toDouble(),
    );

    // Draw the scaled PDF image
    final paint = Paint();
    canvas.drawImageRect(pdfImage, imageRectSource, imageRect, paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset?> points;

  DrawingPainter(this.points);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return true;
  }
}

void main() {
  runApp(MaterialApp(
    home: PdfPageViewCanvas(),
  ));
}
