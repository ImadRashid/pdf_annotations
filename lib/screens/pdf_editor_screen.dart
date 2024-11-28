import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:ui';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:image/image.dart' as img;
import 'package:open_file/open_file.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:pdf_annotations/models/shape_annotation.dart';
import 'package:printing/printing.dart';
import 'package:screenshot/screenshot.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import 'package:zoom_widget/zoom_widget.dart';
import '../models/text_annotation.dart';
import '/models/drawn_line.dart';
import '/widgets/drawing_painter.dart';
import '/utils/pdf_utils.dart';
import 'package:file_picker/file_picker.dart';

enum Mode {
  highlight,
  draw,
  erase,
  text,
  pan,
  line,
  rectangle,
  circle,
  arrow,
}

class PdfEditorScreen extends StatefulWidget {
  @override
  _PdfEditorScreenState createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  Offset _lastPanOffset = Offset.zero;
  Offset _currentPanOffset = Offset.zero;
  Mode mode = Mode.pan;
  List<GlobalKey> _repaintBoundaryKeys = [];
  final PdfViewerController _pdfViewerController = PdfViewerController();
  String? _pdfPath;
  Map<int, List<DrawnLine>> pageLines = {}; // Annotations per page
  Map<int, List<DrawnLine>> pageHighlights = {};
  int currentPage = 0; // Track the current page
  int totalPages = 0; // Total pages in the PDF
  List<DrawnLine> lines = [];
  List<DrawnLine> highlights = [];
  Offset? currentPoint;
  Map<int, List<ShapeAnnotation>> pageShapes = {}; // Shapes per page
  List<ShapeAnnotation> shapes = []; // Current page's shapes
  ShapeAnnotation? currentShape; // Current shape being drawn

  double pointerSize = 3.0; // Default pointer size
  Color pointerColor = Colors.black; // Default pointer color
  bool showOptions = true;
  Map<int, List<TextAnnotation>> pageTexts = {}; // Text annotations per page
  List<TextAnnotation> texts = []; // Current page's text annotations
  ScreenshotController screenshotController = ScreenshotController();
  // Page dimensions and zoom factor
  Size? pageSize;
  double zoomLevel = 1.0;
  bool isZooming = false;
  TextEditingController _pageController = TextEditingController();
  Set<int> modifiedPages = {}; // Tracks the indices of modified pages
  Map<int, Uint8List> pageScreenshots =
      {}; // Store screenshots of modified pages

  @override
  void initState() {
    requestPermisions();
    super.initState();
    _repaintBoundaryKeys = List.generate(100, (index) => GlobalKey());
  }

  requestPermisions() async {
    final isGranted = await PdfUtils.requestStoragePermission();
    print("is granted $isGranted");
  }

