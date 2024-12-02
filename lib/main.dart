import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf_render/pdf_render.dart' as pr;
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;
import 'dart:isolate';
import 'dart:math' as math;
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:flutter/services.dart';

enum Mode {
  draw,
  pan,
  highlight,
  text,
}

void main() {
  runApp(
    const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PdfViewerPage(),
    ),
  );
}

class DrawingPoint {
  final Offset point;
  final Paint paint;
  final double baseStrokeWidth; // Add this field

  DrawingPoint(this.point, this.paint, this.baseStrokeWidth);
}

class DrawingPath {
  final List<DrawingPoint> points;
  final Paint paint;
  final double baseStrokeWidth; // Add this field

  DrawingPath(this.points, this.paint, this.baseStrokeWidth);

  // Update createSmoothPath to use scaled stroke width
  Path createSmoothPath(double currentZoom) {
    if (points.isEmpty) return Path();

    // Scale the stroke width based on current zoom
    paint.strokeWidth = baseStrokeWidth * currentZoom;

    if (points.length < 2) {
      return Path()
        ..addOval(Rect.fromCircle(
            center: points[0].point, radius: paint.strokeWidth / 2));
    }

    Path path = Path();
    path.moveTo(points[0].point.dx, points[0].point.dy);

    if (points.length == 2) {
      path.lineTo(points[1].point.dx, points[1].point.dy);
    } else {
      // Rest of the existing Catmull-Rom spline code remains the same
      for (int i = 0; i < points.length - 1; i++) {
        final p0 = i > 0 ? points[i - 1].point : points[i].point;
        final p1 = points[i].point;
        final p2 = points[i + 1].point;
        final p3 = i + 2 < points.length ? points[i + 2].point : p2;

        final controlPoint1 = Offset(
          p1.dx + (p2.dx - p0.dx) / 6,
          p1.dy + (p2.dy - p0.dy) / 6,
        );

        final controlPoint2 = Offset(
          p2.dx - (p3.dx - p1.dx) / 6,
          p2.dy - (p3.dy - p1.dy) / 6,
        );

        path.cubicTo(
          controlPoint1.dx,
          controlPoint1.dy,
          controlPoint2.dx,
          controlPoint2.dy,
          p2.dx,
          p2.dy,
        );
      }
    }
    return path;
  }
}

class PdfViewerPage extends StatefulWidget {
  const PdfViewerPage({Key? key}) : super(key: key);

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  Map<int, List<DrawingPath>> pageDrawings = {};
  List<DrawingPoint> currentPath = [];

  // Helper methods to manage page-specific drawings
  List<DrawingPath> get currentPagePaths => pageDrawings[currentPage] ?? [];

  void addPathToCurrentPage(DrawingPath path) {
    if (!pageDrawings.containsKey(currentPage)) {
      pageDrawings[currentPage] = [];
    }
    pageDrawings[currentPage]!.add(path);
  }

  List<DrawingPath> paths = [];

  Color currentColor = Colors.red;
  Color currentColorHighlight = Colors.yellow.withAlpha(50);
  double currentStrokePen = 4.0;
  double currentStrokeHighlight = 10.0;

  Offset _getTransformedOffset(Offset screenOffset) {
    // Remove the translation and scale to get the actual point in document space
    return (screenOffset - offset) / zoom;
  }

  pr.PdfDocument? document;
  String? currentFilePath;

  bool isExporting = false;

  bool isLoading = false;
  int currentPage = 0;
  int totalPages = 0;

  ui.Image? currentPageImage;
  bool isPageLoading = false;
  double quality = 3.0; // Reduced quality for better memory management
  // String mode = 'draw';
  Mode mode = Mode.pan;
  @override
  void dispose() {
    document?.dispose();
    super.dispose();
  }

  double _getAdjustedStrokeWidth(double baseWidth) {
    return baseWidth / zoom;
  }

