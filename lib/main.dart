import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:pdf_render/pdf_render.dart' as pr;

void main() {
  runApp(DrawingApp());
}

class DrawingApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Drawing App',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        useMaterial3: true,
      ),
      home: ZoomableDrawingCanvas(),
    );
  }
}

class DrawingLine {
  final List<Offset> points;
  final Color color;
  final double strokeWidth;
  final bool isEraser;

  DrawingLine({
    required this.points,
    required this.color,
    required this.strokeWidth,
    this.isEraser = false,
  });

  List<Offset> getTransformedPoints(double zoom, Offset offset) {
    return points.map((point) {
      return (point * zoom) + offset;
    }).toList();
  }
}

class ZoomableDrawingCanvas extends StatefulWidget {
  @override
  _ZoomableDrawingCanvasState createState() => _ZoomableDrawingCanvasState();
}

class _ZoomableDrawingCanvasState extends State<ZoomableDrawingCanvas> {
  Size? pdfPageSize;
  double? aspectRatio;
  double maxWidth = 1000.0; // Maximum width constraint for very large PDFs
  List<DrawingLine> lines = [];
  DrawingLine? currentLine;

  double zoom = 1.0;
  Offset offset = Offset.zero;
  bool isDrawingMode = true;
  bool isErasing = false;
  bool isDrawingActive = false;

  double strokeWidth = 2.0;
  double eraserWidth = 20.0;

  double previousZoom = 1.0;
  Offset previousOffset = Offset.zero;
  Size? originalPDFSize;
  Rect? pdfBounds; // Store the bounds of the PDF on screen
  static const double canvasWidth = 600;
  static const double canvasHeight = 500;
  final GlobalKey canvasKey = GlobalKey();

  ui.Image? pdfImage;