  @override
  Widget build(BuildContext context) {
    log("current page ===> ${_pdfViewerController.pageNumber}");
    return Scaffold(
      appBar: AppBar(
        title: Text("Edit PDF ${zoomLevel}"),
        leading: IconButton(
          icon: Icon(Icons.close),
          onPressed: _closePDF,
        ),
        actions: [
          if (_pdfPath != null) ...[
            IconButton(
              icon: Icon(Icons.undo),
              onPressed: _undo,
            ),
            IconButton(
              icon: Icon(Icons.save),
              onPressed: _savePdf,
            ),
          ],
        ],
      ),
      body: _pdfPath == null
          ? Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Text("Open a PDF to start editing"),
                  TextButton(
                    onPressed: _pickPDF,
                    child: const Text("Open PDF"),
                  )
                ],
              ),
            )
          : Column(
              children: [
                Expanded(
                  child: Screenshot(
                    controller: screenshotController,
                    child: Stack(
                      children: [
                        SfPdfViewer.file(
                          File(_pdfPath!),
                          pageLayoutMode: PdfPageLayoutMode.single,
                          controller: _pdfViewerController,
                          canShowPaginationDialog: false,
                          canShowScrollHead: false,
                          onTap: (d) {
                            print("ontap");
                            // d.position.
                          },
                          onDocumentLoaded: (details) {
                            print("document loaded");
                            setState(() {
                              totalPages = details.document.pages.count;
                              currentPage = 1;
                              _pageController.text = 1.toString();
                            });

                            final PdfDocument pdfDocument = PdfDocument(
                              inputBytes: File(_pdfPath!).readAsBytesSync(),
                            );
                            final PdfPage firstPage = pdfDocument.pages[0];
                            setState(() {
                              pageSize = Size(
                                firstPage.size.width,
                                firstPage.size.height,
                              );
                              zoomLevel = _pdfViewerController.zoomLevel;
                            });
                            pdfDocument.dispose();
                          },
                          onPageChanged: (details) async {
                            // Switch to new page
                            currentPage = details.newPageNumber;
                            _pageController.text =
                                details.newPageNumber.toString();
                            print("new page number ${details.newPageNumber} ");

                            // Load new page annotations
                            lines = pageLines[currentPage] ?? [];
                            highlights = pageHighlights[currentPage] ?? [];
                            texts = pageTexts[currentPage] ?? [];
                            shapes = pageShapes[currentPage] ?? [];
                            pageShapes[currentPage] = shapes;

                            // Update page dimensions
                            final PdfDocument pdfDocument = PdfDocument(
                              inputBytes: File(_pdfPath!).readAsBytesSync(),
                            );
                            final PdfPage currentPageObj =
                                pdfDocument.pages[details.newPageNumber - 1];
                            setState(() {
                              pageSize = Size(
                                currentPageObj.size.width,
                                currentPageObj.size.height,
                              );
                              zoomLevel = _pdfViewerController.zoomLevel;
                            });
                            pdfDocument.dispose();
                          },
                        ),
                        IgnorePointer(
                          ignoring: mode == Mode.pan,
                          child: GestureDetector(
                            onScaleStart: (details) {
                              print("Scale start: ${details.pointerCount}");
                              // Check if this is a zoom or pan gesture
                              setState(() {
                                isZooming = details.pointerCount > 1;
                              });
                              if (!isZooming && mode == Mode.text) {
                                _selectTextAnnotation(details.localFocalPoint);
                              }

                              if (mode == Mode.pan) {
                                _lastPanOffset = details.localFocalPoint;
                              }

                              if (!isZooming && mode != Mode.pan) {
                                final startPoint = _getNormalizedOffset(
                                    details.localFocalPoint);
                                if (mode == Mode.text) {
                                  _addTextAnnotation(details.localFocalPoint);
                                } else if (mode == Mode.erase) {
                                  setState(() {
                                    _eraseLine(startPoint);
                                  });
                                } else if ([
                                  Mode.line,
                                  Mode.rectangle,
                                  Mode.circle,
                                  Mode.arrow
                                ].contains(mode)) {
                                  // Initialize a new shape
                                  setState(() {
                                    currentShape = ShapeAnnotation(
                                      start: startPoint,
                                      end: startPoint,
                                      shapeType: mode,
                                      color: pointerColor,
                                      strokeWidth: pointerSize / zoomLevel,
                                    );
                                  });
                                }
                              }
                            },
                            onTapDown: (details) {
                              if (mode == Mode.text) {
                                _selectTextAnnotation(details.localPosition);
                              }
                            },
                            onScaleUpdate: (details) {
                              _markPageAsModified();
                              if (mode == Mode.pan) {
                                setState(() {
                                  _currentPanOffset =
                                      _lastPanOffset - details.localFocalPoint;
                                });
                              }
                              if (isZooming) {
                                print("Zooming");
                                if ((details.scale - 1.0).abs() > 0.01) {
                                  // Threshold for significant changes
                                  setState(() {
                                    zoomLevel = (zoomLevel * details.scale)
                                        .clamp(1.0, 3.0);
                                    _pdfViewerController.zoomLevel = zoomLevel;
                                  });
                                }
                              } else if (mode != Mode.pan) {
                                if (mode == Mode.text) {
                                  setState(() {
                                    for (var text in texts) {
                                      if (text.isSelected) {
                                        // Move selected text annotation
                                        text.position +=
                                            details.focalPointDelta / zoomLevel;
                                      }
                                    }
                                  });
                                }
                                print("Single finger action");
                                final offset = _getNormalizedOffset(
                                    details.localFocalPoint);
                                setState(() {
                                  if (mode == Mode.erase) {
                                    _eraseLine(offset);
                                  } else if (mode == Mode.highlight) {
                                    if (highlights.isNotEmpty &&
                                        highlights.last.isDrawing) {
                                      highlights.last.points.add(offset);
                                    } else {
                                      final newHighlight = DrawnLine(
                                        [offset],
                                        Colors.yellow.withOpacity(0.3),
                                        15.0,
                                        isDrawing: true,
                                      );
                                      highlights.add(newHighlight);

                                      if (pageHighlights[currentPage] == null) {
                                        pageHighlights[currentPage] = [];
                                      }
                                      pageHighlights[currentPage]!
                                          .add(newHighlight);
                                    }
                                  } else if (mode == Mode.draw) {
                                    if (lines.isNotEmpty &&
                                        lines.last.isDrawing) {
                                      lines.last.points.add(offset);
                                    } else {
                                      final newLine = DrawnLine(
                                        [offset],
                                        pointerColor,
                                        pointerSize,
                                        isDrawing: true,
                                      );
                                      lines.add(newLine);

                                      if (pageLines[currentPage] == null) {
                                        pageLines[currentPage] = [];
                                      }
                                      pageLines[currentPage]!.add(newLine);
                                    }
                                  } else if ([
                                    Mode.line,
                                    Mode.rectangle,
                                    Mode.circle,
                                    Mode.arrow
                                  ].contains(mode)) {
                                    if (currentShape != null) {
                                      // Update the end point of the shape
                                      currentShape =
                                          currentShape!.copyWith(end: offset);
                                    }
                                  }
                                  currentPoint = offset;
                                });
                              }
                            },
                            onScaleEnd: (details) {
                              print("Scale end");
                              setState(() {
                                isZooming = false;
                              });
                              if (mode == Mode.pan) {
                                setState(() {
                                  _lastPanOffset = _currentPanOffset;
                                });
                              }

                              if (mode != Mode.pan) {
                                setState(() {
                                  if (mode == Mode.highlight &&
                                      highlights.isNotEmpty) {
                                    highlights.last.isDrawing = false;
                                  } else if (mode == Mode.draw &&
                                      lines.isNotEmpty) {
                                    lines.last.isDrawing = false;
                                  } else if ([
                                    Mode.line,
                                    Mode.rectangle,
                                    Mode.circle,
                                    Mode.arrow
                                  ].contains(mode)) {
                                    if (currentShape != null) {
                                      shapes.add(currentShape!);
                                      currentShape = null;
                                    }
                                  }
                                  currentPoint = null;
                                });
                              }
                            },
                            child: pageSize == null
                                ? SizedBox.shrink()
                                : Align(
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: pageSize!.width * zoomLevel,
                                      height: pageSize!.height * zoomLevel,
                                      child: CustomPaint(
                                        isComplex: true,
                                        painter: DrawingPainter(
                                          _getAbsoluteLines(lines),
                                          _getAbsoluteLines(highlights),
                                          _getAbsoluteTexts(texts),
                                          shapes: _getAbsoluteShapes(shapes),
                                          currentShape:
                                              _getAbsoluteShape(currentShape),
                                          panOffset: _currentPanOffset,
                                        ),
                                      ),
                                    ),
                                  ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                _buildToolbar(),
              ],
            ),
    );
  }

  List<ui.Image> _pdfImages = [];
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
        //   _drawings.add([]);
        pageCount++;
      }

      _pdfImages = images;
    } catch (e) {
      print('Error loading or rasterizing PDF: $e');
    }
  }

  Future<Uint8List?> _captureScreenshot() async {
    try {
      final Uint8List? screenshot =
          await screenshotController.capture(pixelRatio: 4);
      if (screenshot == null) {
        print("Screenshot capture failed");
        return null;
      }

      return _cropImage(screenshot);
    } catch (e) {
      print("Error capturing screenshot: $e");
      return null;
    }
  }

  _captureAndStoreScreenshot() async {
    if (modifiedPages.contains(currentPage)) {
      final Uint8List? screenshot = await _captureScreenshot();
      if (screenshot != null) {
        pageScreenshots[currentPage] = screenshot;
      }
    }
  }

  Uint8List _cropImage(Uint8List imageBytes) {
    final image = img.decodeImage(imageBytes);
    if (image == null) return imageBytes;

    final cropMarginLeft = 50;
    final cropMarginTop = 120;
    final cropMarginRight = 50;
    final cropMarginBottom = 100;

    final croppedWidth = image.width - cropMarginLeft - cropMarginRight;
    final croppedHeight = image.height - cropMarginTop - cropMarginBottom;

    final croppedImage = img.copyCrop(
      image,
      x: cropMarginLeft,
      y: cropMarginTop,
      width: croppedWidth,
      height: croppedHeight,
    );

    return Uint8List.fromList(img.encodePng(croppedImage));
  }

  Future<void> _savePdf() async {
    print("pathh = $_pdfPath");
    try {
      final originalPdfFile = File(_pdfPath!);
      final originalPdfBytes = originalPdfFile.readAsBytesSync();
      final pdfDoc = pw.Document();

      final originalPdf = PdfDocument(inputBytes: originalPdfBytes);

      print("Processing pages...");
      bool hasPages = false;

      for (int i = 1; i <= totalPages; i++) {
        print("modified pages length ${modifiedPages.length}");
        if (modifiedPages.contains(i)) {
          Uint8List? screenshot = pageScreenshots[i];
          if (screenshot == null) {
            await _captureAndStoreScreenshot();
            screenshot = pageScreenshots[i];
          }
          if (screenshot != null) {
            print("screenshot added ");
            final image = pw.MemoryImage(screenshot);
            pdfDoc.addPage(
              pw.Page(
                build: (pw.Context context) {
                  return pw.FullPage(
                      ignoreMargins: true,
                      child: pw.Image(image, fit: pw.BoxFit.fill));
                },
              ),
            );
            hasPages = true;
          }
        } else {
          // Get ByteData from the Image object and convert it to Uint8List
          final ByteData? byteData =
              await _pdfImages[i - 1].toByteData(format: ImageByteFormat.png);
          if (byteData != null) {
            final Uint8List unmodifiedImageBytes =
                byteData.buffer.asUint8List();
            final pwImage = pw.MemoryImage(unmodifiedImageBytes);

            pdfDoc.addPage(
              pw.Page(
                build: (pw.Context context) {
                  return pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(pwImage, fit: pw.BoxFit.fill),
                  );
                },
              ),
            );
            hasPages = true; // Page successfully added
          } else {
            print("Failed to get ByteData for page $i");
          }
        }
      }

      if (!hasPages) {
        throw Exception("No pages were added to the output PDF.");
      }

      // Save the output PDF
      print("Saving PDF...");
      final outputPdfBytes = await pdfDoc.save();
      final outputPdfFile = File(
        '${(await getApplicationDocumentsDirectory()).path}/annotated_pdf.pdf',
      );
      await outputPdfFile.writeAsBytes(outputPdfBytes);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved to ${outputPdfFile.path}')),
      );
      await OpenFile.open(outputPdfFile.path);
    } catch (e, stackTrace) {
      print('Error saving PDF: $e');
      print(stackTrace);
    }
  }

  List<ShapeAnnotation> _getAbsoluteShapes(
      List<ShapeAnnotation> normalizedShapes) {
    return normalizedShapes.map((shape) {
      return ShapeAnnotation(
        start: _getAbsoluteOffset(shape.start),
        end: _getAbsoluteOffset(shape.end),
        shapeType: shape.shapeType,
        color: shape.color,
        strokeWidth: shape.strokeWidth * zoomLevel,
      );
    }).toList();
  }

  ShapeAnnotation? _getAbsoluteShape(ShapeAnnotation? normalizedShape) {
    if (normalizedShape == null) return null;
    return ShapeAnnotation(
      start: _getAbsoluteOffset(normalizedShape.start),
      end: _getAbsoluteOffset(normalizedShape.end),
      shapeType: normalizedShape.shapeType,
      color: normalizedShape.color,
      strokeWidth: normalizedShape.strokeWidth * zoomLevel,
    );
  }

  Widget _buildToolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pdfPath != null && showOptions)
          Container(
            height: 50,
            color: Colors.grey[300],
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: ListView(
              //   mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              scrollDirection: Axis.horizontal,
              children: [
                IconButton(
                  color: mode == Mode.highlight ? Colors.yellow : Colors.black,
                  icon: Icon(Icons.highlight),
                  tooltip: 'Highlight',
                  onPressed: () {
                    _updateMode(Mode.highlight);
                  },
                ),
                IconButton(
                  color: mode == Mode.draw ? Colors.red : Colors.black,
                  icon: Icon(
                    Icons.brush,
                  ),
                  tooltip: 'Draw',
                  onPressed: () {
                    _updateMode(Mode.draw);
                  },
                ),
                IconButton(
                  color: mode == Mode.line ? Colors.blue : Colors.black,
                  icon: Icon(Icons.straighten),
                  tooltip: 'Draw Line',
                  onPressed: () {
                    _updateMode(Mode.line);
                  },
                ),
                IconButton(
                  color: mode == Mode.rectangle ? Colors.green : Colors.black,
                  icon: Icon(Icons.rectangle),
                  tooltip: 'Draw Rectangle',
                  onPressed: () {
                    _updateMode(Mode.rectangle);
                  },
                ),
                IconButton(
                  color: mode == Mode.circle ? Colors.orange : Colors.black,
                  icon: Icon(Icons.circle),
                  tooltip: 'Draw Circle',
                  onPressed: () {
                    _updateMode(Mode.circle);
                  },
                ),
                IconButton(
                  color: mode == Mode.arrow ? Colors.purple : Colors.black,
                  icon: Icon(Icons.arrow_forward),
                  tooltip: 'Draw Arrow',
                  onPressed: () {
                    _updateMode(Mode.arrow);
                  },
                ),
                IconButton(
                  color: mode == Mode.erase ? Colors.red : Colors.black,
                  icon: Icon(FontAwesomeIcons.eraser),
                  tooltip: 'Erase',
                  onPressed: () {
                    _updateMode(Mode.erase);
                  },
                ),
                IconButton(
                  color: mode == Mode.pan ? Colors.red : Colors.black,
                  icon: Icon(FontAwesomeIcons.hand),
                  tooltip: 'Pan',
                  onPressed: () {
                    _updateMode(Mode.pan);
                  },
                ),
                IconButton(
                  color: mode == Mode.text ? Colors.blue : Colors.black,
                  icon: Icon(Icons.text_fields),
                  tooltip: 'Add Text',
                  onPressed: () {
                    _updateMode(Mode.text);
                  },
                ),
                IconButton(
                  // color: mode == Mode.pan ? Colors.red : Colors.black,
                  icon: Icon(Icons.zoom_in),
                  tooltip: 'Zoom in',
                  onPressed: () {
                    setState(() {
                      _pdfViewerController.zoomLevel += 0.1;
                      zoomLevel = _pdfViewerController.zoomLevel;
                    });
                  },
                ),
                IconButton(
                  // color: mode == Mode.pan ? Colors.red : Colors.black,
                  icon: Icon(Icons.zoom_out),
                  tooltip: 'Zoom out',
                  onPressed: () {
                    setState(() {
                      _pdfViewerController.zoomLevel -= 0.1;
                      zoomLevel = _pdfViewerController.zoomLevel;
                    });
                  },
                ),
              ],
            ),
          ),
        Container(
          //  height: 100,
          color: Colors.grey[200],
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            //  scrollDirection: Axis.horizontal,
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () async {
                  if (currentPage > 1) {
                    await _captureAndStoreScreenshot();
                    _pdfViewerController.previousPage();
                  }
                },
              ),
              Expanded(
                child: Row(
                  children: [
                    Text("Page:"),
                    SizedBox(width: 8),
                    SizedBox(
                      width: 50,
                      child: TextField(
                        controller: _pageController,
                        decoration: InputDecoration(
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(vertical: 4),
                          border: OutlineInputBorder(),
                        ),
                        keyboardType: TextInputType.number,
                        onSubmitted: (value) {
                          final int? page = int.tryParse(value);
                          if (page != null &&
                              page > 0 &&
                              page <= totalPages &&
                              page != currentPage) {
                            _pdfViewerController.jumpToPage(page);
                          }
                        },
                      ),
                    ),
                    Text(
                      " / $totalPages",
                      style: TextStyle(fontSize: 16),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () async {
                  if (currentPage < totalPages) {
                    await _captureAndStoreScreenshot();
                    _pdfViewerController.nextPage();
                    setState(() {});
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  _closePDF() {
    setState(() {
      _pdfPath = null;
      mode = Mode.pan;
      _pdfPath;
      pageLines = {}; // Annotations per page
      pageHighlights = {};
      currentPage = 0; // Track the current page
      totalPages = 0; // Total pages in the PDF
      lines = [];
      highlights = [];
      currentPoint;
      pointerSize = 3.0; // Default pointer size
      pointerColor = Colors.black; // Default pointer color
      showOptions = true;
      pageTexts = {}; // Text annotations per page
      texts = []; // Current page's text annotations

      // Page dimensions and zoom factor
      pageSize;
      zoomLevel = 1.0;
      _pageController = TextEditingController();
    });
  }

  List<TextAnnotation> _getAbsoluteTexts(List<TextAnnotation> normalizedTexts) {
    return normalizedTexts
        .map((annotation) => TextAnnotation(
              _getAbsoluteOffset(annotation.position),
              annotation.text,
              annotation.style,
            ))
        .toList();
  }

  void _markPageAsModified() {
    print("mark as modified called ${currentPage}");
    modifiedPages.add(currentPage); // Add the current page to the modified set
  }

  void _addTextAnnotation(Offset localPosition) async {
    final normalizedPosition = _getNormalizedOffset(localPosition);
    String? inputText = await _showTextInputDialog();
    if (inputText != null && inputText.isNotEmpty) {
      setState(() {
        final annotation = TextAnnotation(
          normalizedPosition,
          inputText,
          TextStyle(color: pointerColor, fontSize: pointerSize * 4),
          isSelected: false, // Initialize as unselected
        );
        texts.add(annotation);

        if (pageTexts[currentPage] == null) {
          pageTexts[currentPage] = [];
        }
        pageTexts[currentPage]!.add(annotation);
      });
    }
  }

  Future<String?> _showTextInputDialog() async {
    TextEditingController textController = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text('Enter Text'),
          content: TextField(
            controller: textController,
            decoration: InputDecoration(hintText: 'Type here'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(null),
              child: Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(textController.text),
              child: Text('Add'),
            ),
          ],
        );
      },
    );
  }

  void _selectTextAnnotation(Offset localPosition) {
    final normalizedPosition = _getNormalizedOffset(localPosition);
    setState(() {
      for (var text in texts) {
        final textBounds = Rect.fromLTWH(
          text.position.dx,
          text.position.dy,
          text.style.fontSize! * text.text.length * 0.6, // Approximation
          text.style.fontSize!,
        );
        text.isSelected = textBounds.contains(normalizedPosition);
      }
    });
  }

  void _resizeSelectedText(double delta) {
    setState(() {
      for (var text in texts) {
        if (text.isSelected) {
          double newSize =
              (text.style.fontSize! + delta / 10).clamp(10.0, 100.0);
          text.style = text.style.copyWith(fontSize: newSize);
        }
      }
    });
  }

  Offset _getNormalizedOffset(Offset localPosition) {
    if (pageSize == null || zoomLevel == 0) return localPosition;

    // Normalize coordinates to a scale [0, 1]
    return Offset(
      localPosition.dx / (pageSize!.width * zoomLevel),
      localPosition.dy / (pageSize!.height * zoomLevel),
    );
  }

  Offset _getAbsoluteOffset(Offset normalizedOffset) {
    if (pageSize == null) return normalizedOffset;

    // Map normalized coordinates [0, 1] back to absolute page coordinates
    return Offset(
      normalizedOffset.dx * pageSize!.width * zoomLevel,
      normalizedOffset.dy * pageSize!.height * zoomLevel,
    );
  }

  List<DrawnLine> _getAbsoluteLines(List<DrawnLine> normalizedLines) {
    return normalizedLines
        .map((line) => DrawnLine(
              line.points.map(_getAbsoluteOffset).toList(),
              line.color,
              line.strokeWidth * zoomLevel,
              isDrawing: line.isDrawing,
            ))
        .toList();
  }

  void _updateMode(Mode newMode) {
    log("Update mode ");
    setState(() {
      mode = newMode;
    });
  }

  Offset _getScaledOffset(Offset localPosition) {
    if (pageSize == null || zoomLevel == 0) return localPosition;

    return Offset(
      localPosition.dx / zoomLevel,
      localPosition.dy / zoomLevel,
    );
  }

  void _handlePointerEvent(PointerEvent event) {
    log("handling pointer events");
    if (event is PointerDownEvent || event is PointerMoveEvent) {
      final Offset offset = _getScaledOffset(event.localPosition);
      if (mode == Mode.draw) {
        setState(() {
          if (lines.isEmpty || !lines.last.isDrawing) {
            lines.add(DrawnLine([offset], pointerColor, pointerSize,
                isDrawing: true));
          } else {
            lines.last.points.add(offset);
          }
        });
      }
    }
  }

  Future<void> _pickPDF() async {
    FilePickerResult? result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
    );

    if (result != null && result.files.single.path != null) {
      await _loadAndRasterizePdf(result.files.single.path!);
      setState(() {
        _pdfPath = result.files.single.path;
      });
    }
  }

  void _undo() {
    setState(() {
      if (mode == Mode.highlight && highlights.isNotEmpty) {
        highlights.removeLast();
      } else if (mode == Mode.draw && lines.isNotEmpty) {
        lines.removeLast();
      } else if ((mode == Mode.arrow ||
              mode == Mode.circle ||
              mode == Mode.line ||
              mode == Mode.rectangle) &&
          shapes.isNotEmpty) {
        shapes.removeLast();
      }
    });
  }

  void _eraseLine(Offset position) {
    setState(() {
      // Remove lines
      lines.removeWhere((line) {
        final isErased =
            line.points.any((point) => (point - position).distance < 10);
        if (isErased) pageLines[currentPage]?.remove(line);
        return isErased;
      });

      // Remove highlights
      highlights.removeWhere((highlight) {
        final isErased =
            highlight.points.any((point) => (point - position).distance < 10);
        if (isErased) pageHighlights[currentPage]?.remove(highlight);
        return isErased;
      });

      // Remove shapes
      shapes.removeWhere((shape) {
        final isErased = (shape.start - position).distance < 10 ||
            (shape.end - position).distance < 10;
        if (isErased) pageShapes[currentPage]?.remove(shape);
        return isErased;
      });

      // Remove text annotations
      texts.removeWhere((text) {
        final rect = Rect.fromLTWH(
          text.position.dx,
          text.position.dy,
          text.style.fontSize! * text.text.length * 0.6,
          text.style.fontSize!,
        );
        final isErased = rect.contains(position);
        if (isErased) pageTexts[currentPage]?.remove(text);
        return isErased;
      });
    });
  }

  Future<void> _saveModifiedPDF() async {
    print("Zoom Level = ${zoomLevel}");
    if (_pdfPath == null) return;

    final Uint8List? pdfBytes = await PdfUtils.overlayDrawingOnPDF(
      _pdfPath!,
      pageLines,
      pageHighlights,
      pageTexts,
    );

    if (pdfBytes != null) {
      final file = await PdfUtils.saveToFile(pdfBytes, "modified.pdf");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved to ${file.path}')),
      );

      final result = await OpenFile.open(file.path);
      if (result.type != ResultType.done) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open PDF: ${result.message}')),
        );
      }
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to save annotations to the PDF.')),
      );
    }
  }
}