  double zoom = 1.0;
  double previousZoom = 1.0;
  Offset offset = Offset.zero;
  Offset previousOffset = Offset.zero;
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white60,
      appBar: // First, add this widget below the existing action buttons in the AppBar:
          AppBar(
        actions: [
          IconButton(
            icon: const Icon(Icons.file_open),
            onPressed: _pickAndLoadPdf,
          ),
          IconButton(
            color: mode == Mode.pan ? Colors.red : Colors.black,
            icon: const Icon(Icons.back_hand_outlined),
            onPressed: () {
              setState(() {
                mode = Mode.pan;
              });
            },
          ),
          IconButton(
            color: mode == Mode.draw ? Colors.red : Colors.black,
            icon: const Icon(Icons.brush),
            onPressed: () {
              setState(() {
                mode = Mode.draw;
              });
            },
          ),
          IconButton(
            color: mode == Mode.highlight ? Colors.red : Colors.black,
            icon: const Icon(Icons.highlight),
            onPressed: () {
              setState(() {
                mode = Mode.highlight;
              });
            },
          ),
          // Add stroke width control
          if (mode == Mode.draw)
            SizedBox(
              width: 150,
              child: Row(
                children: [
                  const Icon(Icons.line_weight, size: 20),
                  Expanded(
                    child: Slider(
                      value: currentStrokePen,
                      min: 1.0,
                      max: 10.0,
                      divisions: 9,
                      label: currentStrokePen.round().toString(),
                      onChanged: (value) {
                        setState(() {
                          currentStrokePen = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          // Add highlight width control
          if (mode == Mode.highlight)
            SizedBox(
              width: 150,
              child: Row(
                children: [
                  const Icon(Icons.line_weight, size: 20),
                  Expanded(
                    child: Slider(
                      value: currentStrokeHighlight,
                      min: 5.0,
                      max: 30.0,
                      divisions: 5,
                      label: currentStrokeHighlight.round().toString(),
                      onChanged: (value) {
                        setState(() {
                          currentStrokeHighlight = value;
                        });
                      },
                    ),
                  ),
                ],
              ),
            ),
          if (!isExporting)
            IconButton(
              icon: const Icon(Icons.save),
              onPressed: document != null ? _exportPdf : null,
            )
          else
            const SizedBox(
              width: 48,
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                  ),
                ),
              ),
            ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: clearCurrentPageDrawings,
        child: Icon(Icons.clear),
        tooltip: 'Clear Current Page',
      ),
      body: Column(
        children: [
          Expanded(
            child: isLoading
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CircularProgressIndicator(),
                        SizedBox(height: 16),
                        Text('Loading PDF...'),
                      ],
                    ),
                  )
                : document == null
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.picture_as_pdf, size: 64),
                            const SizedBox(height: 16),
                            ElevatedButton(
                              onPressed: _pickAndLoadPdf,
                              child: const Text('Open PDF'),
                            ),
                          ],
                        ),
                      )
                    : Stack(
                        children: [
                          Center(
                            child: currentPageImage == null
                                ? const CircularProgressIndicator()
                                : GestureDetector(
                                    onScaleStart: (details) {
                                      if (mode == Mode.draw ||
                                          mode == Mode.highlight) {
                                        final transformedOffset =
                                            _getTransformedOffset(
                                                details.localFocalPoint);
                                        final baseStrokeWidth =
                                            mode == Mode.highlight
                                                ? currentStrokeHighlight
                                                : currentStrokePen;
                                        setState(() {
                                          currentPath = [
                                            DrawingPoint(
                                              transformedOffset,
                                              Paint()
                                                ..color = mode == Mode.highlight
                                                    ? currentColorHighlight
                                                    : currentColor
                                                ..strokeWidth = baseStrokeWidth *
                                                    zoom // Initial scaled width
                                                ..strokeCap = StrokeCap.round
                                                ..strokeJoin = StrokeJoin.round
                                                ..style = PaintingStyle.stroke
                                                ..isAntiAlias = true,
                                              baseStrokeWidth, // Store the base width
                                            )
                                          ];
                                        });
                                      } else {
                                        previousZoom = zoom;
                                        previousOffset = offset;
                                      }
                                    },
                                    onScaleUpdate: (details) {
                                      if ((mode == Mode.draw ||
                                              mode == Mode.highlight) &&
                                          details.scale == 1.0) {
                                        final transformedOffset =
                                            _getTransformedOffset(
                                                details.localFocalPoint);
                                        if (currentPath.isEmpty ||
                                            (currentPath.last.point -
                                                        transformedOffset)
                                                    .distance >
                                                1.0 / zoom) {
                                          final baseStrokeWidth =
                                              mode == Mode.highlight
                                                  ? currentStrokeHighlight
                                                  : currentStrokePen;
                                          currentPath.add(
                                            DrawingPoint(
                                              transformedOffset,
                                              Paint()
                                                ..color = mode == Mode.highlight
                                                    ? currentColorHighlight
                                                    : currentColor
                                                ..strokeWidth =
                                                    baseStrokeWidth * zoom
                                                ..strokeCap = StrokeCap.round
                                                ..strokeJoin = StrokeJoin.round
                                                ..style = PaintingStyle.stroke
                                                ..isAntiAlias = true,
                                              baseStrokeWidth,
                                            ),
                                          );
                                          setState(() {});
                                        }
                                      } else {
                                        setState(() {
                                          // Handle zooming and panning in a single setState
                                          if (details.scale != 1.0) {
                                            // Changed the clamp range to allow higher zoom levels
                                            final newZoom =
                                                (previousZoom * details.scale)
                                                    .clamp(0.2 / quality, 5.0);
                                            final focalPoint =
                                                details.localFocalPoint;
                                            final double zoomFactor =
                                                newZoom / zoom;
                                            final Offset normalizedOffset =
                                                offset - focalPoint;
                                            final Offset scaledOffset =
                                                normalizedOffset * zoomFactor;
                                            final Offset offsetDelta =
                                                scaledOffset - normalizedOffset;
                                            zoom = newZoom;
                                            offset = _constrainOffset(
                                                offset + offsetDelta, newZoom);
                                          } else {
                                            offset = _constrainOffset(
                                                offset +
                                                    details.focalPointDelta,
                                                zoom);
                                          }
                                        });
                                      }
                                    },
                                    onScaleEnd: (details) {
                                      if ((mode == Mode.draw ||
                                              mode == Mode.highlight) &&
                                          currentPath.isNotEmpty) {
                                        setState(() {
                                          addPathToCurrentPage(DrawingPath(
                                            List.from(currentPath),
                                            currentPath.first.paint,
                                            currentPath.first.baseStrokeWidth,
                                          ));
                                          currentPath = [];
                                        });
                                      } else {
                                        previousZoom = zoom;
                                        previousOffset = offset;
                                      }
                                    },
                                    child: CustomPaint(
                                      painter: PdfPainter(
                                        currentPageImage!,
                                        zoom,
                                        offset,
                                        currentPagePaths,
                                        currentPath,
                                      ),
                                      size: Size(
                                        currentPageImage!.width.toDouble(),
                                        currentPageImage!.height.toDouble(),
                                      ),
                                    ),
                                  ),
                          ),
                          if (isPageLoading)
                            const Positioned.fill(
                              child: Center(
                                child: CircularProgressIndicator(),
                              ),
                            ),
                        ],
                      ),
          ),
          if (document != null)
            Container(
              padding: const EdgeInsets.all(16),
              color: Theme.of(context).colorScheme.surface,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  IconButton(
                    icon: const Icon(Icons.first_page),
                    onPressed: currentPage > 0 ? () => _loadPage(0) : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.navigate_before),
                    onPressed: currentPage > 0
                        ? () => _loadPage(currentPage - 1)
                        : null,
                  ),
                  const SizedBox(width: 16),
                  Text(
                    'Page ${currentPage + 1} of $totalPages',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(width: 16),
                  IconButton(
                    icon: const Icon(Icons.navigate_next),
                    onPressed: currentPage < totalPages - 1
                        ? () => _loadPage(currentPage + 1)
                        : null,
                  ),
                  IconButton(
                    icon: const Icon(Icons.last_page),
                    onPressed: currentPage < totalPages - 1
                        ? () => _loadPage(totalPages - 1)
                        : null,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  double _calculateInitialZoom(BuildContext context, Size imageSize) {
    if (currentPageImage == null) return 1.0;

    final screenSize = MediaQuery.of(context).size;
    final containerSize = Size(
      screenSize.width,
      screenSize.height - kToolbarHeight - 80,
    );

    final double horizontalRatio = containerSize.width / imageSize.width;
    final double verticalRatio = containerSize.height / imageSize.height;

    // Changed to allow the initial zoom to be larger than 1.0 if needed
    return math.min(horizontalRatio, verticalRatio) / quality;
  }

  Offset _constrainOffset(Offset offset, double zoom) {
    if (currentPageImage == null) return Offset.zero;

    final Size imageSize = Size(
      currentPageImage!.width.toDouble(),
      currentPageImage!.height.toDouble(),
    );

    final Size viewSize = Size(
      MediaQuery.of(context).size.width,
      MediaQuery.of(context).size.height - kToolbarHeight - 80,
    );

    final Size scaledSize = Size(
      imageSize.width * zoom,
      imageSize.height * zoom,
    );

    final double maxX = 0.0;
    final double maxY = 0.0;
    final double minX = math.min(0.0, viewSize.width - scaledSize.width);
    final double minY = math.min(0.0, viewSize.height - scaledSize.height);

    return Offset(
      offset.dx.clamp(minX, maxX),
      offset.dy.clamp(minY, maxY),
    );
  }

  Future<void> _exportPdf() async {
    if (currentFilePath == null || document == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No PDF file loaded to export')),
      );
      return;
    }

    try {
      setState(() {
        isExporting = true;
      });

      // Pre-render all pages
      List<Uint8List> pageImages = [];
      double? originalWidth;

      // Get the original width from the first page
      final firstPage = await document!.getPage(1);
      originalWidth = firstPage.width;

      // Render each page
      for (int i = 0; i < document!.pageCount; i++) {
        final page = await document!.getPage(i + 1);

        final pageImage = await page.render(
          width: (page.width * quality).toInt(),
          height: (page.height * quality).toInt(),
        );

        final img = await pageImage.createImageDetached();
        final byteData = await img.toByteData(format: ui.ImageByteFormat.png);

        if (byteData != null) {
          pageImages.add(byteData.buffer.asUint8List());
        }

        img.dispose();
        pageImage.dispose();
      }

      // Prepare the export path
      final tempDir = await getTemporaryDirectory();
      final originalFileName = path.basename(currentFilePath!);
      final timestamp = DateTime.now().millisecondsSinceEpoch.toString();
      final newFileName = 'annotated_${timestamp}_$originalFileName';
      final newPath = path.join(tempDir.path, newFileName);

      // Create export data
      final exportData = PdfExportData(
        pageImages: pageImages,
        pageDrawings: pageDrawings,
        outputPath: newPath,
        pageWidth: firstPage.width,
        pageHeight: firstPage.height,
        originalWidth: originalWidth,
        pageCount: document!.pageCount,
      );

      // Get root isolate token
      final rootIsolateToken = RootIsolateToken.instance!;

      // Create and run isolate
      final receivePort = ReceivePort();
      final isolate = await Isolate.spawn(
        exportPdfIsolate,
        [rootIsolateToken, receivePort.sendPort, exportData],
      );

      // Wait for result
      final result = await receivePort.first;

      // Clean up isolate
      isolate.kill();
      receivePort.close();

      if (result == 'success') {
        await OpenFile.open(newPath);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('PDF exported successfully')),
          );
        }
      } else
      // if (result.startsWith('error:'))
      {
        log(result);
        // throw Exception(result.substring(7));
      }
    } catch (e, stackTrace) {
      debugPrint('Export error: $e');
      log('Stack trace: $stackTrace');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error exporting PDF: $e')),
        );
      }
    } finally {
      setState(() {
        isExporting = false;
      });
    }
  }

  Future<void> _copyFileInIsolate(ExportData data) async {
    final bytes = await File(data.sourcePath).readAsBytes();
    await File(data.destinationPath).writeAsBytes(bytes, flush: true);
  }

  void isolateFunction(IsolateMessage message) async {
    try {
      final bytes = await File(message.sourcePath).readAsBytes();
      await File(message.destinationPath).writeAsBytes(bytes, flush: true);
      message.sendPort.send('success');
    } catch (e) {
      message.sendPort.send('error: $e');
    }
  }

  // Optional: Add a method to handle large file exports with progress
  Future<void> _copyFileWithProgress(String sourcePath, String destinationPath,
      Function(double) onProgress) async {
    final input = File(sourcePath).openRead();
    final output = File(destinationPath).openWrite();

    final sourceFile = File(sourcePath);
    final totalSize = await sourceFile.length();
    var bytesWritten = 0;

    await for (final chunk in input) {
      output.add(chunk);
      bytesWritten += chunk.length;
      final progress = bytesWritten / totalSize;
      onProgress(progress);
    }

    await output.close();
  }

  Future<void> _pickAndLoadPdf() async {
    try {
      setState(() {
        isLoading = true;
        currentPage = 0;
        currentPageImage = null;
      });

      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
      );

      if (result != null && result.files.single.path != null) {
        document?.dispose();
        final file = File(result.files.single.path!);
        currentFilePath = file.path; // Store the file path
        document = await pr.PdfDocument.openFile(file.path);
        totalPages = document!.pageCount;
        await _loadPage(0);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error loading PDF: $e')),
        );
      }
    } finally {
      setState(() => isLoading = false);
    }
  }

  Future<void> _loadPage(int pageNumber) async {
    if (document == null || isPageLoading) return;

    try {
      setState(() {
        isPageLoading = true;
      });

      currentPageImage?.dispose();
      currentPageImage = null;

      final page = await document!.getPage(pageNumber + 1);
      final image = await _renderPage(page);

      if (mounted && image != null) {
        setState(() {
          currentPageImage = image;
          currentPage = pageNumber;
          // Reset zoom and offset when loading a new page
          final imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );
          zoom = _calculateInitialZoom(context, imageSize);
          previousZoom = zoom;
          offset = Offset.zero;
          previousOffset = Offset.zero;
          currentPath = []; // Clear current path when changing pages
        });
      }
    } catch (e) {
      debugPrint('Error loading page: $e');
    } finally {
      setState(() {
        isPageLoading = false;
      });
    }
  }

  void clearCurrentPageDrawings() {
    setState(() {
      pageDrawings.remove(currentPage);
      currentPath = [];
    });
  }

  Future<ui.Image?> _renderPage(pr.PdfPage page) async {
    try {
      final width = (page.width * quality).toInt();
      final height = (page.height * quality).toInt();

      final pageImage = await page.render(
        width: width,
        height: height,
      );

      if (pageImage != null) {
        return pageImage.createImageDetached();
      }
    } catch (e) {
      debugPrint('Error rendering page: $e');
    }
    return null;
  }
}