  Future<void> pickAndLoadPDF() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null) {
      final path = result.files.single.path!;
      final doc = await pr.PdfDocument.openFile(path);
      final page = await doc.getPage(1);

      // Store original PDF dimensions
      pdfPageSize = Size(page.width, page.height);
      aspectRatio = page.width / page.height;

      // Calculate render dimensions while maintaining aspect ratio
      double renderWidth = page.width;
      double renderHeight = page.height;

      // Scale down if width exceeds maxWidth
      if (renderWidth > maxWidth) {
        renderWidth = maxWidth;
        renderHeight = renderWidth / aspectRatio!;
      }

      final image = await page.render(
        width: renderWidth.toInt(),
        height: renderHeight.toInt(),
        fullWidth: renderWidth,
        fullHeight: renderHeight,
        // backgroundColor: '#FFFFFF',
      );

      final ui.Image renderedImage = await image.createImageDetached();

      setState(() {
        if (pdfImage != null) {
          pdfImage!.dispose();
        }
        pdfImage = renderedImage;
        // Reset view
        zoom = 1.0;
        offset = Offset.zero;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Calculate container dimensions based on PDF size
    double containerWidth = pdfPageSize?.width ?? canvasWidth;
    double containerHeight = pdfPageSize?.height ?? canvasHeight;

    // Scale container if needed
    if (containerWidth > maxWidth) {
      containerHeight = maxWidth / aspectRatio!;
      containerWidth = maxWidth;
    }
    return Scaffold(
      appBar: AppBar(
        actions: [
          ToggleButtons(
            isSelected: [
              isDrawingMode && !isErasing,
              !isDrawingMode,
              isDrawingMode && isErasing
            ],
            onPressed: (int index) {
              setState(() {
                currentLine = null; // Clear current line when switching modes
                if (index == 0) {
                  isDrawingMode = true;
                  isErasing = false;
                } else if (index == 1) {
                  isDrawingMode = false;
                  isErasing = false;
                } else if (index == 2) {
                  isDrawingMode = true;
                  isErasing = true;
                }
              });
            },
            children: [
              Tooltip(
                message: 'Pen Tool',
                child: Icon(Icons.edit),
              ),
              Tooltip(
                message: 'Pan/Zoom Tool',
                child: Icon(Icons.pan_tool),
              ),
              Tooltip(
                message: 'Eraser Tool',
                child: Icon(Icons.auto_fix_high),
              ),
            ],
          ),
          IconButton(
            icon: Icon(Icons.save),
            onPressed: _exportToPdf,
            tooltip: 'Export to PDF',
          ),
          IconButton(
            icon: Icon(Icons.folder),
            onPressed: pickAndLoadPDF,
          ),
        ],
      ),
      body: pdfImage == null
          ? Center(child: Text('Please select a PDF file'))
          : Center(
              child: ClipRect(
                child: Container(
                  width: containerWidth,
                  height: containerHeight,
                  decoration: BoxDecoration(
                    color: Colors.white,
                    border: Border.all(color: Colors.grey),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.grey.withOpacity(0.5),
                        spreadRadius: 2,
                        blurRadius: 5,
                        offset: Offset(0, 3),
                      ),
                    ],
                  ),
                  child: Stack(
                    children: [
                      GestureDetector(
                        onScaleStart: (details) {
                          if (!_isPointInCanvas(details.localFocalPoint)) {
                            currentLine = null;
                            return;
                          }

                          setState(() {
                            isDrawingActive = true;
                            if (!isDrawingMode) {
                              previousZoom = zoom;
                              previousOffset = offset;
                              currentLine = null;
                            } else {
                              final normalizedPoint =
                                  _getNormalizedPoint(details.localFocalPoint);
                              currentLine = DrawingLine(
                                points: [normalizedPoint],
                                color: isErasing ? Colors.white : Colors.black,
                                strokeWidth:
                                    isErasing ? eraserWidth : strokeWidth,
                                isEraser: isErasing,
                              );
                            }
                          });
                        },
                        onScaleUpdate: (details) {
                          if (!_isPointInCanvas(details.localFocalPoint)) {
                            setState(() {
                              if (isErasing) currentLine = null;
                            });
                            return;
                          }

                          setState(() {
                            if (!isDrawingMode) {
                              // Calculate new zoom
                              final newZoom = (previousZoom * details.scale)
                                  .clamp(0.5, 5.0);

                              if (details.scale == 1.0) {
                                // Enhanced pan operation with higher speed and direct delta application
                                final panSpeed =
                                    3.0; // Increased from 2.0 to 3.0
                                final rawOffset = previousOffset +
                                    (details.focalPointDelta * panSpeed);

                                // Update the offset immediately without waiting for previous animation
                                offset = _constrainOffset(rawOffset, zoom);

                                // Update previousOffset to current position to prevent jump on next update
                                previousOffset = offset;
                              } else {
                                // Zoom operation
                                final focalPoint = details.localFocalPoint;
                                final oldScale = zoom;
                                final newScale = newZoom;

                                // Calculate new offset with enhanced focal point maintenance
                                final newOffset = focalPoint -
                                    (focalPoint - previousOffset) *
                                        (newScale / oldScale);

                                offset = _constrainOffset(newOffset, newScale);
                                zoom = newScale;
                              }
                            } else if (currentLine != null) {
                              final normalizedPoint =
                                  _getNormalizedPoint(details.localFocalPoint);
                              currentLine!.points.add(normalizedPoint);

                              if (isErasing) {
                                _handleErasure(normalizedPoint);
                              }
                            }
                          });
                        },
                        onScaleEnd: (details) {
                          setState(() {
                            isDrawingActive = false;
                            if (isDrawingMode &&
                                currentLine != null &&
                                !isErasing) {
                              lines.add(currentLine!);
                            }
                            currentLine = null;
                          });
                        },
                        child: CustomPaint(
                          key: canvasKey,
                          painter: DrawingPainter(
                            pdfImage: pdfImage!,
                            lines: lines,
                            currentLine: currentLine,
                            zoom: zoom,
                            offset: offset,
                            eraserRadius: isErasing && isDrawingActive
                                ? eraserWidth / 2
                                : 0,
                            canvasSize: Size(canvasWidth, canvasHeight),
                          ),
                          size: Size(canvasWidth, canvasHeight),
                        ),
                      ),
                      if (isErasing)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 20,
                          child: Slider(
                            value: eraserWidth,
                            min: 10,
                            max: 50,
                            onChanged: (value) {
                              setState(() {
                                eraserWidth = value;
                              });
                            },
                            label: 'Eraser Size',
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          setState(() {
            lines.clear();
            currentLine = null;
          });
        },
        child: Icon(Icons.clear),
        tooltip: 'Clear Canvas',
      ),
    );
  }

  @override
  void didUpdateWidget(ZoomableDrawingCanvas oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (currentLine?.isEraser != isErasing) {
      setState(() {
        currentLine = null;
      });
    }
  }

  bool _isPointInCanvas(Offset point) {
    return point.dx >= 0 &&
        point.dx <= canvasWidth &&
        point.dy >= 0 &&
        point.dy <= canvasHeight;
  }

  Offset _constrainOffset(Offset newOffset, double currentZoom) {
    final double maxDx = canvasWidth * (currentZoom - 1);
    final double maxDy = canvasHeight * (currentZoom - 1);

    return Offset(
      newOffset.dx.clamp(-maxDx, maxDx),
      newOffset.dy.clamp(-maxDy, maxDy),
    );
  }

  Offset _getNormalizedPoint(Offset screenPoint) {
    return (screenPoint - offset) / zoom;
  }

  void _handleErasure(Offset eraserPoint) {
    final eraseRadius = eraserWidth / 2;
    List<DrawingLine> newLines = [];

    for (var line in lines) {
      List<List<Offset>> segments = [[]];

      for (int i = 0; i < line.points.length; i++) {
        var point = line.points[i];
        bool pointIsErased = false;

        // Check if current point is within eraser radius
        if ((point - eraserPoint).distance <= eraseRadius) {
          pointIsErased = true;
        } else if (i > 0) {
          // Check if line segment intersects with eraser circle
          var prevPoint = line.points[i - 1];
          pointIsErased =
              _lineIntersectsCircle(prevPoint, point, eraserPoint, eraseRadius);
        }

        if (!pointIsErased) {
          segments.last.add(point);
        } else if (segments.last.isNotEmpty) {
          // Start new segment if current point is erased
          segments.add([]);
        }
      }

      // Add valid segments to new lines
      for (var segment in segments) {
        if (segment.length >= 2) {
          newLines.add(DrawingLine(
            points: segment,
            color: line.color,
            strokeWidth: line.strokeWidth,
          ));
        }
      }
    }

    setState(() {
      lines = newLines;
    });
  }

  // Helper method to check if a line segment intersects with a circle
  bool _lineIntersectsCircle(
      Offset lineStart, Offset lineEnd, Offset circleCenter, double radius) {
    // Vector from line start to circle center
    final ac = circleCenter - lineStart;
    // Vector from line start to line end
    final ab = lineEnd - lineStart;

    // Length of line segment
    final abLength = ab.distance;

    // Unit vector of AB
    final abUnit = Offset(ab.dx / abLength, ab.dy / abLength);

    // Project AC onto AB to find the closest point
    final projection = ac.dx * abUnit.dx + ac.dy * abUnit.dy;

    // Closest point on line segment
    Offset closest;
    if (projection <= 0) {
      closest = lineStart;
    } else if (projection >= abLength) {
      closest = lineEnd;
    } else {
      closest = lineStart + (abUnit * projection);
    }

    // Check if closest point is within radius
    return (closest - circleCenter).distance <= radius;
  } // Helper function to convert ui.Image to PdfImage

  Future<pw.ImageProvider> pdfImageFromUiImage(ui.Image image) async {
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    return pw.MemoryImage(bytes!.buffer.asUint8List());
  }

  Future<void> _exportToPdf() async {
    if (pdfPageSize == null) return;

    try {
      final pdf = pw.Document();
      final pdfImage2 = await pdfImageFromUiImage(pdfImage!);

      pdf.addPage(
        pw.Page(
          build: (pw.Context context) {
            return pw.Stack(
              children: [
                pw.Image(pdfImage2, fit: pw.BoxFit.contain),
                pw.Transform(
                  transform: Matrix4.identity()
                    ..translate(0.0, pdfPageSize!.height)
                    ..scale(1.0, -1.0),
                  child: pw.CustomPaint(
                    painter: (canvas, size) {
                      for (var line in lines) {
                        if (line.points.length >= 2) {
                          for (int i = 0; i < line.points.length - 1; i++) {
                            final start = line.points[i];
                            final end = line.points[i + 1];

                            canvas
                              ..setStrokeColor(
                                  PdfColor.fromInt(line.color.value))
                              ..setLineWidth(line.strokeWidth)
                              ..moveTo(start.dx, start.dy)
                              ..lineTo(end.dx, end.dy)
                              ..strokePath();
                          }
                        }
                      }
                    },
                    size: PdfPoint(pdfPageSize!.width, pdfPageSize!.height),
                  ),
                ),
              ],
            );
          },
          pageFormat: PdfPageFormat(pdfPageSize!.width, pdfPageSize!.height,
              marginAll: 0),
        ),
      );
      final dir = await getApplicationDocumentsDirectory();
      final String filePath =
          '${dir.path}/drawing_${DateTime.now().millisecondsSinceEpoch}.pdf';

      final file = File(filePath);
      await file.writeAsBytes(await pdf.save());

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('PDF saved successfully'),
          duration: Duration(seconds: 2),
        ),
      );

      await OpenFile.open(filePath);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Error saving PDF: ${e.toString()}'),
          duration: Duration(seconds: 3),
          backgroundColor: Colors.red,
        ),
      );
    }
  }
}

