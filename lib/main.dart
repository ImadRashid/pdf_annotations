import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
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
  List<List<Offset?>> _drawings = [];
  int _currentPage = 0;
  bool isHandMode = false;
  double _scale = 1.0;
  Offset _offset = Offset(0, 0);
  late Offset _lastFocalPoint;

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
          IconButton(
            icon: Icon(isHandMode ? Icons.pan_tool : Icons.brush),
            onPressed: _toggleDrawingMode,
          ),
        ],
      ),
      body: _selectedPdfPath == null
          ? Center(child: Text('Please select a PDF file to display'))
          : _pdfImages.isEmpty
              ? Center(child: CircularProgressIndicator())
              : Column(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onScaleStart: (details) {
                          _lastFocalPoint = details.localFocalPoint;
                        },
                        onScaleUpdate: (details) {
                          if (isHandMode) {
                            setState(() {
                              _offset = _offset +
                                  details.localFocalPoint -
                                  _lastFocalPoint;
                              _lastFocalPoint = details.localFocalPoint;
                            });
                          } else {
                            setState(() {
                              _scale = (_scale * details.scale).clamp(1.0, 3.0);
                            });
                          }
                        },
                        onPanUpdate: isHandMode
                            ? (details) {
                                setState(() {
                                  _offset +=
                                      details.localPosition - _lastFocalPoint;
                                });
                                _lastFocalPoint = details.localPosition;
                              }
                            : null,
                        child: Stack(
                          children: [
                            CustomPaint(
                              painter: PdfPagePainter(
                                _pdfImages[_currentPage],
                                _scale,
                                _offset,
                              ),
                              child: Container(),
                            ),
                            CustomPaint(
                              painter: DrawingPainter(
                                _drawings[_currentPage],
                                _scale,
                                _offset,
                              ),
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

  // Toggle between drawing mode and pan (hand) mode
  void _toggleDrawingMode() {
    setState(() {
      isHandMode = !isHandMode;
    });
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
      final file = File(filePath);
      final documentBytes = await file.readAsBytes();

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

  // Convert ui.Image to PNG bytes
  Future<Uint8List> _convertUiImageToBytes(ui.Image image) async {
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  }

  Future<void> _savePdf() async {
    try {
      final pdfDocument = pw.Document();

      for (int i = 0; i < _totalPages; i++) {
        final imageBytes = await _convertUiImageToBytes(_pdfImages[i]);

        // Create a PdfImage from the byte data
        final pdfImage = PdfImage(
          pdfDocument.document,
          image: imageBytes,
          width: _pdfImages[i].width,
          height: _pdfImages[i].height,
        );

        // Add the image to the PDF page
        final page = pw.Page(
          build: (pw.Context context) {
            return pw.Image(pdfImage);
          },
        );
        pdfDocument.addPage(page);
      }

      final outputFile = File('${_selectedPdfPath}_modified.pdf');
      await outputFile.writeAsBytes(await pdfDocument.save());

      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('PDF saved successfully!'),
      ));
    } catch (e) {
      print('Error saving PDF: $e');
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Failed to save PDF.'),
      ));
    }
  }
}

class PdfPagePainter extends CustomPainter {
  final ui.Image pdfImage;
  final double scale;
  final Offset offset;

  PdfPagePainter(this.pdfImage, this.scale, this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    final imageAspectRatio = pdfImage.width / pdfImage.height;
    final canvasAspectRatio = size.width / size.height;

    Rect imageRect;
    if (imageAspectRatio > canvasAspectRatio) {
      final scaledHeight = size.width / imageAspectRatio;
      imageRect = Rect.fromLTWH(
        0,
        (size.height - scaledHeight) / 2,
        size.width,
        scaledHeight,
      );
    } else {
      final scaledWidth = size.height * imageAspectRatio;
      imageRect = Rect.fromLTWH(
        (size.width - scaledWidth) / 2,
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

    final paint = Paint();
    canvas.drawImageRect(pdfImage, imageRectSource, imageRect, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) {
    return false;
  }
}

class DrawingPainter extends CustomPainter {
  final List<Offset?> points;
  final double scale;
  final Offset offset;

  DrawingPainter(this.points, this.scale, this.offset);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.red
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(scale);

    for (int i = 0; i < points.length - 1; i++) {
      if (points[i] != null && points[i + 1] != null) {
        canvas.drawLine(points[i]!, points[i + 1]!, paint);
      }
    }

    canvas.restore();
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