class PdfPainter extends CustomPainter {
  final ui.Image image;
  final double zoom;
  final Offset offset;
  final List<DrawingPath> paths;
  final List<DrawingPoint> currentPath;

  PdfPainter(this.image, this.zoom, this.offset, this.paths, this.currentPath);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.save();

    canvas.translate(offset.dx, offset.dy);
    canvas.scale(zoom);

    // Draw PDF
    paintImage(
      canvas: canvas,
      rect: Offset.zero & Size(image.width.toDouble(), image.height.toDouble()),
      image: image,
      filterQuality: FilterQuality.high,
    );

    // Enable anti-aliasing for smoother lines
    canvas.saveLayer(null, Paint()..isAntiAlias = true);

    // Draw completed paths with scaled stroke width
    for (final path in paths) {
      canvas.drawPath(
        path.createSmoothPath(zoom),
        path.paint..isAntiAlias = true,
      );
    }

    // Draw current path with scaled stroke width
    if (currentPath.isNotEmpty) {
      final currentDrawingPath = DrawingPath(
        currentPath,
        currentPath.first.paint,
        currentPath.first.baseStrokeWidth,
      );
      canvas.drawPath(
        currentDrawingPath.createSmoothPath(zoom),
        currentPath.first.paint..isAntiAlias = true,
      );
    }

