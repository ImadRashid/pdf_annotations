// import 'package:flutter/material.dart';
// import '/screens/pdf_editor_screen.dart';

// void main() {
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       debugShowCheckedModeBanner: false,
//       title: 'PDF Editor',
//       theme: ThemeData(primarySwatch: Colors.blue),
//       home: PdfEditorScreen(),
//     );
//   }
// }

// import 'dart:async';
// import 'dart:ui' as ui;

// import 'package:flutter/material.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:flutter/services.dart';
// import 'package:open_file/open_file.dart';
// import 'package:pdf/pdf.dart';
// import 'package:printing/printing.dart';
// import 'package:path_provider/path_provider.dart';
// import 'dart:io';
// import 'package:image/image.dart' as img;
// import 'package:pro_image_editor/pro_image_editor.dart';
// import 'package:pdf/widgets.dart' as pw;

// void main() {
//   runApp(MyApp());
// }

// class MyApp extends StatelessWidget {
//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       home: PdfToImageEditor(),
//     );
//   }
// }

// class PdfToImageEditor extends StatefulWidget {
//   @override
//   _PdfToImageEditorState createState() => _PdfToImageEditorState();
// }

// class _PdfToImageEditorState extends State<PdfToImageEditor> {
//   List<Uint8List> _pdfImages = [];
//   bool _isLoading = false;

//   Future<void> _pickPdfFile() async {
//     FilePickerResult? result = await FilePicker.platform.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: ['pdf'],
//     );

//     if (result != null) {
//       String? filePath = result.files.single.path;
//       if (filePath != null) {
//         await _loadAndRasterizePdf(filePath);
//       }
//     }
//   }

//   Future<void> _loadAndRasterizePdf(String filePath) async {
//     setState(() {
//       _isLoading = true;
//     });

//     try {
//       final file = File(filePath);
//       final documentBytes = await file.readAsBytes();

//       final pages = Printing.raster(documentBytes, dpi: 300);

//       final List<Uint8List> images = [];
//       await for (var page in pages) {
//         final image = await page.toPng();
//         images.add(image);
//       }
//       setState(() {
//         _pdfImages = images;
//       });
//     } catch (e) {
//       print('Error loading or rasterizing PDF: $e');
//     } finally {
//       setState(() {
//         _isLoading = false;
//       });
//     }
//   }

//   Future<void> _savePdf() async {
//     final pdf = pw.Document();

//     for (var image in _pdfImages) {
//       final pdfImage = pw.MemoryImage(image);

//       pdf.addPage(pw.Page(build: (pw.Context context) {
//         return pw.Image(pdfImage, fit: pw.BoxFit.fill);
//       }));
//     }

//     final output = await getTemporaryDirectory();
//     final file = File("${output.path}/output.pdf");
//     print("saving pdf....");
//     await file.writeAsBytes(await pdf.save());
//     await OpenFile.open(file.path);
//   }

//   void _editImage(int index) async {
//     final originalImage = img.decodeImage(_pdfImages[index]);

//     // Create a white canvas to draw the image on
//     final pictureRecorder = ui.PictureRecorder();
//     final canvas = Canvas(
//         pictureRecorder,
//         Rect.fromPoints(
//             Offset(0, 0),
//             Offset(originalImage!.width.toDouble(),
//                 originalImage.height.toDouble())));

//     // Fill the canvas with white background
//     final paint = Paint()..color = Colors.white;
//     canvas.drawRect(
//         Rect.fromLTRB(0, 0, originalImage.width.toDouble(),
//             originalImage.height.toDouble()),
//         paint);

//     // Draw the original image on top of the white background
//     final ui.Image imgToDraw = await _convertImageToUiImage(originalImage);
//     canvas.drawImage(imgToDraw, Offset(0, 0), paint);

//     // Create a new image from the canvas with a white background
//     final picture = pictureRecorder.endRecording();
//     final imgData =
//         await picture.toImage(originalImage.width, originalImage.height);

//     // Convert the new image to byte data (JPEG or PNG format)
//     final byteData = await imgData.toByteData(format: ui.ImageByteFormat.png);
//     final editedImage = byteData!.buffer.asUint8List();

