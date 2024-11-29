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
import 'package:flutter/rendering.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:image/image.dart' as img;
import 'package:pdf_annotations/models/drawn_line.dart';
import 'package:pdf_annotations/models/shape_annotation.dart';
import 'package:pdf_annotations/models/text_annotation.dart';
import 'package:pdf_annotations/screens/pdf_editor_screen.dart';
import 'package:pdf_annotations/utils/pdf_utils.dart';
import 'package:pdf_annotations/widgets/drawing_painter.dart';
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:vector_math/vector_math_64.dart' as math;

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
  double _previousScale = 1.0;

  List<Uint8List> _screenshots = [];
  List<ui.Image> _pdfImages = [];
  int _totalPages = 0;
  String? _selectedPdfPath;
  List<List<Offset?>> _drawings = [];
  //int _currentPage = 0;
  Mode mode = Mode.pan;
  //double zoomLevel = 1.0;
  TextEditingController _pageController = TextEditingController(text: "1");
  Offset _lastPanOffset = Offset.zero;
  Offset _currentPanOffset = Offset.zero;
  // Mode mode = Mode.pan;
  List<GlobalKey> _repaintBoundaryKeys = [];
  // final PdfViewerController _pdfViewerController = PdfViewerController();
  Map<int, List<DrawnLine>> pageLines = {}; // Annotations per page
  Map<int, List<DrawnLine>> pageHighlights = {};
  int currentPage = 1; // Track the current page
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
  //double zoomLevel = 1.0;
  bool isZooming = false;
  //TextEditingController _pageController = TextEditingController();
  Set<int> modifiedPages = {}; // Tracks the indices of modified pages
  Map<int, Uint8List> pageScreenshots =
      {}; // Store screenshots of modified pages
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
          ? Center(
              child: CircularProgressIndicator(),
            )
          : _selectedPdfPath == null
              ? Center(child: Text('Please select a PDF file to display'))
              : _pdfImages.isEmpty
                  ? Center(child: CircularProgressIndicator())
                  : Column(
                      children: [
                        Expanded(
                          child: GestureDetector(
                            onTapDown: (details) {
                              print("heree");
                              if (mode == Mode.text) {
                                _selectTextAnnotation(details.localPosition);
                              }

                              if (mode == Mode.text) {
                                _addTextAnnotation(details.localPosition);
                              }
                            },
                            child: Screenshot(
                              controller: screenshotController,
                              child: InteractiveViewer(
                                transformationController:
                                    _transformationController,
                                onInteractionStart: (details) {
                                  print("Scale start: ${details.pointerCount}");
                                  // Check if this is a zoom or pan gesture
                                  setState(() {
                                    isZooming = details.pointerCount > 1;
                                    _previousScale = _scale;
                                  });
                                  if (!isZooming && mode == Mode.text) {
                                    _selectTextAnnotation(
                                        details.localFocalPoint);
                                  }

                                  // if (mode == Mode.pan) {
                                  //   _lastPanOffset = details.localFocalPoint;
                                  // }

                                  if (!isZooming && mode != Mode.pan) {
                                    final startPoint = _getNormalizedOffset(
                                        details.localFocalPoint);
                                    if (mode == Mode.text) {
                                      _addTextAnnotation(
                                          details.localFocalPoint);
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
                                          strokeWidth: pointerSize / _scale,
                                        );
                                      });
                                    }
                                  }
                                },
                                onInteractionUpdate: (details) {
                                  _markPageAsModified();
                                  // if (mode == Mode.pan) {
                                  setState(() {
                                    // _scale = _previousScale * details.scale;
                                    // _transformationController.value =
                                    //     Matrix4.diagonal3(
                                    //         math.Vector3(_scale, _scale, 1.0));
                                    // _currentPanOffset =
                                    //     _lastPanOffset - details.localFocalPoint;
                                  });
                                  //  }
                                  if (isZooming) {
                                    print("Zooming");
                                    if ((details.scale - 1.0).abs() > 0.01) {
                                      // Threshold for significant changes
                                      setState(() {
                                        _scale = (_scale * details.scale)
                                            .clamp(1.0, 3.0);
                                        // _pdfViewerController.zoomLevel = zoomLevel;
                                      });
                                    }
                                  } else if (mode != Mode.pan) {
                                    if (mode == Mode.text) {
                                      setState(() {
                                        for (var text in texts) {
                                          if (text.isSelected) {
                                            // Move selected text annotation
                                            text.position +=
                                                details.focalPointDelta /
                                                    _scale;
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
                                          currentShape = currentShape!
                                              .copyWith(end: offset);
                                        }
                                      }
                                      currentPoint = offset;
                                    });
                                  }
                                },
                                onInteractionEnd: (details) {
                                  print("Scale end");
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
                                          _pdfImages[currentPage]),
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
                                        panOffset: _currentPanOffset,
                                      ),
                                    ),
                                  ],
                                ),
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

  bool _isLoading = false;
  Future<void> _savePdf() async {
    print("pathh = $_selectedPdfPath");
    try {
      final originalPdfFile = File(_selectedPdfPath!);
      final originalPdfBytes = originalPdfFile.readAsBytesSync();
      final pdfDoc = pw.Document();

      // final originalPdf = PdfDocument(inputBytes: originalPdfBytes);

      print("Processing pages...");
      bool hasPages = false;

      for (int i = 1; i <= _pdfImages.length; i++) {
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
        _drawings.add([]);
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
    if (pageSize == null || _scale == 0) return localPosition;

    // Normalize coordinates to a scale [0, 1]
    return Offset(
      localPosition.dx / (pageSize!.width * _scale),
      localPosition.dy / (pageSize!.height * _scale),
    );
  }

  Offset _getAbsoluteOffset(Offset normalizedOffset) {
    if (pageSize == null) return normalizedOffset;

    // Map normalized coordinates [0, 1] back to absolute page coordinates
    return Offset(
      normalizedOffset.dx * pageSize!.width * _scale,
      normalizedOffset.dy * pageSize!.height * _scale,
    );
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