    canvas.restore();
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PdfPainter oldDelegate) => true;
}

class ExportData {
  final String sourcePath;
  final String destinationPath;

  ExportData(this.sourcePath, this.destinationPath);
}

Future<void> _copyFileInIsolate(ExportData data) async {
  final bytes = await File(data.sourcePath).readAsBytes();
  await File(data.destinationPath).writeAsBytes(bytes, flush: true);
}

// Top-level isolate function
@pragma('vm:entry-point')
void copyFileIsolate(IsolateMessage message) async {
  try {
    final bytes = await File(message.sourcePath).readAsBytes();
    await File(message.destinationPath).writeAsBytes(bytes, flush: true);
    message.sendPort.send('success');
  } catch (e) {
    message.sendPort.send('error: $e');
  }
}

class IsolateMessage {
  final String sourcePath;
  final String destinationPath;
  final SendPort sendPort;

  IsolateMessage(this.sourcePath, this.destinationPath, this.sendPort);
}

class PdfExportData {
  final List<Uint8List> pageImages;
  final Map<int, List<DrawingPath>> pageDrawings;
  final String outputPath;
  final double pageWidth;
  final double pageHeight;
  final double originalWidth;
  final int pageCount;

  PdfExportData({
    required this.pageImages,
    required this.pageDrawings,
    required this.outputPath,
    required this.pageWidth,
    required this.pageHeight,
    required this.originalWidth,
    required this.pageCount,
  });
}