//     // Now push it to the editor screen
//     final updatedImage = await Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (context) => ProImageEditor.memory(
//           editedImage,
//           configs: ProImageEditorConfigs(
//             theme: ThemeData.light().copyWith(
//               scaffoldBackgroundColor: Colors.white,
//               canvasColor: Colors.white,
//             ),
//             imageEditorTheme: ImageEditorTheme(
//                 background: Colors.white,
//                 paintingEditor: PaintingEditorTheme(background: Colors.white)),
//             paintEditorConfigs:
//                 PaintEditorConfigs(enabled: true, enableZoom: true),
//             textEditorConfigs: TextEditorConfigs(enabled: true),
//             cropRotateEditorConfigs: CropRotateEditorConfigs(enabled: false),
//             filterEditorConfigs: FilterEditorConfigs(enabled: false),
//             tuneEditorConfigs: TuneEditorConfigs(enabled: false),
//             blurEditorConfigs: BlurEditorConfigs(enabled: false),
//             emojiEditorConfigs: EmojiEditorConfigs(enabled: false),
//             stickerEditorConfigs: StickerEditorConfigs(
//                 enabled: false,
//                 buildStickers: (dynamic Function(Widget) setLayer,
//                     ScrollController scrollController) {
//                   return SizedBox.shrink();
//                 }),
//           ),
//           callbacks: ProImageEditorCallbacks(
//               onImageEditingComplete: (Uint8List editedImageData) async {
//             setState(() {
//               _pdfImages[index] = editedImageData;
//             });
//             Navigator.of(context).pop();
//           }),
//         ),
//       ),
//     );

//     if (updatedImage != null) {
//       setState(() {
//         _pdfImages[index] = updatedImage;
//       });
//     }
//   }

//   // Convert img.Image to ui.Image for drawing
//   Future<ui.Image> _convertImageToUiImage(img.Image image) async {
//     final completer = Completer<ui.Image>();
//     ui.decodeImageFromList(Uint8List.fromList(img.encodePng(image)),
//         (ui.Image img) {
//       completer.complete(img);
//     });
//     return completer.future;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('PDF to Image Editor'),
//       ),
//       body: _isLoading
//           ? Center(child: CircularProgressIndicator())
//           : _pdfImages.isEmpty
//               ? Center(child: Text('No images to display'))
//               : Container(
//                   //  color: Colors.blue,
//                   child: PageView.builder(
//                     itemCount: _pdfImages.length,
//                     itemBuilder: (context, index) {
//                       return GestureDetector(
//                           onTap: () => _editImage(index),
//                           child: Container(
//                             // color: Colors.yellow,
//                             child: Image.memory(
//                               _pdfImages[index],
//                             ),
//                           ));
//                     },
//                   ),
//                 ),
//       floatingActionButton: FloatingActionButton(
//         onPressed: _pickPdfFile,
//         child: Icon(Icons.add),
//       ),
//       persistentFooterButtons: [
//         ElevatedButton(
//           onPressed: _savePdf,
//           child: Text('Save as PDF'),
//         ),
//       ],
//     );
//   }
// }

import 'dart:async';
import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:pdf_annotations/models/drawn_line.dart';
import 'package:pdf_annotations/models/shape_annotation.dart';
import 'package:pdf_annotations/models/text_annotation.dart';
import 'package:pdf_annotations/screens/pdf_editor_screen.dart';
import 'package:pdf_annotations/widgets/drawing_painter.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:vector_math/vector_math_64.dart' as math;
import 'package:pdf_render/pdf_render.dart' as pr;

// enum Mode {
//   highlight,
//   draw,
//   erase,
//   text,
//   pan,
//   line,
//   rectangle,
//   circle,
//   arrow,
// }

class PdfPageViewCanvas extends StatefulWidget {
  @override
  _PdfPageViewCanvasState createState() => _PdfPageViewCanvasState();
}