class DrawingPainter extends CustomPainter {
  final List<DrawingLine> lines;
  final DrawingLine? currentLine;
  final double zoom;
  final Offset offset;
  final double eraserRadius;
  final Size canvasSize;
  final ui.Image pdfImage;

  DrawingPainter({
    required this.lines,
    this.currentLine,
    required this.zoom,
    required this.offset,
    required this.canvasSize,
    required this.pdfImage,
    this.eraserRadius = 0,
  });

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
      Offset.zero & size,
      Paint()..color = Colors.white,
    );

    canvas.save();
    canvas.translate(offset.dx, offset.dy);
    canvas.scale(zoom);

    // Draw PDF image at original size
    canvas.drawImage(pdfImage, Offset.zero, Paint());

    // Clip to PDF bounds
    canvas.clipRect(Offset.zero & size);

    // // Fill background with white instead of red
    // canvas.drawRect(
    //   Offset.zero & canvasSize,
    //   Paint()..color = Colors.white,
    // );

    // // Optimize transform operations
    // canvas.save();
    // canvas.translate(offset.dx, offset.dy);
    // canvas.scale(zoom);
    // canvas.drawImage(pdfImage, Offset.zero, Paint());

    // // Optimize clipping
    // final clipRect = Offset.zero & canvasSize;
    // canvas.clipRect(clipRect);

    // Batch similar lines together to reduce state changes
    final regularPaint = Paint()
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    for (var line in lines) {
      if (line.points.length >= 2) {
        regularPaint
          ..color = line.color
          ..strokeWidth = line.strokeWidth;

        final path = Path();
        path.moveTo(line.points.first.dx, line.points.first.dy);
        for (var point in line.points.skip(1)) {
          path.lineTo(point.dx, point.dy);
        }
        canvas.drawPath(path, regularPaint);
      }
    }

    // Draw current line if exists
    if (currentLine != null && currentLine!.points.length >= 2) {
      regularPaint
        ..color = currentLine!.color
        ..strokeWidth = currentLine!.strokeWidth;

      final path = Path();
      path.moveTo(currentLine!.points.first.dx, currentLine!.points.first.dy);
      for (var point in currentLine!.points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, regularPaint);
    }

    // Draw eraser preview if needed
    if (currentLine?.isEraser == true &&
        eraserRadius > 0 &&
        currentLine!.points.isNotEmpty) {
      final eraserPaint = Paint()
        ..color = Colors.red.withOpacity(0.3)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.0;

      canvas.drawCircle(
        currentLine!.points.last,
        eraserRadius / zoom,
        eraserPaint,
      );
    }

    canvas.restore();
  }

  void _drawLine(Canvas canvas, DrawingLine line) {
    if (line.points.isEmpty) return;

    final paint = Paint()
      ..color = line.color
      ..strokeWidth = line.strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    final path = Path();
    path.moveTo(line.points.first.dx, line.points.first.dy);
    for (var point in line.points.skip(1)) {
      path.lineTo(point.dx, point.dy);
    }

    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(DrawingPainter oldDelegate) => true;
}