@pragma('vm:entry-point')
void exportPdfIsolate(List<dynamic> args) async {
  final RootIsolateToken rootIsolateToken = args[0];
  final SendPort sendPort = args[1];
  final PdfExportData data = args[2];

  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

  try {
    final pdf = pw.Document();

    // Calculate scale factors
    final renderScale = 3.0; // This should match your 'quality' variable
    final pdfScale = data.pageWidth / data.originalWidth;

    // Combined scale for position coordinates
    final combinedScale = pdfScale / renderScale;

    // Separate scale for stroke width (reduced by a factor to match screen appearance)
    final strokeScale = combinedScale * 0.5; // Adjust this factor if needed

    for (int i = 0; i < data.pageCount; i++) {
      final pageDrawings = data.pageDrawings[i] ?? [];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(data.pageWidth, data.pageHeight),
          build: (context) {
            return pw.Stack(
              children: [
                // Base PDF page image
                pw.Positioned.fill(
                  child: pw.Image(
                    pw.MemoryImage(data.pageImages[i]),
                    fit: pw.BoxFit.fill,
                  ),
                ),
                // Annotations layer
                if (pageDrawings.isNotEmpty)
                  pw.Positioned.fill(
                    child: pw.CustomPaint(
                      painter: (PdfGraphics canvas, PdfPoint size) {
                        for (var drawing in pageDrawings) {
                          if (drawing.points.isEmpty) continue;

                          // Convert color to PDF format with opacity
                          final color = drawing.paint.color;
                          final r = color.red / 255;
                          final g = color.green / 255;
                          final b = color.blue / 255;
                          final a = color.alpha / 255;

                          final pdfColor = PdfColor(r, g, b);
                          canvas.setStrokeColor(pdfColor);
                          canvas.setGraphicState(PdfGraphicState(opacity: a));

                          // Apply the reduced stroke scale
                          final strokeWidth =
                              drawing.baseStrokeWidth * strokeScale;
                          canvas.setLineWidth(strokeWidth);
                          canvas.setLineCap(PdfLineCap.round);
                          canvas.setLineJoin(PdfLineJoin.round);

                          if (drawing.points.length < 2) {
                            // Handle single point as a small line
                            final point = drawing.points[0].point;
                            final scaledX = point.dx * combinedScale;
                            final scaledY =
                                data.pageHeight - (point.dy * combinedScale);
                            canvas
                              ..moveTo(scaledX, scaledY)
                              ..lineTo(scaledX + strokeWidth, scaledY)
                              ..strokePath();
                          } else {
                            // Draw smooth path for multiple points using Catmull-Rom splines
                            for (int j = 0;
                                j < drawing.points.length - 1;
                                j++) {
                              final p0 = j > 0
                                  ? drawing.points[j - 1].point
                                  : drawing.points[j].point;
                              final p1 = drawing.points[j].point;
                              final p2 = drawing.points[j + 1].point;
                              final p3 = j + 2 < drawing.points.length
                                  ? drawing.points[j + 2].point
                                  : p2;

                              if (j == 0) {
                                canvas.moveTo(p1.dx * combinedScale,
                                    data.pageHeight - (p1.dy * combinedScale));
                              }

                              // Calculate control points for cubic Bezier curve
                              final controlPoint1 = Offset(
                                p1.dx + (p2.dx - p0.dx) / 6,
                                p1.dy + (p2.dy - p0.dy) / 6,
                              );

                              final controlPoint2 = Offset(
                                p2.dx - (p3.dx - p1.dx) / 6,
                                p2.dy - (p3.dy - p1.dy) / 6,
                              );

                              // Draw cubic Bezier curve with correct position scaling
                              canvas.curveTo(
                                controlPoint1.dx * combinedScale,
                                data.pageHeight -
                                    (controlPoint1.dy * combinedScale),
                                controlPoint2.dx * combinedScale,
                                data.pageHeight -
                                    (controlPoint2.dy * combinedScale),
                                p2.dx * combinedScale,
                                data.pageHeight - (p2.dy * combinedScale),
                              );
                            }
                            canvas.strokePath();
                          }
                        }
                      },
                    ),
                  ),
              ],
            );
          },
        ),
      );
    }

    final outputFile = File(data.outputPath);
    await outputFile.writeAsBytes(await pdf.save());
    sendPort.send('success');
  } catch (e, st) {
    print('PDF Export Error: $e\n$st');
    sendPort.send('error: $e');
  }
}

// Helper function to validate coordinates
bool _isValidCoordinate(Offset point) {
  return !point.dx.isNaN &&
      !point.dx.isInfinite &&
      !point.dy.isNaN &&
      !point.dy.isInfinite &&
      point.dx.abs() < 14400 && // PDF coordinate limit
      point.dy.abs() < 14400; // PDF coordinate limit
}