class _PdfPageViewCanvasState extends State<PdfPageViewCanvas> {
  TransformationController _transformationController =
      TransformationController();
  double _scale = 1.0;
  List<ui.Image> _pdfImages = [];
  int _totalPages = 0;
  String? _selectedPdfPath;
  Mode mode = Mode.pan;
  //double zoomLevel = 1.0;
  TextEditingController _pageController = TextEditingController(text: "1");
  Map<int, List<DrawnLine>> pageLines = {};
  Map<int, List<DrawnLine>> pageHighlights = {};
  int currentPage = 1;
  int totalPages = 0;
  List<DrawnLine> lines = [];
  List<DrawnLine> highlights = [];
  Offset? currentPoint;
  Map<int, List<ShapeAnnotation>> pageShapes = {};
  List<ShapeAnnotation> shapes = [];
  ShapeAnnotation? currentShape;

  double pointerSize = 3.0;
  Color pointerColor = Colors.black;
  bool showOptions = true;
  Map<int, List<TextAnnotation>> pageTexts = {};
  List<TextAnnotation> texts = [];
  ScreenshotController screenshotController = ScreenshotController();

  bool isZooming = false;

  Set<int> modifiedPages = {};
  Map<int, Uint8List> pageScreenshots = {};
  @override
  void initState() {
    super.initState();
  }

  void _zoomIn() {
    setState(() {
      _scale *= 1.2;
      //  zoomLevel *= 1.2;
      _transformationController.value =
          Matrix4.diagonal3(math.Vector3(_scale, _scale, 1.0));
    });
  }

  void _zoomOut() {
    setState(() {
      _scale /= 1.2;
      //zoomLevel /= 1.2;
      _transformationController.value =
          Matrix4.diagonal3(math.Vector3(_scale, _scale, 1.0));
    });
  }

  void _resetZoom() {
    _scale = 1.0;
    _transformationController.value =
        Matrix4.diagonal3(math.Vector3(_scale, _scale, 1.0));
    setState(() {});
  }

  double maxWidth = 1000.0;

  Offset _getNormalizedOffset(Offset localFocalPoint) {
    // Normalize the local focal point based on current scale and pan offset
    final matrix = _transformationController.value;

    // Apply the inverse of the transformation matrix to convert the local coordinates
    // final inverseMatrix = matrix.clone().invert();
    final Matrix4 inverseMatrix =
        Matrix4.tryInvert(_transformationController.value) ??
            Matrix4.identity();
    final transformedOffset =
        MatrixUtils.transformPoint(inverseMatrix, localFocalPoint);

    // Return the transformed position, adjusted for scale and pan
    return transformedOffset;
  }

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
            icon: Icon(Icons.save),
            onPressed: _savePdf,
          ),
        ],
      ),
      body: _isLoading
          ? Center(child: CircularProgressIndicator())
          : _selectedPdfPath == null
              ? Center(child: Text('Please select a PDF file to display'))
              : _pdfImages.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Expanded(
                          child: Screenshot(
                            controller: screenshotController,
                            child: InteractiveViewer(
                              transformationController:
                                  _transformationController,
                              onInteractionStart: (details) {
                                setState(() {
                                  isZooming = details.pointerCount > 1;
                                });

                                if (!isZooming && mode != Mode.pan) {
                                  final startPoint = _getNormalizedOffset(
                                      details.localFocalPoint);
                                  setState(() {
                                    if (mode == Mode.text) {
                                      _addTextAnnotation(
                                          details.localFocalPoint);
                                    } else if (mode == Mode.erase) {
                                      _eraseLine(startPoint);
                                    } else if ([
                                      Mode.line,
                                      Mode.rectangle,
                                      Mode.circle,
                                      Mode.arrow
                                    ].contains(mode)) {
                                      currentShape = ShapeAnnotation(
                                        start: startPoint,
                                        end: startPoint,
                                        shapeType: mode,
                                        color: pointerColor,
                                        strokeWidth: pointerSize / _scale,
                                      );
                                    }
                                  });
                                }
                              },
                              onInteractionUpdate: (details) {
                                _markPageAsModified();

                                if (isZooming) {
                                  setState(() {
                                    _scale = (_scale * details.scale)
                                        .clamp(1.0, 3.0);
                                  });
                                } else if (mode != Mode.pan) {
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
                                            isDrawing: true);
                                        highlights.add(newHighlight);

                                        if (pageHighlights[currentPage] ==
                                            null) {
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
                                            [offset], pointerColor, pointerSize,
                                            isDrawing: true);
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
                                        currentShape =
                                            currentShape!.copyWith(end: offset);
                                      }
                                    }
                                    currentPoint = offset;
                                  });
                                }
                              },
                              onInteractionEnd: (details) {
                                setState(() {
                                  isZooming = false;
                                });

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
                              panEnabled: mode == Mode.pan,
                              child: Stack(
                                children: [
                                  CustomPaint(
                                    painter: PdfPagePainter(
                                        _pdfImages[currentPage - 1]),
                                    child: Container(),
                                  ),
                                  CustomPaint(
                                    painter: DrawingPainter(
                                      _getAbsoluteLines(lines),
                                      _getAbsoluteLines(highlights),
                                      _getAbsoluteTexts(texts),
                                      shapes: _getAbsoluteShapes(shapes),
                                      currentShape:
                                          _getAbsoluteShape(currentShape),
                                    ),
                                  ),
                                  ...texts.map((text) {
                                    return Positioned(
                                      left: text.position.dx * _scale,
                                      top: text.position.dy * _scale,
                                      child: Draggable<TextAnnotation>(
                                        data: text,
                                        feedback: Material(
                                          child: Transform.scale(
                                            scale: _scale,
                                            child: Text(text.text,
                                                style: text.style),
                                          ),
                                        ),
                                        childWhenDragging: Container(),
                                        onDraggableCanceled:
                                            (velocity, offset) {
                                          final postion =
                                              _getNormalizedOffset(offset);
                                          final inverseMatrix =
                                              Matrix4.tryInvert(
                                                  _transformationController
                                                      .value);
                                          if (inverseMatrix != null) {
                                            final transformedOffset =
                                                MatrixUtils.transformPoint(
                                                    inverseMatrix, offset);
                                            setState(() {
                                              text.position = offset;
                                            });
                                          }
                                        },
                                        child: GestureDetector(
                                          onTap: () {
                                            setState(() {
                                              text.isSelected =
                                                  !text.isSelected;
                                            });
                                          },
                                          child: Text(text.text,
                                              style: TextStyle(
                                                  color: Colors.transparent)),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ],
                              ),
                            ),
                          ),
                        ),
                        _buildToolbar(),
                      ],
                    ),
    );
  }

  Future<Uint8List?> _captureScreenshot() async {
    // _pdfViewerController.zoomLevel = 1.0;
    // zoomLevel = _pdfViewerController.zoomLevel;
    //  setState(() {});

    try {
      if (_scale > 1.0 || _scale < 1.0) {
        _resetZoom();
      }
      final Uint8List? screenshot =
          await screenshotController.capture(pixelRatio: 4);
      if (screenshot == null) {
        print("Screenshot capture failed");
        return null;
      }

      return
          //screenshot;
          _cropImage(screenshot);
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

    final cropMarginLeft = 800;
    final cropMarginRight = 800;

    // Calculate the new dimensions
    final croppedWidth = image.width - cropMarginLeft - cropMarginRight;
    final croppedHeight = image.height;

    // Crop the image
    final croppedImage = img.copyCrop(
      image,
      x: cropMarginLeft,
      y: 0,
      width: croppedWidth,
      height: croppedHeight,
    );

    return Uint8List.fromList(img.encodePng(croppedImage));
  }

  bool _isLoading = false;
  Future<void> _savePdf() async {
    try {
      final pdfDoc = pw.Document();
      print("Processing pages...");
      bool hasPages = false;

      for (int i = 1; i <= _pdfImages.length; i++) {
        if (modifiedPages.contains(i)) {
          Uint8List? screenshot = pageScreenshots[i];
          if (screenshot == null) {
            await _captureAndStoreScreenshot();
            screenshot = pageScreenshots[i];
          }
          if (screenshot != null) {
            final image = pw.MemoryImage(screenshot);
            pdfDoc.addPage(
              pw.Page(
                build: (pw.Context context) {
                  return pw.FullPage(
                    ignoreMargins: true,
                    child: pw.Image(
                      image,
                      fit: pw.BoxFit.fill,
                      // width: _pdfImages[0].width.toDouble(),
                      // height: _pdfImages[0].height.toDouble(),
                    ),
                  );
                },
              ),
            );
            hasPages = true;
          }
        } else {
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
      _isLoading = true;
      setState(() {});
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
    _isLoading = false;
    setState(() {});
  }

  Future<void> _savePdfDirectly() async {
    // Load the original PDF
    final pdfDocument =
        PdfDocument(inputBytes: await File(_selectedPdfPath!).readAsBytes());

    // Process each page
    for (int i = 0; i < _totalPages; i++) {
      final PdfPage pdfPage = pdfDocument.pages[i];

      // Get the page's graphics object for drawing
      final PdfGraphics graphics = pdfPage.graphics;

      // Draw all lines
      if (pageLines.containsKey(i + 1)) {
        for (final line in pageLines[i + 1]!) {
          final paint = PdfPen(
              PdfColor(line.color.red, line.color.green, line.color.blue),
              width: line.strokeWidth);

          for (int j = 0; j < line.points.length - 1; j++) {
            final point1 = line.points[j];
            final point2 = line.points[j + 1];
            graphics.drawLine(paint, Offset(point1.dx, point1.dy),
                Offset(point2.dx, point2.dy));
          }
        }
      }

      // Draw all text annotations
      if (pageTexts.containsKey(i + 1)) {
        for (final text in pageTexts[i + 1]!) {
          final PdfFont font = PdfStandardFont(
              PdfFontFamily.helvetica, text.style.fontSize ?? 12);
          graphics.drawString(
            text.text,
            font,
            brush: PdfSolidBrush(PdfColor(text.style.color!.red,
                text.style.color!.green, text.style.color!.blue)),
            bounds: Rect.fromLTWH(text.position.dx, text.position.dy, 500, 50),
          );
        }
      }

      // Draw shapes (rectangles, circles, etc.)
      if (pageShapes.containsKey(i + 1)) {
        for (final shape in pageShapes[i + 1]!) {
          final paint = PdfPen(
              PdfColor(shape.color.red, shape.color.green, shape.color.blue),
              width: shape.strokeWidth);
          if (shape.shapeType == Mode.rectangle) {
            graphics.drawRectangle(
              bounds: Rect.fromPoints(Offset(shape.start.dx, shape.start.dy),
                  Offset(shape.end.dx, shape.end.dy)),
              pen: paint,
            );
          } else if (shape.shapeType == Mode.circle) {
            final center = Offset((shape.start.dx + shape.end.dx) / 2,
                (shape.start.dy + shape.end.dy) / 2);
            final radius = (shape.start - shape.end).distance / 2;
            graphics.drawEllipse(
              Rect.fromCircle(center: center, radius: radius),
              pen: paint,
            );
          }
        }
      }
    }

    // Save the modified PDF
    final output = await getTemporaryDirectory();
    final file = File('${output.path}/annotated_pdf.pdf');
    await file.writeAsBytes(await pdfDocument.save());
    await OpenFile.open(file.path);

    // Dispose of the PDF document
    pdfDocument.dispose();
  }

  List<ShapeAnnotation> _getAbsoluteShapes(
      List<ShapeAnnotation> normalizedShapes) {
    return normalizedShapes.map((shape) {
      return ShapeAnnotation(
        start: _getAbsoluteOffset(shape.start),
        end: _getAbsoluteOffset(shape.end),
        shapeType: shape.shapeType,
        color: shape.color,
        strokeWidth: shape.strokeWidth * _scale,
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
      strokeWidth: normalizedShape.strokeWidth * _scale,
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
            //       _drawings = [];
          });

          _loadAndRenderPdf(filePath);
        }
      }
    } catch (e) {
      print('Error picking file: $e');
    }
  }

  Future<void> _loadAndRenderPdf(String filePath) async {
    try {
      final doc = await pr.PdfDocument.openFile(filePath);
      final int pageCount = doc.pageCount;
      print("pages count ===> $pageCount");
      for (int i = 1; i <= pageCount; i++) {
        final page = await doc.getPage(i);

        double scale = 3.0; // You can adjust this value as needed
        final image = await page.render(
          width: (page.width * scale).toInt(),
          height: (page.height * scale).toInt(),
          fullWidth: page.width * scale,
          fullHeight: page.height * scale,
        );

        final ui.Image renderedImage = await image.createImageDetached();

        setState(() {
          _pdfImages.add(renderedImage);
          _totalPages = pageCount;
        });

        print("total images ====> ${_pdfImages.length}");
      }
    } catch (e) {
      print('Error loading or rendering PDF: $e');
    }
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

  // Offset _getNormalizedOffset(Offset localPosition) {
  //   if (_scale == 0) return localPosition;
  //   print("get normalized offset ");
  //   // Normalize coordinates to a scale [0, 1]
  //   return Offset(
  //     localPosition.dx / (_scale),
  //     localPosition.dy / (_scale),
  //   );
  // }

  Offset _getAbsoluteOffset(Offset normalizedOffset) {
    //   if (pageSize == null) return normalizedOffset;
    return normalizedOffset;
    // Offset(
    //   normalizedOffset.dx,
    //   normalizedOffset.dy,
    // );
  }

  List<DrawnLine> _getAbsoluteLines(List<DrawnLine> normalizedLines) {
    return normalizedLines
        .map((line) => DrawnLine(
              line.points.map(_getAbsoluteOffset).toList(),
              line.color,
              line.strokeWidth * _scale,
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

  // Offset _getScaledOffset(Offset localPosition) {
  //   if (pageSize == null || zoomLevel == 0) return localPosition;

  //   return Offset(
  //     localPosition.dx / zoomLevel,
  //     localPosition.dy / zoomLevel,
  //   );
  // }

  Widget _buildToolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          height: 50,
          //  color: Colors.red,
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
                icon: Icon(Icons.zoom_in),
                tooltip: 'Zoom in',
                onPressed: () {
                  setState(() {
                    //   zoomLevel += 0.1;
                    _zoomIn();
                  });
                },
              ),
              IconButton(
                icon: Icon(Icons.zoom_out),
                tooltip: 'Zoom out',
                onPressed: () {
                  setState(() {
                    // zoomLevel -= 0.1;
                    _zoomOut();
                  });
                },
              ),
            ],
          ),
        ),
        Container(
          color: Colors.grey[200],
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () async {
                  if (currentPage > 0) {
                    await _captureAndStoreScreenshot();
                    setState(() {
                      currentPage--;

                      _pageController.text = currentPage.toString();
                      print("new page number ${currentPage} ");

                      // Load new page annotations
                      lines = pageLines[currentPage] ?? [];
                      highlights = pageHighlights[currentPage] ?? [];
                      texts = pageTexts[currentPage] ?? [];
                      shapes = pageShapes[currentPage] ?? [];
                      pageShapes[currentPage] = shapes;
                    });
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
                              page <= _totalPages &&
                              page != currentPage) {
                            setState(() {
                              currentPage = page - 1;
                            });
                          }
                        },
                      ),
                    ),
                    Text(" / $_totalPages"),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.arrow_forward),
                onPressed: () async {
                  if (currentPage < _totalPages - 1) {
                    await _captureAndStoreScreenshot();
                    setState(() {
                      currentPage++;
                      _pageController.text = currentPage.toString();
                      print("new page number ${currentPage} ");

                      // Load new page annotations
                      lines = pageLines[currentPage] ?? [];
                      highlights = pageHighlights[currentPage] ?? [];
                      texts = pageTexts[currentPage] ?? [];
                      shapes = pageShapes[currentPage] ?? [];
                      pageShapes[currentPage] = shapes;
                    });
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  // void _updateMode(Mode newMode) {
  //   setState(() {
  //     mode = newMode;
  //   });
  // }
}

class PdfPagePainter extends CustomPainter {
  final ui.Image image;

  PdfPagePainter(this.image);

  @override
  void paint(Canvas canvas, Size size) {
    paintImage(
      canvas: canvas,
      rect: Rect.fromLTWH(0, 0, size.width, size.height),
      image: image,
      fit: BoxFit.contain,
    );
  }

  @override
  bool shouldRepaint(CustomPainter oldDelegate) => false;
}

void main() {
  runApp(MaterialApp(
    home: PdfPageViewCanvas(),
  ));
}
