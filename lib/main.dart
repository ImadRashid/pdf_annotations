import 'dart:async';
import 'dart:developer';
import 'dart:ui' as ui;
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:open_file/open_file.dart';
import 'package:pdf_annotations/const.dart';
import 'package:pdf_annotations/customButton.dart';
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

import 'utils.dart';

const String _path =
    "/Users/imadrashid/Library/Developer/CoreSimulator/Devices/7F6DE896-F3AC-4087-A25F-172B4F8A7F0C/data/Containers/Data/Application/0CAC396E-EE21-4867-9808-314EC4A38494/tmp/Iman's Resume.pdf";
void main() {
  runApp(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      home: PdfViewerPage(
        filePath: _path,
        exportToStorage: true,
      ),
    ),
  );
}

//// HOW TO USE
/// if you pass a file path in the argument the document will try to load that file
/// if you don't pass any filepath it will open the screen with a button to pick a file

class PdfViewerPage extends StatefulWidget {
  final void Function()? onCloseButtonAction;
  bool? exportToStorage;
  //if file path is null it will show pick a file button at center of screen
  final String? filePath;
  // pass either measurement or annotations mode default is annotations
  PdfViewerPage({
    super.key,
    this.onCloseButtonAction,
    this.filePath,
    this.exportToStorage = false,
  });

  @override
  State<PdfViewerPage> createState() => _PdfViewerPageState();
}

class _PdfViewerPageState extends State<PdfViewerPage> {
  Offset? _currentPointerPosition;

  Map<int, List<DrawingPath>> pageDrawings = {};
  List<DrawingPoint> currentPath = [];
  Color currentMeasurementColor = Colors.orange;
  double currentMeasurementStroke = 10.0;
  Color currentMeasurementLineColor = Colors.black;
  double currentMeasurementLineStroke = 10.0;
  Color currentMeasurementBoxColor = Colors.black;
  double currentMeasurementBoxStroke = 10.0;

  Map<int, DrawingPath?> pageReferenceLines = {};
  Map<int, TextAnnotation?> pageReferenceTexts = {};
  Map<int, double?> pagePixelsPerMeter = {};
  Map<int, double?> pageLineLengths = {};
  DrawingPath? get referenceLine => pageReferenceLines[currentPage];
  TextAnnotation? get referenceText => pageReferenceTexts[currentPage];
  double? get pixelsPerMeter => pagePixelsPerMeter[currentPage];
  double? get lineLength => pageLineLengths[currentPage];

  // Helper methods to manage page-specific drawings
  List<DrawingPath> get currentPagePaths => pageDrawings[currentPage] ?? [];

  List<DrawingPath> paths = [];

  Color currentColor = Colors.red;
  Color currentColorHighlight = Colors.yellow.withAlpha(50);
  double currentStrokePen = 12.0;
  double currentStrokeHighlight = 48.0;

  pr.PdfDocument? document;
  String? currentFilePath;

  bool isExporting = false;

  bool isLoading = false;
  int currentPage = 0;
  int totalPages = 0;
  Offset? lineStart;
  ui.Image? currentPageImage;
  bool isPageLoading = false;
  double quality = 4.0;
  // String mode = 'draw';
  Mode mode = Mode.pan;

  double currentEraserSize = 20.0;
  bool isTypingText = false;
  FocusNode textFocusNode = FocusNode();
  OverlayEntry? textOverlay;
  final LayerLink layerLink = LayerLink();

  final List<double> fontSizes = [12, 14, 16, 18, 20, 24, 28, 32, 36, 48];
  double selectedFontSize = 16.0;

  double zoom = 1.0;
  double previousZoom = 1.0;
  Offset offset = Offset.zero;
  Offset previousOffset = Offset.zero;
  double? initialLineLength;

  Map<int, List<TextAnnotation>> pageTextAnnotations = {};
  TextEditingController textController = TextEditingController();
  Offset? pendingTextPosition;
  bool isAddingText = false;
  DrawingPath? referenceBox; // Store reference box
  TextAnnotation? referenceBoxText; // Store reference box measurement text
  double? boxArea; // Store box area
  double? pixelsPerSquareMeter; // For area calculations
  Offset? boxStart; // For drawing the box
  Rect? currentBox;
  List<TextAnnotation> get currentPageTextAnnotations =>
      pageTextAnnotations[currentPage] ?? [];

  TextAnnotation? selectedAnnotation;
  bool isDraggingText = false;
  bool isResizingText = false;
  Offset? dragOffset;
  bool _canUndoScale = false;
  final _referenceFocusNode = FocusNode();
  MeasurementTool measurementTool = MeasurementTool.none;
  TextEditingController _referenceController = TextEditingController();

  void _handleTextInteraction(Offset position) {
    final transformedPosition = _getTransformedOffset(position);

    for (final annotation in pageTextAnnotations[currentPage] ?? []) {
      final rect = Rect.fromLTWH(
        annotation.position.dx,
        annotation.position.dy,
        annotation.size.width,
        annotation.size.height,
      );

      if (rect.contains(transformedPosition)) {
        setState(() {
          selectedAnnotation = annotation;
          isDraggingText = true;
          dragOffset = transformedPosition - annotation.position;
        });
        return;
      }
    }
  }

  void handleErase(Offset point) {
    final transformedPoint = _getTransformedOffset(point);
    final eraserRadius = currentEraserSize / (2 * zoom);
    bool modified = false;

    // Store old states before modification
    final oldDrawings = pageDrawings[currentPage] != null
        ? List<DrawingPath>.from(pageDrawings[currentPage]!)
        : null;
    final oldTexts = pageTextAnnotations[currentPage] != null
        ? List<TextAnnotation>.from(pageTextAnnotations[currentPage]!)
        : null;

    // Handle text annotations
    if (pageTextAnnotations.containsKey(currentPage)) {
      bool textRemoved = false;
      List<TextAnnotation> remainingAnnotations = [];

      for (var annotation in pageTextAnnotations[currentPage]!) {
        final textSpan = TextSpan(
          text: annotation.text,
          style: TextStyle(
            fontSize: annotation.fontSize,
            fontFamily: annotation.fontFamily,
          ),
        );

        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        )..layout();

        final textBounds = Rect.fromLTWH(
          annotation.position.dx,
          annotation.position.dy,
          textPainter.width / quality,
          textPainter.height / quality,
        );

        final eraserBounds = Rect.fromCircle(
          center: transformedPoint,
          radius: eraserRadius,
        );

        if (!textBounds.overlaps(eraserBounds) &&
            !textBounds.contains(transformedPoint) &&
            !eraserBounds.contains(textBounds.center)) {
          remainingAnnotations.add(annotation);
        } else {
          textRemoved = true;
          modified = true;
        }
      }

      if (textRemoved) {
        setState(() {
          if (remainingAnnotations.isEmpty) {
            pageTextAnnotations.remove(currentPage);
          } else {
            pageTextAnnotations[currentPage] = remainingAnnotations;
          }
        });
      }
    }

    // Handle drawings
    if (pageDrawings.containsKey(currentPage)) {
      bool pathsModified = false;
      List<DrawingPath> newPaths = [];

      for (var path in pageDrawings[currentPage]!) {
        bool pathAffected = false;

        for (var drawPoint in path.points) {
          if ((drawPoint.point - transformedPoint).distance <= eraserRadius) {
            pathAffected = true;
            modified = true;
            break;
          }
        }

        if (pathAffected) {
          final segments = path.splitPath(transformedPoint, eraserRadius);
          newPaths.addAll(segments);
          pathsModified = true;
        } else {
          newPaths.add(path);
        }
      }

      if (pathsModified) {
        setState(() {
          pageDrawings[currentPage] =
              newPaths.where((path) => path.points.length > 1).toList();
        });
      }
    }

    // Add to history if any changes were made
    if (modified) {
      addToHistory(AnnotationAction(
        type: ActionType.erase,
        pageNumber: currentPage,
        oldState: {
          'drawings': oldDrawings,
          'texts': oldTexts,
        },
        newState: {
          'drawings': List<DrawingPath>.from(pageDrawings[currentPage] ?? []),
          'texts':
              List<TextAnnotation>.from(pageTextAnnotations[currentPage] ?? []),
        },
      ));
    }
  }

  double _getAdjustedStrokeWidth(double baseWidth) {
    return baseWidth / zoom;
  }

  @override
  void initState() {
    super.initState();
    if (widget.filePath != null) {
      _openFileFromPath();
    }
    textController.addListener(() {
      if (isAddingText) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    textController.dispose();
    textFocusNode.dispose();
    textOverlay?.remove();
    super.dispose();
  }

  List<AnnotationAction> undoStack = [];
  List<AnnotationAction> redoStack = [];
  static const int maxHistorySize =
      50; // Limit stack size to prevent memory issues

  void addToHistory(AnnotationAction action) {
    undoStack.add(action);
    if (undoStack.length > maxHistorySize) {
      undoStack.removeAt(0);
    }
    // Clear redo stack when new action is performed
    redoStack.clear();
    // Update UI to reflect undo/redo availability
    setState(() {});
  }

  void undo() {
    if (undoStack.isEmpty) return;

    final action = undoStack.removeLast();
    redoStack.add(action);

    setState(() {
      switch (action.type) {
        case ActionType.draw:
          // Restore previous state of drawings
          if (action.oldState != null) {
            pageDrawings[action.pageNumber] =
                List<DrawingPath>.from(action.oldState);
          } else {
            pageDrawings[action.pageNumber]?.removeLast();
          }
          break;

        case ActionType.erase:
          // Restore erased paths
          if (action.oldState != null) {
            pageDrawings[action.pageNumber] =
                List<DrawingPath>.from(action.oldState);
          }
          break;

        case ActionType.text:
          // Remove added text or restore modified text
          if (action.oldState != null) {
            pageTextAnnotations[action.pageNumber] =
                List<TextAnnotation>.from(action.oldState);
          } else {
            pageTextAnnotations[action.pageNumber]?.removeLast();
          }
          break;

        case ActionType.measure:
        case ActionType.box:
          // Remove measurement or restore previous state
          if (action.oldState != null) {
            pageDrawings[action.pageNumber] =
                List<DrawingPath>.from(action.oldState);
            pageTextAnnotations[action.pageNumber] =
                List<TextAnnotation>.from(action.oldState);
          } else {
            pageDrawings[action.pageNumber]?.removeLast();
            // Remove associated measurement text
            if (pageTextAnnotations[action.pageNumber]?.isNotEmpty ?? false) {
              pageTextAnnotations[action.pageNumber]?.removeLast();
            }
          }
          break;
      }
    });
  }

  void redo() {
    if (redoStack.isEmpty) return;

    final action = redoStack.removeLast();
    undoStack.add(action);

    setState(() {
      switch (action.type) {
        case ActionType.draw:
          // Restore the drawing
          if (!pageDrawings.containsKey(action.pageNumber)) {
            pageDrawings[action.pageNumber] = [];
          }
          if (action.newState is DrawingPath) {
            pageDrawings[action.pageNumber]!.add(action.newState);
          } else {
            pageDrawings[action.pageNumber] =
                List<DrawingPath>.from(action.newState);
          }
          break;

        case ActionType.erase:
          // Apply the erase action
          pageDrawings[action.pageNumber] =
              List<DrawingPath>.from(action.newState);
          break;

        case ActionType.text:
          // Restore the text
          if (!pageTextAnnotations.containsKey(action.pageNumber)) {
            pageTextAnnotations[action.pageNumber] = [];
          }
          if (action.newState is TextAnnotation) {
            pageTextAnnotations[action.pageNumber]!.add(action.newState);
          } else {
            pageTextAnnotations[action.pageNumber] =
                List<TextAnnotation>.from(action.newState);
          }
          break;

        case ActionType.measure:
        case ActionType.box:
          // Restore measurement or box
          if (!pageDrawings.containsKey(action.pageNumber)) {
            pageDrawings[action.pageNumber] = [];
          }
          pageDrawings[action.pageNumber] =
              List<DrawingPath>.from(action.newState);
          if (action.newState is Map) {
            pageTextAnnotations[action.pageNumber] =
                List<TextAnnotation>.from(action.newState['text']);
          }
          break;
      }
    });
  }

// Add bottom controls for text mode
  Widget _buildTextControls() {
    return Container(
      decoration: BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(color: Colors.black26, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // Font size dropdown
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              border: Border.all(color: Colors.grey),
              borderRadius: BorderRadius.circular(4),
            ),
            child: DropdownButton<double>(
              value: selectedFontSize,
              underline: const SizedBox(),
              items: fontSizes.map((double size) {
                return DropdownMenuItem<double>(
                  value: size,
                  child: Text('${size.toInt()}'),
                );
              }).toList(),
              onChanged: (double? newSize) {
                if (newSize != null) {
                  setState(() {
                    selectedFontSize = newSize;
                  });
                }
              },
            ),
          ),
          const SizedBox(width: 16),
          // Color picker
          Wrap(
            spacing: 8,
            children: [
              Colors.black,
              Colors.red,
              Colors.blue,
              Colors.green,
              Colors.orange,
            ]
                .map((color) => GestureDetector(
                      onTap: () {
                        setState(() {
                          currentColor = color;
                        });
                      },
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: color,
                          border: Border.all(
                            color: currentColor == color
                                ? Colors.white
                                : Colors.grey,
                            width: 2,
                          ),
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ))
                .toList(),
          ),
        ],
      ),
    );
  }

  void _handleTextAdd(Offset position) {
    final transformedPosition = _getTransformedOffset(position);
    setState(() {
      pendingTextPosition = transformedPosition;
      isTypingText = true;
      textController.clear();
    });

    textOverlay?.remove();
    textOverlay = OverlayEntry(
      builder: (context) => Positioned(
        left: (position.dx + offset.dx) * zoom,
        top: (position.dy + offset.dy) * zoom,
        child: CompositedTransformFollower(
          link: layerLink,
          offset: Offset(position.dx, position.dy),
          child: Material(
            color: Colors.transparent,
            child: Container(
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.8,
              ),
              child: IntrinsicWidth(
                child: TextField(
                  focusNode: textFocusNode,
                  controller: textController,
                  autofocus: true,
                  style: TextStyle(
                    fontSize: selectedFontSize * zoom,
                    color: currentColor,
                  ),
                  decoration: const InputDecoration(
                    border: InputBorder.none,
                    isDense: true,
                    contentPadding: EdgeInsets.zero,
                  ),
                  onSubmitted: (text) {
                    if (text.isNotEmpty && pendingTextPosition != null) {
                      if (!pageTextAnnotations.containsKey(currentPage)) {
                        pageTextAnnotations[currentPage] = [];
                      }

                      // Store the base font size without zoom factor
                      pageTextAnnotations[currentPage]!.add(TextAnnotation(
                        position: pendingTextPosition!,
                        text: text,
                        color: currentColor,
                        fontSize: selectedFontSize * zoom,
                      ));
                    }
                    _finishTextInput();
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );

    Overlay.of(context).insert(textOverlay!);
    textFocusNode.requestFocus();
  }

  void _finishTextInput() {
    textOverlay?.remove();
    textOverlay = null;
    setState(() {
      isTypingText = false;
      pendingTextPosition = null;
      textController.clear();
    });
  }

  void addPathToCurrentPage(DrawingPath path) {
    if (!pageDrawings.containsKey(currentPage)) {
      pageDrawings[currentPage] = [];
    }

    final oldState = pageDrawings[currentPage] != null
        ? List<DrawingPath>.from(pageDrawings[currentPage]!)
        : null;

    pageDrawings[currentPage]!.add(path);

    addToHistory(AnnotationAction(
      type: ActionType.draw,
      pageNumber: currentPage,
      oldState: oldState,
      newState: path,
    ));
  }

  Offset _getTransformedOffset(Offset screenOffset) {
    return (screenOffset - offset) / zoom;
  }

  Future<void> showSaveOptionsDialog(
    BuildContext context,
    String fileName,
    Function(bool createCopy) onOptionSelected,
  ) {
    return showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Save PDF'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                  'Would you like to replace the existing file or save a copy?'),
              const SizedBox(height: 8),
              Text(
                'File: $fileName',
                style: const TextStyle(fontSize: 12, color: Colors.grey),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onOptionSelected(false);
              },
              child: const Text('Replace'),
            ),
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                onOptionSelected(true);
              },
              child: const Text('Save Copy'),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Cancel'),
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white60,
      appBar: // First, add this widget below the existing action buttons in the AppBar:
          AppBar(
        leading: InkWell(
          onTap: widget.onCloseButtonAction,
          child: Container(
            padding: const EdgeInsets.only(
              left: 20,
            ),
            child: SvgPicture.asset('assets/close.svg'),
          ),
        ),
        centerTitle: false,
        title: InkWell(
            onTap: () {
              setState(() {
                if (mode == Mode.measure) {
                  mode = Mode.pan;
                } else {
                  mode = Mode.measure;
                }
              });
            },
            child: Text(
              mode == Mode.measure ? "Messen" : "Ausfüllen",
            )),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: primaryColor),
            onPressed: document != null
                ? _exportPdf
                : () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text("You need to open a file first"),
                      ),
                    );
                  },
            child: !isExporting
                ? const Text(
                    "Speichern",
                    style: TextStyle(
                      color: Colors.black,
                      fontWeight: ui.FontWeight.w500,
                      fontSize: 14,
                      fontFamily: 'Roboto',
                    ),
                  )
                : const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                    ),
                  ),
          ),
          const SizedBox(
            width: 10,
          )
        ],

        //     IconButton(
        //       icon: const Icon(Icons.save),
        //       onPressed: document != null ? _exportPdf : null,
        //     )
        //   else
        //     const SizedBox(
        //       width: 48,
        //       height: 48,
        //       child: Center(
        //         child: SizedBox(
        //           width: 24,
        //           height: 24,
        //           child: CircularProgressIndicator(
        //             strokeWidth: 2,
        //           ),
        //         ),
        //       ),
        //     ),
        // ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
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
                          CompositedTransformTarget(
                            link: layerLink,
                            child: Center(
                              child: currentPageImage == null
                                  ? const CircularProgressIndicator()
                                  : GestureDetector(
                                      onScaleStart: (details) {
                                        if (currentPageImage == null) return;

                                        final transformedOffset =
                                            _getTransformedOffset(
                                                details.localFocalPoint);
                                        if (!_isWithinPageBounds(
                                            transformedOffset)) return;

                                        if (mode == Mode.measure) {
                                          setState(() {
                                            if (measurementTool ==
                                                MeasurementTool.box) {
                                              boxStart = _getTransformedOffset(
                                                  details.localFocalPoint);
                                              currentBox = null;
                                            } else {
                                              if (measurementTool ==
                                                  MeasurementTool.scale) {
                                                pagePixelsPerMeter[
                                                    currentPage] = null;
                                              }
                                              lineStart = _getTransformedOffset(
                                                  details.localFocalPoint);
                                            }
                                          });
                                        }

                                        if (mode == Mode.text) {
                                          _handleTextAdd(
                                              details.localFocalPoint);
                                        } else if (mode == Mode.erase) {
                                          setState(() {
                                            _currentPointerPosition =
                                                details.localFocalPoint;
                                          });
                                          handleErase(details.localFocalPoint);
                                        } else if (mode == Mode.draw ||
                                            mode == Mode.highlight) {
                                          final baseStrokeWidth =
                                              mode == Mode.highlight
                                                  ? currentStrokeHighlight
                                                  : currentStrokePen;
                                          setState(() {
                                            currentPath = [
                                              DrawingPoint(
                                                transformedOffset,
                                                Paint()
                                                  ..color = mode ==
                                                          Mode.highlight
                                                      ? currentColorHighlight
                                                      : currentColor
                                                  ..strokeWidth =
                                                      baseStrokeWidth * zoom
                                                  ..strokeCap = StrokeCap.round
                                                  ..strokeJoin =
                                                      StrokeJoin.round
                                                  ..style = PaintingStyle.stroke
                                                  ..isAntiAlias = true,
                                                baseStrokeWidth,
                                              )
                                            ];
                                          });
                                        } else {
                                          previousZoom = zoom;
                                          previousOffset = offset;
                                        }
                                      },
                                      onScaleUpdate: (details) {
                                        if (currentPageImage == null) return;

                                        final transformedOffset =
                                            _getTransformedOffset(
                                                details.localFocalPoint);

                                        // Check if this is a zoom/pan gesture (scale != 1.0 or multiple pointers)
                                        bool isZoomOrPanGesture =
                                            details.scale != 1.0 ||
                                                details.pointerCount > 1;

                                        if (isZoomOrPanGesture) {
                                          setState(() {
                                            // Handle zoom
                                            if (details.scale != 1.0) {
                                              final newZoom = (previousZoom *
                                                      details.scale)
                                                  .clamp(0.2 / quality, 10.0);
                                              final focalPoint =
                                                  details.localFocalPoint;
                                              final double zoomFactor =
                                                  newZoom / zoom;
                                              final Offset normalizedOffset =
                                                  offset - focalPoint;
                                              final Offset scaledOffset =
                                                  normalizedOffset * zoomFactor;
                                              final Offset offsetDelta =
                                                  scaledOffset -
                                                      normalizedOffset;
                                              zoom = newZoom;
                                              offset = _constrainOffset(
                                                  offset + offsetDelta,
                                                  newZoom);
                                            } else {
                                              // Handle pan
                                              offset = _constrainOffset(
                                                  offset +
                                                      details.focalPointDelta,
                                                  zoom);
                                            }
                                          });
                                          return; // Exit early after handling zoom/pan
                                        }

                                        // If we get here, it's a drawing gesture

                                        // Check if the point is within page bounds for drawing operations
                                        if (!_isWithinPageBounds(
                                                transformedOffset) &&
                                            mode != Mode.pan) return;

                                        if (mode == Mode.measure &&
                                            lineStart != null) {
                                          setState(() {
                                            _currentPointerPosition =
                                                _getTransformedOffset(
                                                    details.localFocalPoint);
                                          });
                                        } else if (mode == Mode.measure &&
                                            boxStart != null) {
                                          setState(() {
                                            final currentPoint =
                                                _getTransformedOffset(
                                                    details.localFocalPoint);
                                            currentBox = Rect.fromPoints(
                                                boxStart!, currentPoint);
                                          });
                                        } else if (isDraggingText &&
                                            selectedAnnotation != null) {
                                          final newPosition =
                                              _getTransformedOffset(
                                                      details.localFocalPoint) -
                                                  dragOffset!;
                                          setState(() {
                                            final annotations =
                                                pageTextAnnotations[
                                                    currentPage]!;
                                            final index = annotations
                                                .indexOf(selectedAnnotation!);
                                            annotations[index] =
                                                selectedAnnotation!.copyWith(
                                                    position: newPosition);
                                            selectedAnnotation =
                                                annotations[index];
                                          });
                                        } else if (mode == Mode.erase) {
                                          setState(() {
                                            _currentPointerPosition =
                                                details.localFocalPoint;
                                          });
                                          handleErase(details.localFocalPoint);
                                        } else if ((mode == Mode.draw ||
                                            mode == Mode.highlight)) {
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
                                                  ..color = mode ==
                                                          Mode.highlight
                                                      ? currentColorHighlight
                                                      : currentColor
                                                  ..strokeWidth =
                                                      baseStrokeWidth * zoom
                                                  ..strokeCap = StrokeCap.round
                                                  ..strokeJoin =
                                                      StrokeJoin.round
                                                  ..style = PaintingStyle.stroke
                                                  ..isAntiAlias = true,
                                                baseStrokeWidth,
                                              ),
                                            );
                                            setState(() {});
                                          }
                                        }
                                      },
                                      onScaleEnd: (details) {
                                        if (mode == Mode.erase) {
                                          setState(() {
                                            _currentPointerPosition = null;
                                          });
                                        }
                                        if (mode == Mode.measure &&
                                            boxStart != null &&
                                            currentBox != null) {
                                          if (measurementTool ==
                                              MeasurementTool.box) {
                                            if (pixelsPerMeter != null) {
                                              // Only allow box drawing if we have a reference scale
                                              // Create and add the box path
                                              final measurementPath =
                                                  _createBoxPath(
                                                      currentBox!,
                                                      measurementTool ==
                                                              MeasurementTool
                                                                  .measure
                                                          ? currentMeasurementLineColor
                                                          : measurementTool ==
                                                                  MeasurementTool
                                                                      .box
                                                              ? currentMeasurementBoxColor
                                                              : Colors.black,
                                                      MeasurementTool.scale ==
                                                              measurementTool
                                                          ? currentMeasurementLineStroke
                                                          : MeasurementTool
                                                                      .box ==
                                                                  measurementTool
                                                              ? currentMeasurementBoxStroke
                                                              : 3.0);

                                              setState(() {
                                                addPathToCurrentPage(
                                                    measurementPath);
                                                // Add measurements for both sides and area
                                                _addBoxMeasurements(currentBox!,
                                                    measurementPath);
                                              });
                                            } else {
                                              ScaffoldMessenger.of(context)
                                                  .showSnackBar(
                                                const SnackBar(
                                                  content: Text(
                                                      'Please set a reference scale first'),
                                                ),
                                              );
                                            }
                                          }

                                          setState(() {
                                            boxStart = null;
                                            currentBox = null;
                                          });
                                        }

                                        if (mode == Mode.measure &&
                                            lineStart != null &&
                                            _currentPointerPosition != null) {
                                          final currentLineLength =
                                              (lineStart! -
                                                      _currentPointerPosition!)
                                                  .distance;
                                          if (measurementTool ==
                                              MeasurementTool.scale) {
                                            // Remove previous reference line if it exists
                                            if (pageReferenceLines[
                                                    currentPage] !=
                                                null) {
                                              setState(() {
                                                // Remove the old reference line and text
                                                final index =
                                                    pageDrawings[currentPage]
                                                        ?.indexOf(
                                                            pageReferenceLines[
                                                                currentPage]!);
                                                if (index != null &&
                                                    index != -1) {
                                                  pageDrawings[currentPage]
                                                      ?.removeAt(index);
                                                }

                                                if (pageReferenceTexts[
                                                        currentPage] !=
                                                    null) {
                                                  pageTextAnnotations[
                                                          currentPage]
                                                      ?.remove(
                                                          pageReferenceTexts[
                                                              currentPage]);
                                                }
                                              });
                                            }

                                            // Add new reference line
                                            setState(() {
                                              // Replace this entire block with your new code
                                              pageReferenceLines[currentPage] =
                                                  DrawingPath(
                                                [
                                                  DrawingPoint(
                                                    lineStart!,
                                                    Paint()
                                                      ..color =
                                                          currentMeasurementColor
                                                      ..strokeWidth =
                                                          currentMeasurementStroke *
                                                              4
                                                      ..strokeCap =
                                                          StrokeCap.round
                                                      ..style =
                                                          PaintingStyle.fill
                                                      ..isAntiAlias = true,
                                                    currentMeasurementStroke *
                                                        4,
                                                  ),
                                                  DrawingPoint(
                                                    _currentPointerPosition!,
                                                    Paint()
                                                      ..color =
                                                          currentMeasurementColor
                                                      ..strokeWidth =
                                                          currentMeasurementStroke *
                                                              4
                                                      ..strokeCap =
                                                          StrokeCap.round
                                                      ..style =
                                                          PaintingStyle.fill
                                                      ..isAntiAlias = true,
                                                    currentMeasurementStroke *
                                                        4,
                                                  ),
                                                ],
                                                Paint()
                                                  ..color =
                                                      currentMeasurementColor
                                                  ..strokeWidth =
                                                      currentMeasurementStroke
                                                  ..strokeCap = StrokeCap.round
                                                  ..isAntiAlias = true,
                                                currentMeasurementStroke,
                                                pathType: Mode.measure,
                                                isDashed: true,
                                                dashPattern: [8.0, 4.0],
                                                measurementTool:
                                                    measurementTool,
                                              );

                                              addPathToCurrentPage(
                                                  pageReferenceLines[
                                                      currentPage]!);
                                              pageLineLengths[currentPage] =
                                                  currentLineLength;
                                              lineStart = null;
                                              _currentPointerPosition = null;
                                            });

                                            // Request focus for the reference input after a short delay
                                            Future.delayed(
                                                const Duration(
                                                    milliseconds: 100), () {
                                              if (mounted) {
                                                _referenceController.clear();
                                                _referenceFocusNode
                                                    .requestFocus();
                                              }
                                            });
                                          } else if (measurementTool ==
                                                  MeasurementTool.measure &&
                                              pixelsPerMeter != null) {
                                            // Handle measurement lines
                                            final measurementInMeters =
                                                currentLineLength /
                                                    pixelsPerMeter!;
                                            setState(() {
                                              // Add the measurement line
                                              final measurementLine =
                                                  DrawingPath(
                                                [
                                                  DrawingPoint(
                                                    lineStart!,
                                                    Paint()
                                                      ..color = measurementTool ==
                                                              MeasurementTool
                                                                  .measure
                                                          ? currentMeasurementLineColor
                                                          : measurementTool ==
                                                                  MeasurementTool
                                                                      .box
                                                              ? currentMeasurementBoxColor
                                                              : Colors.black
                                                      ..strokeWidth = MeasurementTool
                                                                  .measure ==
                                                              measurementTool
                                                          ? currentMeasurementLineStroke
                                                          : MeasurementTool
                                                                      .box ==
                                                                  measurementTool
                                                              ? currentMeasurementBoxStroke
                                                              : 3.0
                                                      ..strokeCap =
                                                          StrokeCap.round
                                                      ..isAntiAlias = true,
                                                    MeasurementTool.measure ==
                                                            measurementTool
                                                        ? currentMeasurementLineStroke
                                                        : MeasurementTool.box ==
                                                                measurementTool
                                                            ? currentMeasurementBoxStroke
                                                            : 3.0,
                                                  ),
                                                  DrawingPoint(
                                                    _currentPointerPosition!,
                                                    Paint()
                                                      ..color = measurementTool ==
                                                              MeasurementTool
                                                                  .measure
                                                          ? currentMeasurementLineColor
                                                          : measurementTool ==
                                                                  MeasurementTool
                                                                      .box
                                                              ? currentMeasurementBoxColor
                                                              : Colors.black
                                                      ..strokeWidth = MeasurementTool
                                                                  .measure ==
                                                              measurementTool
                                                          ? currentMeasurementLineStroke
                                                          : MeasurementTool
                                                                      .box ==
                                                                  measurementTool
                                                              ? currentMeasurementBoxStroke
                                                              : 3.0
                                                      ..strokeCap =
                                                          StrokeCap.round
                                                      ..isAntiAlias = true,
                                                    MeasurementTool.measure ==
                                                            measurementTool
                                                        ? currentMeasurementLineStroke
                                                        : MeasurementTool.box ==
                                                                measurementTool
                                                            ? currentMeasurementBoxStroke
                                                            : 3.0,
                                                  ),
                                                ],
                                                Paint()
                                                  ..color = measurementTool ==
                                                          MeasurementTool
                                                              .measure
                                                      ? currentMeasurementLineColor
                                                      : measurementTool ==
                                                              MeasurementTool
                                                                  .box
                                                          ? currentMeasurementBoxColor
                                                          : Colors.black
                                                  ..strokeWidth = MeasurementTool
                                                              .measure ==
                                                          measurementTool
                                                      ? currentMeasurementLineStroke
                                                      : MeasurementTool.box ==
                                                              measurementTool
                                                          ? currentMeasurementBoxStroke
                                                          : 3.0
                                                  ..strokeCap = StrokeCap.round
                                                  ..isAntiAlias = true,
                                                MeasurementTool.measure ==
                                                        measurementTool
                                                    ? currentMeasurementLineStroke
                                                    : MeasurementTool.box ==
                                                            measurementTool
                                                        ? currentMeasurementBoxStroke
                                                        : 3.0,
                                                pathType: Mode.measure,
                                              );

                                              addPathToCurrentPage(
                                                  measurementLine);

                                              // Add measurement text
                                              final midPoint = (lineStart! +
                                                      _currentPointerPosition!) /
                                                  2;
                                              final lineVector =
                                                  _currentPointerPosition! -
                                                      lineStart!;
                                              final normalizedVector = Offset(
                                                -lineVector.dy,
                                                lineVector.dx,
                                              ).normalized();

                                              final textOffset = midPoint +
                                                  (normalizedVector * 20.0);

                                              if (!pageTextAnnotations
                                                  .containsKey(currentPage)) {
                                                pageTextAnnotations[
                                                    currentPage] = [];
                                              }

                                              pageTextAnnotations[currentPage]!
                                                  .add(TextAnnotation(
                                                position: textOffset,
                                                text:
                                                    '${measurementInMeters.toStringAsFixed(2)} m',
                                                fontSize: 14.0 * quality,
                                                color: Colors.black,
                                                fontFamily: 'Roboto',
                                              ));

                                              lineStart = null;
                                              _currentPointerPosition = null;
                                            });
                                          }
                                        }

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
                                          mode: mode,
                                          currentPointerPosition:
                                              _currentPointerPosition,
                                          eraserSize: currentEraserSize,
                                          textAnnotations:
                                              currentPageTextAnnotations,
                                          quality: quality,
                                          lineStart: lineStart,
                                          pixelsPerMeter: pixelsPerMeter,
                                          initialLineLength: initialLineLength,
                                          currentBox: currentBox,
                                        ),
                                        size: Size(
                                          currentPageImage!.width.toDouble(),
                                          currentPageImage!.height.toDouble(),
                                        ),
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
          if (mode == Mode.text) _buildTextControls(),
          if (document != null &&
              (mode == Mode.draw ||
                  mode == Mode.erase ||
                  mode == Mode.highlight))
            Container(
              decoration: const BoxDecoration(
                color: backgroundColor,
                border: Border(
                  bottom: BorderSide(
                    color: Colors.black26,
                    width: 0.5,
                  ),
                ),
              ),
              child: Slider(
                thumbColor: primaryColor,
                activeColor: primaryColor,
                value: mode == Mode.draw
                    ? currentStrokePen
                    : mode == Mode.erase
                        ? currentEraserSize
                        : currentStrokeHighlight,
                min: 12.0,
                max: mode == Mode.highlight ? 480.0 : 120.0,
                label: mode == Mode.draw
                    ? currentStrokePen.round().toString()
                    : mode == Mode.erase
                        ? currentEraserSize.round().toString()
                        : currentStrokeHighlight.round().toString(),
                onChanged: (value) {
                  setState(() {
                    if (mode == Mode.erase) {
                      currentEraserSize = value;
                    } else if (mode == Mode.draw) {
                      currentStrokePen = value;
                    } else if (mode == Mode.highlight) {
                      currentStrokeHighlight = value;
                    } else {}
                  });
                },
              ),
            ),
          if (document != null && mode != Mode.measure)
            Container(
              color: backgroundColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  CustomButton(
                    svgAsset: 'assets/draw.svg',
                    onTap: () {
                      setState(() {
                        mode = Mode.draw;
                      });
                    },
                    isActive: mode == Mode.draw,
                  ),
                  CustomButton(
                    svgAsset: 'assets/erase.svg',
                    onTap: () {
                      setState(() {
                        mode = Mode.erase;
                      });
                    },
                    isActive: mode == Mode.erase,
                  ),
                  CustomButton(
                    width: 20,
                    height: 20,
                    svgAsset: 'assets/text.svg',
                    onTap: () {
                      setState(() {
                        mode = Mode.text;
                      });
                    },
                    isActive: mode == Mode.text,
                  ),
                  CustomButton(
                    svgAsset: 'assets/highlight.svg',
                    onTap: () {
                      setState(() {
                        mode = Mode.highlight;
                      });
                    },
                    isActive: mode == Mode.highlight,
                  ),
                  CustomButton(
                    customIcon: const Icon(
                      Icons.back_hand_outlined,
                      size: 18,
                    ),
                    onTap: () {
                      setState(() {
                        mode = Mode.pan;
                      });
                    },
                    isActive: mode == Mode.pan,
                    svgAsset: '',
                  ),
                ],
              ),
            ),
          if (document != null && mode == Mode.measure)
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 200,
                  color: backgroundColor,
                  padding: const EdgeInsets.all(8.0),
                  child: TextFormField(
                    controller: _referenceController,
                    focusNode: _referenceFocusNode,
                    decoration: const InputDecoration(
                      labelText: "Referenzewert",
                      suffixText: "Meter",
                      focusedBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black)),
                      labelStyle: TextStyle(color: Colors.black),
                      border: OutlineInputBorder(
                          borderSide: BorderSide(color: Colors.black)),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    ),
                    keyboardType:
                        TextInputType.numberWithOptions(decimal: true),
                    onFieldSubmitted: (value) {
                      final referenceValue = double.tryParse(value);
                      if (referenceValue != null &&
                          pageLineLengths[currentPage] != null) {
                        setState(() {
                          initialLineLength = pageLineLengths[currentPage];
                          pagePixelsPerMeter[currentPage] =
                              pageLineLengths[currentPage]! / referenceValue;
                          pageLineLengths[currentPage] = null;

                          // Add reference measurement text
                          if (pageReferenceLines[currentPage] != null) {
                            final points =
                                pageReferenceLines[currentPage]!.points;
                            final midPoint =
                                (points[0].point + points[1].point) / 2;
                            final lineVector =
                                points[1].point - points[0].point;
                            final normalizedVector =
                                Offset(-lineVector.dy, lineVector.dx)
                                    .normalized();
                            final textOffset =
                                midPoint + (normalizedVector * 20.0);

                            pageReferenceTexts[currentPage] = TextAnnotation(
                              position: textOffset,
                              text: '$referenceValue m (reference)',
                              fontSize: 12.0 * quality,
                              color: currentMeasurementColor,
                              fontFamily: 'Roboto',
                            );

                            if (!pageTextAnnotations.containsKey(currentPage)) {
                              pageTextAnnotations[currentPage] = [];
                            }
                            pageTextAnnotations[currentPage]!
                                .add(pageReferenceTexts[currentPage]!);
                          }
                        });
                      }
                    },
                  ),
                ),
                _buildMeasurementControls()
              ],
            ),
          if (document != null && mode == Mode.measure)
            Container(
              color: backgroundColor,
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      CustomButton(
                        svgAsset: 'assets/undo.svg',
                        onTap: undoStack.isEmpty ? null : undo,
                        isActive: false,
                      ),
                      CustomButton(
                        svgAsset: 'assets/redo.svg',
                        onTap: redoStack.isEmpty ? null : redo,
                        isActive: false,
                      ),
                    ],
                  ),
                  Row(
                    children: [
                      CustomButton(
                        svgAsset: 'assets/scale.svg',
                        onTap: () {
                          setState(() {
                            measurementTool = MeasurementTool.scale;
                            mode = Mode.measure;
                          });
                        },
                        isActive: measurementTool == MeasurementTool.scale,
                      ),
                      CustomButton(
                        svgAsset: 'assets/measure.svg',
                        onTap: () {
                          if (referenceLine != null) {
                            setState(() {
                              measurementTool = MeasurementTool.measure;
                              mode = Mode.measure;
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Please draw a reference line first'),
                              ),
                            );
                          }
                        },
                        isActive: measurementTool == MeasurementTool.measure,
                      ),
                      CustomButton(
                        customIcon: const Icon(Icons.crop_square, size: 24),
                        onTap: () {
                          if (pixelsPerMeter != null) {
                            setState(() {
                              measurementTool = MeasurementTool.box;
                              mode = Mode.measure;
                            });
                          } else {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content:
                                    Text('Please set a reference scale first'),
                              ),
                            );
                          }
                        },
                        isActive: measurementTool == MeasurementTool.box,
                        svgAsset: '',
                      ),
                    ],
                  ),
                ],
              ),
            ),
          if (document != null)
            Container(
              padding: const EdgeInsets.only(
                bottom: 16,
                top: 10,
              ),
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

  Widget _buildMeasurementControls() {
    return Container(
      decoration: const BoxDecoration(
        color: backgroundColor,
        border: Border(
          bottom: BorderSide(color: Colors.black26, width: 0.5),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Column(
        children: [
          // Color picker row
          Row(
            children: [
              const Text('Line Color: ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              const SizedBox(width: 8),
              Wrap(
                spacing: 8,
                children: [
                  Colors.blue,
                  Colors.red,
                  Colors.black,
                  Colors.green,
                  Colors.orange,
                ]
                    .map((color) => GestureDetector(
                          onTap: () {
                            setState(() {
                              if (MeasurementTool.scale == measurementTool) {
                                currentMeasurementColor = color;
                              } else if (MeasurementTool.measure ==
                                  measurementTool) {
                                currentMeasurementLineColor = color;
                              } else if (MeasurementTool.box ==
                                  measurementTool) {
                                currentMeasurementBoxColor = color;
                              }
                            });
                          },
                          child: Container(
                            width: 24,
                            height: 24,
                            decoration: BoxDecoration(
                              color: color,
                              border: Border.all(
                                color: MeasurementTool.scale == measurementTool
                                    ? currentMeasurementColor == color
                                        ? Colors.white
                                        : Colors.grey
                                    : MeasurementTool.measure == measurementTool
                                        ? currentMeasurementLineColor == color
                                            ? Colors.white
                                            : Colors.grey
                                        : MeasurementTool.box == measurementTool
                                            ? currentMeasurementBoxColor ==
                                                    color
                                                ? Colors.white
                                                : Colors.grey
                                            : Colors.white,
                                width: 2,
                              ),
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ))
                    .toList(),
              ),
            ],
          ),
          const SizedBox(height: 8),
          // Stroke width slider
          Row(
            children: [
              const Text('Line Width: ',
                  style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500)),
              Expanded(
                child: Slider(
                  thumbColor: primaryColor,
                  activeColor: primaryColor,
                  value: MeasurementTool.scale == measurementTool
                      ? currentMeasurementStroke
                      : MeasurementTool.measure == measurementTool
                          ? currentMeasurementLineStroke
                          : MeasurementTool.box == measurementTool
                              ? currentMeasurementBoxStroke
                              : 10,
                  min: 5.0,
                  max: 100.0,
                  onChanged: (value) {
                    setState(() {
                      if (MeasurementTool.scale == measurementTool) {
                        currentMeasurementStroke = value;
                      } else if (MeasurementTool.measure == measurementTool) {
                        currentMeasurementLineStroke = value;
                      } else if (MeasurementTool.box == measurementTool) {
                        currentMeasurementBoxStroke = value;
                      }
                    });
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  void _updateReferenceInput() {
    if (pageReferenceTexts[currentPage] != null) {
      // Extract the reference value from the text
      // Example text format: "5 m (reference)"
      final text = pageReferenceTexts[currentPage]!.text;
      final value = text.split(' ')[0]; // Get the first part (number)
      _referenceController.text = value;
    } else {
      _referenceController.clear();
      // Reset measurement tool to scale if no reference exists
      if (measurementTool != MeasurementTool.scale) {
        setState(() {
          measurementTool = MeasurementTool.scale;
        });
      }
    }
  }

  void _addBoxMeasurements(Rect box, DrawingPath path) {
    if (pixelsPerMeter == null) return;

    // Calculate width and height in meters
    final width = box.width.abs() / pixelsPerMeter!;
    final height = box.height.abs() / pixelsPerMeter!;

    if (!pageTextAnnotations.containsKey(currentPage)) {
      pageTextAnnotations[currentPage] = [];
    }

    // Add width measurement (horizontal side)
    final horizontalMidpoint = Offset(
      box.left + box.width / 2,
      box.bottom + 20.0, // Offset below the box
    );

    pageTextAnnotations[currentPage]!.add(TextAnnotation(
      position: horizontalMidpoint,
      text: '${width.toStringAsFixed(2)} m',
      fontSize: 14.0 * quality,
      color: Colors.black,
      fontFamily: 'Roboto',
    ));

    // Add height measurement (vertical side)
    final verticalMidpoint = Offset(
      box.right + 20.0, // Offset to the right of the box
      box.top + box.height / 2,
    );

    pageTextAnnotations[currentPage]!.add(TextAnnotation(
      position: verticalMidpoint,
      text: '${height.toStringAsFixed(2)} m',
      fontSize: 14.0 * quality,
      color: Colors.black,
      fontFamily: 'Roboto',
    ));

    // Add area measurement in the center
    final areaMidpoint = Offset(
      box.left + box.width / 2,
      box.top + box.height / 2,
    );

    final area = width * height;
    pageTextAnnotations[currentPage]!.add(TextAnnotation(
      position: areaMidpoint,
      text: '${area.toStringAsFixed(2)} m²',
      fontSize: 14.0 * quality,
      color: Colors.black,
      fontFamily: 'Roboto',
    ));
  }

  DrawingPath _createBoxPath(Rect box, Color color, double strokeSize) {
    return DrawingPath(
      [
        DrawingPoint(box.topLeft, _createPaint(color, strokeSize), strokeSize),
        DrawingPoint(box.topRight, _createPaint(color, strokeSize), strokeSize),
        DrawingPoint(
            box.bottomRight, _createPaint(color, strokeSize), strokeSize),
        DrawingPoint(
            box.bottomLeft, _createPaint(color, strokeSize), strokeSize),
        DrawingPoint(box.topLeft, _createPaint(color, strokeSize),
            strokeSize), // // Close the box
      ],
      _createPaint(color, strokeSize),
      strokeSize,
      pathType: Mode.box, // Add a new Mode.box type
    );
  }

  Paint _createPaint(Color color, double strokeSize) {
    return Paint()
      ..color = color
      ..strokeWidth = strokeSize
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke
      ..isAntiAlias = true;
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

    // Calculate base zoom without quality factor
    final baseZoom = math.min(horizontalRatio, verticalRatio);

    // Apply a zoom multiplier to make the content more readable
    // while maintaining high quality rendering
    return baseZoom * 1.2; // Adjust this multiplier as needed
  }

  // double _calculateInitialZoom(BuildContext context, Size imageSize) {
  //   if (currentPageImage == null) return 1.0;

  //   final screenSize = MediaQuery.of(context).size;
  //   final containerSize = Size(
  //     screenSize.width,
  //     screenSize.height - kToolbarHeight - 80,
  //   );

  //   final double horizontalRatio = containerSize.width / imageSize.width;
  //   final double verticalRatio = containerSize.height / imageSize.height;

  //   // Changed to allow the initial zoom to be larger than 1.0 if needed
  //   return math.min(horizontalRatio, verticalRatio) / quality;
  // }

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

      if (widget.exportToStorage == true) {
        final originalFileName = path.basename(currentFilePath!);

        // await showSaveOptionsDialog(
        //   context,
        //   originalFileName,
        //   (createCopy) async {
        try {
          String targetPath;
          // if (createCopy) {
          //   // Generate unique path for copy in the same directory as original
          //   targetPath = await PdfStorageHandler.generateUniqueFilePath(
          //       currentFilePath!);
          // } else {
          // Use original file path for replacement
          targetPath = currentFilePath!;
          // }

          // Create export data with the temporary path
          final exportData = PdfExportData(
            pageImages: pageImages,
            pageDrawings: pageDrawings,
            outputPath: newPath,
            pageWidth: firstPage.width,
            pageHeight: firstPage.height,
            originalWidth: originalWidth!,
            pageCount: document!.pageCount,
            pageTextAnnotations: pageTextAnnotations,
          );

          // Get root isolate token
          final rootIsolateToken = RootIsolateToken.instance!;

          // Create and run isolate to generate PDF
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
            try {
              // For replacement, use the isolated replacement method
              final resultPath = await PdfStorageHandler.replacePdfInIsolate(
                  newPath, targetPath);

              await OpenFile.open(resultPath);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Original PDF replaced successfully'),
                  ),
                );
              }
            } catch (e) {
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Error replacing file: $e')),
                );
              }
            }
          } else {
            throw Exception(result);
          }
        } catch (e, st) {
          log("$e, $st");
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Error saving PDF: $e'),
                // duration: Duration(hours: 1),
              ),
            );
          }
        } finally {
          // Clean up temporary file
          try {
            final tempFile = File(newPath);
            if (await tempFile.exists()) {
              await tempFile.delete();
            }
          } catch (e) {
            print('Error cleaning up temporary file: $e');
          }
        }
        // },
        // );
      } else {
        // Create export data
        final exportData = PdfExportData(
          pageImages: pageImages,
          pageDrawings: pageDrawings,
          outputPath: newPath,
          pageWidth: firstPage.width,
          pageHeight: firstPage.height,
          originalWidth: originalWidth,
          pageCount: document!.pageCount,
          pageTextAnnotations: pageTextAnnotations, // Add this line
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
        } else {
          log(result);
          // throw Exception(result.substring(7));
        }
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

  Future<void> _openFileFromPath() async {
    try {
      setState(() {
        isLoading = true;
        currentPage = 0;
        currentPageImage = null;
      });

      // Since we already have the file path in widget.filePath
      document?.dispose();
      final file = File(widget.filePath!);
      currentFilePath = file.path;

      document = await pr.PdfDocument.openFile(file.path);
      totalPages = document!.pageCount;
      await _loadPage(0);
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
      log("[Log] Loaded PDF File: $currentFilePath");
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
          final imageSize = Size(
            image.width.toDouble(),
            image.height.toDouble(),
          );
          zoom = _calculateInitialZoom(context, imageSize);
          previousZoom = zoom;
          offset = Offset.zero;
          previousOffset = Offset.zero;
          currentPath = [];
        });

        // Update reference input when page changes
        _updateReferenceInput();
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

  bool _isWithinPageBounds(Offset point) {
    if (currentPageImage == null) return false;

    final pageWidth = currentPageImage!.width.toDouble();
    final pageHeight = currentPageImage!.height.toDouble();

    return point.dx >= 0 &&
        point.dx <= pageWidth &&
        point.dy >= 0 &&
        point.dy <= pageHeight;
  }
}

class PdfPainter extends CustomPainter {
  final ui.Image image;
  final double zoom;
  final Offset offset;
  final List<DrawingPath> paths;
  final List<DrawingPoint> currentPath;
  final Mode mode;
  final Offset? eraserPosition;
  final double eraserSize;
  final Offset? currentPointerPosition;
  final List<TextAnnotation> textAnnotations;
  final double quality;
  final Offset? lineStart;
  final double? initialLineLength;
  final double? pixelsPerMeter;
  Rect? currentBox;

  PdfPainter(
    this.image,
    this.zoom,
    this.offset,
    this.paths,
    this.currentPath, {
    this.mode = Mode.draw,
    this.eraserPosition,
    this.eraserSize = 20.0,
    this.currentPointerPosition,
    this.textAnnotations = const [],
    this.quality = 4.0,
    this.lineStart,
    this.initialLineLength,
    this.pixelsPerMeter,
    this.currentBox,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final Rect clipRect = Offset.zero & size;
    canvas.clipRect(clipRect);

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

    // Draw paths with anti-aliasing
    canvas.saveLayer(null, Paint()..isAntiAlias = true);
    Path createDashedPath(Path path, double dashLength, double gapLength) {
      Path dashedPath = Path();
      for (ui.PathMetric pathMetric in path.computeMetrics()) {
        double distance = 0.0;
        while (distance < pathMetric.length) {
          final double nextDistance = distance + dashLength;
          dashedPath.addPath(
            pathMetric.extractPath(distance, nextDistance),
            Offset.zero,
          );
          distance = nextDistance + gapLength;
        }
      }
      return dashedPath;
    }

    void drawStartAndEndDots(
        Canvas canvas, List<Offset> points, Paint paint, double radius) {
      Paint dotPaint = Paint()
        ..color = paint.color
        ..style = PaintingStyle.fill
        ..isAntiAlias = true;

      canvas.drawCircle(points.first, radius, dotPaint);
      canvas.drawCircle(points.last, radius, dotPaint);
    }

    // Draw completed paths
    for (final path in paths) {
      if (path.pathType == Mode.measure) {
        if (path.measurementTool == MeasurementTool.scale) {
          // Create a paint for dotted dashed line
          Paint dottedDashedPaint = Paint()
            ..color = path.paint.color
            ..strokeWidth = path.paint.strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;

          // Create a path for the line
          Path linePath = Path();
          linePath.moveTo(path.points[0].point.dx, path.points[0].point.dy);
          for (int i = 1; i < path.points.length; i++) {
            linePath.lineTo(path.points[i].point.dx, path.points[i].point.dy);
          }

          // Create a dashed path
          Path dashedPath = createDashedPath(
              linePath, 10.0, 30.0); // Adjust dash and gap lengths as needed
          canvas.drawPath(dashedPath, dottedDashedPaint);

          // Draw big filled dots at start and end points
          drawStartAndEndDots(canvas, path.points.map((p) => p.point).toList(),
              path.paint, 30.0); // Adjust the size as needed
        } else {
          // Create a paint for dotted dashed line
          Paint dottedDashedPaint = Paint()
            ..color = path.paint.color
            ..strokeWidth = path.paint.strokeWidth
            ..style = PaintingStyle.stroke
            ..strokeCap = StrokeCap.round
            ..isAntiAlias = true;

          // Create a path for the line
          Path linePath = Path();
          linePath.moveTo(path.points[0].point.dx, path.points[0].point.dy);
          linePath.lineTo(path.points[1].point.dx, path.points[1].point.dy);

          // Create a dashed path
          Path dashedPath = createDashedPath(
              linePath, 10.0, 30.0); // Adjust dash and gap lengths as needed
          canvas.drawPath(dashedPath, dottedDashedPaint);

          // Draw big filled dots at start and end points
          drawStartAndEndDots(
              canvas,
              [path.points[0].point, path.points[1].point],
              path.paint,
              30.0); // Adjust the size as needed
        }
      } else {
        canvas.drawPath(
          path.createSmoothPath(zoom),
          path.paint..isAntiAlias = true,
        );
      }
    }
    if (mode == Mode.measure && currentBox != null) {
      final boxPaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 2.0
        ..style = PaintingStyle.stroke;
      canvas.drawRect(currentBox!, boxPaint);

      // Show live measurements if we have a scale
      if (pixelsPerMeter != null) {
        final width = currentBox!.width.abs() / pixelsPerMeter!;
        final height = currentBox!.height.abs() / pixelsPerMeter!;
        final area = width * height;

        // Width measurement
        final widthText = '${width.toStringAsFixed(2)} m';
        final heightText = '${height.toStringAsFixed(2)} m';
        final areaText = '${area.toStringAsFixed(2)} m²';

        _drawMeasurementText(
            canvas,
            widthText,
            Offset(currentBox!.left + currentBox!.width / 2,
                currentBox!.bottom + 20));
        _drawMeasurementText(
            canvas,
            heightText,
            Offset(currentBox!.right + 20,
                currentBox!.top + currentBox!.height / 2));
        _drawMeasurementText(
            canvas,
            areaText,
            Offset(currentBox!.left + currentBox!.width / 2,
                currentBox!.top + currentBox!.height / 2));
      }
    }

    // Draw current path
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

    // Draw eraser preview when in erase mode
    if (mode == Mode.erase && currentPointerPosition != null) {
      final eraserPaint = Paint()
        ..style = PaintingStyle.stroke
        ..color = Colors.red
        ..strokeWidth = 2 / zoom;

      final eraserCirclePaint = Paint()
        ..style = PaintingStyle.fill
        ..color = Colors.red.withOpacity(0.1);

      final transformedPosition = (currentPointerPosition! - offset) / zoom;

      // Draw filled circle with low opacity
      canvas.drawCircle(
        transformedPosition,
        eraserSize / (2 * zoom),
        eraserCirclePaint,
      );

      // Draw circle outline
      canvas.drawCircle(
        transformedPosition,
        eraserSize / (2 * zoom),
        eraserPaint,
      );
    }

    // Draw text annotations with proper scaling and clipping
    if (mode == Mode.measure &&
        lineStart != null &&
        currentPointerPosition != null) {
      final linePaint = Paint()
        ..color = Colors.black
        ..strokeWidth = 3.0
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..isAntiAlias = true;

      canvas.drawLine(lineStart!, currentPointerPosition!, linePaint);

      if (pixelsPerMeter != null) {
        final distanceInPixels =
            (lineStart! - currentPointerPosition!).distance;
        final lengthInMeters = distanceInPixels / pixelsPerMeter!;
        final textSpan = TextSpan(
          text: '${lengthInMeters.toStringAsFixed(2)} meters',
          style: TextStyle(color: Colors.black, fontSize: 50),
        );
        final textPainter = TextPainter(
          text: textSpan,
          textDirection: TextDirection.ltr,
        );
        textPainter.layout();
        final textOffset =
            (lineStart! + currentPointerPosition!) / 2 - Offset(0, 10);
        textPainter.paint(canvas, textOffset);
      }
    }
    for (final annotation in textAnnotations) {
      final textSpan = TextSpan(
        text: annotation.text,
        style: TextStyle(
          color: annotation.color,
          fontSize: annotation.fontSize,
          fontFamily: annotation.fontFamily,
        ),
      );

      final textPainter = TextPainter(
        text: textSpan,
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.left,
        maxLines: 1, // Prevent text wrapping
      );

      // Layout with unlimited width to prevent wrapping
      textPainter.layout(minWidth: 0, maxWidth: double.infinity);

      // Calculate the actual position in canvas coordinates
      final position = annotation.position;

      if (annotation.isSelected) {
        final rect = Rect.fromLTWH(
          position.dx,
          position.dy,
          textPainter.width / quality,
          textPainter.height / quality,
        );

        canvas.drawRect(
          rect,
          Paint()
            ..style = PaintingStyle.stroke
            ..color = Colors.blue
            ..strokeWidth = 1.0 / zoom,
        );
      }

      // Save canvas state before applying clip
      canvas.save();

      // Create a clip rect for the text bounds
      final textBounds = Rect.fromLTWH(
        position.dx,
        position.dy,
        textPainter.width / quality,
        textPainter.height / quality,
      );

      // Paint the text
      textPainter.paint(canvas, position);

      // Restore canvas state
      canvas.restore();
    }

    canvas.restore();
    canvas.restore();
  }

  void _drawMeasurementText(Canvas canvas, String text, Offset position) {
    final textSpan = TextSpan(
      text: text,
      style: TextStyle(
        color: Colors.black,
        fontSize: 14.0 * quality,
        fontFamily: 'Roboto',
      ),
    );

    final textPainter = TextPainter(
      text: textSpan,
      textDirection: TextDirection.ltr,
    );

    textPainter.layout();
    textPainter.paint(canvas, position);
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
  final Map<int, List<TextAnnotation>> pageTextAnnotations;

  PdfExportData({
    required this.pageImages,
    required this.pageDrawings,
    required this.outputPath,
    required this.pageWidth,
    required this.pageHeight,
    required this.originalWidth,
    required this.pageCount,
    required this.pageTextAnnotations,
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

    const PDF_POINTS_PER_INCH = 72.0;
    const SCREEN_PPI = 96.0;
    final renderQuality = 4.0;
    final pdfScale = data.pageWidth / data.originalWidth;
    final coordinateScale = pdfScale / renderQuality;
    final strokeScale =
        (pdfScale * (PDF_POINTS_PER_INCH / SCREEN_PPI) / renderQuality) * 0.4;

    for (int i = 0; i < data.pageCount; i++) {
      final pageDrawings = data.pageDrawings[i] ?? [];
      final pageTexts = data.pageTextAnnotations[i] ?? [];

      pdf.addPage(
        pw.Page(
          pageFormat: PdfPageFormat(data.pageWidth, data.pageHeight),
          build: (context) {
            return pw.Stack(
              children: [
                pw.Positioned.fill(
                  child: pw.Image(
                    pw.MemoryImage(data.pageImages[i]),
                    fit: pw.BoxFit.fill,
                  ),
                ),
                if (pageDrawings.isNotEmpty)
                  pw.Positioned.fill(
                    child: pw.CustomPaint(
                      painter: (PdfGraphics canvas, PdfPoint size) {
                        for (var drawing in pageDrawings) {
                          if (drawing.points.isEmpty) continue;

                          final color = drawing.paint.color;
                          final pdfColor = PdfColor(
                            color.red / 255,
                            color.green / 255,
                            color.blue / 255,
                          );

                          canvas.setStrokeColor(pdfColor);
                          canvas.setGraphicState(PdfGraphicState(
                            opacity: color.alpha / 255,
                          ));

                          final strokeWidth =
                              drawing.baseStrokeWidth * strokeScale;
                          canvas.setLineWidth(strokeWidth);
                          canvas.setLineCap(PdfLineCap.round);
                          canvas.setLineJoin(PdfLineJoin.round);

                          var points = drawing.points;
                          if (points.length < 2) continue;

                          // Handle measurement lines with dashes
                          if (drawing.pathType == Mode.measure) {
                            // Set dash pattern
                            canvas.setLineDashPattern(
                                [10 * coordinateScale, 25 * coordinateScale]);

                            // Draw single line with dash pattern
                            canvas.moveTo(
                                points.first.point.dx * coordinateScale,
                                data.pageHeight -
                                    (points.first.point.dy * coordinateScale));
                            canvas.lineTo(
                                points.last.point.dx * coordinateScale,
                                data.pageHeight -
                                    (points.last.point.dy * coordinateScale));
                            canvas.strokePath();

                            // Reset dash pattern for dots
                            canvas.setLineDashPattern([]);

                            // Draw endpoint dots (existing dot drawing code remains the same)
                            final dotRadius = strokeWidth * 2;
                            for (var point in [
                              points.first.point,
                              points.last.point
                            ]) {
                              final centerX = point.dx * coordinateScale;
                              final centerY = data.pageHeight -
                                  (point.dy * coordinateScale);

                              for (var angle = 0.0;
                                  angle < 2 * math.pi;
                                  angle += 0.2) {
                                final x = centerX + dotRadius * math.cos(angle);
                                final y = centerY + dotRadius * math.sin(angle);

                                if (angle == 0) {
                                  canvas.moveTo(x, y);
                                } else {
                                  canvas.lineTo(x, y);
                                }
                              }
                              canvas.closePath();
                              canvas.setFillColor(pdfColor);
                              canvas.fillPath();
                              canvas.strokePath();
                            }
                          }
                          // Handle boxes and other drawings
                          else if (drawing.pathType == Mode.box) {
                            canvas.moveTo(
                                points[0].point.dx * coordinateScale,
                                data.pageHeight -
                                    (points[0].point.dy * coordinateScale));
                            for (int j = 1; j < points.length; j++) {
                              canvas.lineTo(
                                  points[j].point.dx * coordinateScale,
                                  data.pageHeight -
                                      (points[j].point.dy * coordinateScale));
                            }
                            canvas.strokePath();
                          }
                          // Handle freehand drawings
                          else {
                            canvas.moveTo(
                                points[0].point.dx * coordinateScale,
                                data.pageHeight -
                                    (points[0].point.dy * coordinateScale));
                            for (int j = 0; j < points.length - 1; j++) {
                              final p0 =
                                  j > 0 ? points[j - 1].point : points[j].point;
                              final p1 = points[j].point;
                              final p2 = points[j + 1].point;
                              final p3 = j + 2 < points.length
                                  ? points[j + 2].point
                                  : p2;

                              if (_isValidCoordinate(p1) &&
                                  _isValidCoordinate(p2)) {
                                final cp1 = Offset(
                                  p1.dx + (p2.dx - p0.dx) / 6,
                                  p1.dy + (p2.dy - p0.dy) / 6,
                                );
                                final cp2 = Offset(
                                  p2.dx - (p3.dx - p1.dx) / 6,
                                  p2.dy - (p3.dy - p1.dy) / 6,
                                );

                                canvas.curveTo(
                                    cp1.dx * coordinateScale,
                                    data.pageHeight -
                                        (cp1.dy * coordinateScale),
                                    cp2.dx * coordinateScale,
                                    data.pageHeight -
                                        (cp2.dy * coordinateScale),
                                    p2.dx * coordinateScale,
                                    data.pageHeight -
                                        (p2.dy * coordinateScale));
                              }
                            }
                            canvas.strokePath();
                          }
                        }
                      },
                    ),
                  ),
                ...pageTexts.map((annotation) {
                  return pw.Positioned(
                    left: annotation.position.dx * coordinateScale,
                    top: annotation.position.dy * coordinateScale,
                    child: pw.Transform.translate(
                      offset: PdfPoint(0, 0),
                      child: pw.Text(
                        annotation.text,
                        style: pw.TextStyle(
                          color: PdfColor(
                            annotation.color.red / 255,
                            annotation.color.green / 255,
                            annotation.color.blue / 255,
                          ),
                          fontSize: annotation.fontSize * coordinateScale,
                        ),
                      ),
                    ),
                  );
                }).toList(),
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

bool _isValidCoordinate(Offset point) {
  return point.dx.isFinite && point.dy.isFinite;
}

class TextAnnotation {
  final Offset position;
  final String text;
  final double fontSize;
  final Color color;
  final String fontFamily;
  final Size size;
  bool isSelected;
  final double minWidth = 100;
  final double minHeight = 30;

  TextAnnotation({
    required this.position,
    required this.text,
    this.fontSize = 16.0,
    this.color = Colors.red,
    this.fontFamily = 'Roboto',
    this.size = const Size(100, 30),
    this.isSelected = false,
  });

  Rect get bounds => Rect.fromLTWH(
        position.dx,
        position.dy,
        size.width,
        size.height,
      );

  bool containsPoint(Offset point) {
    return bounds.contains(point);
  }

  ResizeHandle? getResizeHandle(Offset point) {
    const handleSize = 10.0;

    for (var handle in ResizeHandle.values) {
      if (getHandleRect(handle, handleSize).contains(point)) {
        return handle;
      }
    }
    return null;
  }

  Rect getHandleRect(ResizeHandle handle, double size) {
    switch (handle) {
      case ResizeHandle.topLeft:
        return Rect.fromLTWH(
            position.dx - size / 2, position.dy - size / 2, size, size);
      case ResizeHandle.topRight:
        return Rect.fromLTWH(position.dx + this.size.width - size / 2,
            position.dy - size / 2, size, size);
      case ResizeHandle.bottomLeft:
        return Rect.fromLTWH(position.dx - size / 2,
            position.dy + this.size.height - size / 2, size, size);
      case ResizeHandle.bottomRight:
        return Rect.fromLTWH(position.dx + this.size.width - size / 2,
            position.dy + this.size.height - size / 2, size, size);
    }
  }

  TextAnnotation copyWith({
    Offset? position,
    String? text,
    double? fontSize,
    Color? color,
    String? fontFamily,
    Size? size,
    bool? isSelected,
  }) {
    return TextAnnotation(
      position: position ?? this.position,
      text: text ?? this.text,
      fontSize: fontSize ?? this.fontSize,
      color: color ?? this.color,
      fontFamily: fontFamily ?? this.fontFamily,
      size: size ?? this.size,
      isSelected: isSelected ?? this.isSelected,
    );
  }

  TextAnnotation resize(ResizeHandle handle, Offset delta) {
    double newWidth = size.width;
    double newHeight = size.height;
    Offset newPosition = position;

    switch (handle) {
      case ResizeHandle.topLeft:
        newWidth = math.max(size.width - delta.dx, minWidth);
        newHeight = math.max(size.height - delta.dy, minHeight);
        newPosition = Offset(
          position.dx + (size.width - newWidth),
          position.dy + (size.height - newHeight),
        );
        break;
      case ResizeHandle.topRight:
        newWidth = math.max(size.width + delta.dx, minWidth);
        newHeight = math.max(size.height - delta.dy, minHeight);
        newPosition =
            Offset(position.dx, position.dy + (size.height - newHeight));
        break;
      case ResizeHandle.bottomLeft:
        newWidth = math.max(size.width - delta.dx, minWidth);
        newHeight = math.max(size.height + delta.dy, minHeight);
        newPosition =
            Offset(position.dx + (size.width - newWidth), position.dy);
        break;
      case ResizeHandle.bottomRight:
        newWidth = math.max(size.width + delta.dx, minWidth);
        newHeight = math.max(size.height + delta.dy, minHeight);
        break;
    }

    return copyWith(
      position: newPosition,
      size: Size(newWidth, newHeight),
    );
  }
}

enum ResizeHandle {
  topLeft,
  topRight,
  bottomLeft,
  bottomRight,
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
  final Mode? pathType;
  final bool isDashed;
  final List<double>? dashPattern;
  MeasurementTool? measurementTool;

  DrawingPath(
    this.points,
    this.paint,
    this.baseStrokeWidth, {
    this.pathType,
    this.isDashed = false,
    this.dashPattern,
    this.measurementTool,
  });
  Path createSmoothPath(double currentZoom) {
    if (points.isEmpty) return Path();

    // Scale the stroke width based on current zoom
    paint.strokeWidth = baseStrokeWidth * currentZoom;
    if (pathType == Mode.box) {
      // For boxes, draw straight lines between points
      Path path = Path();
      path.moveTo(points[0].point.dx, points[0].point.dy);
      for (var point in points.skip(1)) {
        path.lineTo(point.point.dx, point.point.dy);
      }
      return path;
    }

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
  // Update createSmoothPath to use scaled stroke width
  // Path createSmoothPath(double currentZoom) {
  //   if (points.isEmpty) return Path();

  //   paint.strokeWidth = baseStrokeWidth * currentZoom;
  //   Path path = Path();

  //   // Special handling for dashed measurement lines
  //   if (isDashed && points.length == 2 && pathType == Mode.measure) {
  //     final start = points[0].point;
  //     final end = points[1].point;
  //     final distance = (end - start).distance;
  //     final direction = (end - start) / distance;

  //     // Draw dotted line
  //     double currentDistance = 0;
  //     bool drawing = true;
  //     double dashLength = dashPattern![0];
  //     double gapLength = dashPattern![1];

  //     while (currentDistance < distance) {
  //       final startPoint = start + direction * currentDistance;
  //       currentDistance += drawing ? dashLength : gapLength;
  //       if (currentDistance > distance) currentDistance = distance;
  //       final endPoint = start + direction * currentDistance;

  //       if (drawing) {
  //         path.moveTo(startPoint.dx, startPoint.dy);
  //         path.lineTo(endPoint.dx, endPoint.dy);
  //       }
  //       drawing = !drawing;
  //     }

  //     // Draw endpoint dots
  //     path.addOval(Rect.fromCircle(
  //       center: points[0].point,
  //       radius: points[0].baseStrokeWidth / 2,
  //     ));
  //     path.addOval(Rect.fromCircle(
  //       center: points[1].point,
  //       radius: points[1].baseStrokeWidth / 2,
  //     ));

  //     return path;
  //   }

  //   path.moveTo(points[0].point.dx, points[0].point.dy);

  //   if (points.length == 2) {
  //     path.lineTo(points[1].point.dx, points[1].point.dy);
  //   } else {
  //     for (int i = 0; i < points.length - 1; i++) {
  //       final p0 = i > 0 ? points[i - 1].point : points[i].point;
  //       final p1 = points[i].point;
  //       final p2 = points[i + 1].point;
  //       final p3 = i + 2 < points.length ? points[i + 2].point : p2;

  //       final controlPoint1 = Offset(
  //         p1.dx + (p2.dx - p0.dx) / 6,
  //         p1.dy + (p2.dy - p0.dy) / 6,
  //       );

  //       final controlPoint2 = Offset(
  //         p2.dx - (p3.dx - p1.dx) / 6,
  //         p2.dy - (p3.dy - p1.dy) / 6,
  //       );

  //       path.cubicTo(
  //         controlPoint1.dx,
  //         controlPoint1.dy,
  //         controlPoint2.dx,
  //         controlPoint2.dy,
  //         p2.dx,
  //         p2.dy,
  //       );
  //     }
  //   }
  //   return path;
  // }

  List<DrawingPath> splitPath(Offset eraserPoint, double eraserRadius) {
    if (points.isEmpty) return [this];

    List<List<DrawingPoint>> segments = [];
    List<DrawingPoint> currentSegment = [];
    bool isInEraserRange = false;

    for (int i = 0; i < points.length; i++) {
      final point = points[i];
      final distance = (point.point - eraserPoint).distance;
      final currentPointInRange = distance <= eraserRadius;

      // Start a new segment when transitioning from erased to non-erased points
      if (currentPointInRange != isInEraserRange) {
        if (!currentPointInRange && currentSegment.isNotEmpty) {
          segments.add(List.from(currentSegment));
          currentSegment = [];
        }
        isInEraserRange = currentPointInRange;
      }

      if (!currentPointInRange) {
        currentSegment.add(point);
      }
    }

    // Add the last segment if it's not empty
    if (currentSegment.isNotEmpty) {
      segments.add(currentSegment);
    }

    // Convert segments to DrawingPath objects
    return segments
        .map((segment) => DrawingPath(
              segment,
              paint,
              baseStrokeWidth,
            ))
        .toList();
  }
}

extension OffsetExtension on Offset {
  Offset normalized() {
    final length = distance;
    if (length == 0.0) return Offset.zero;
    return this / length;
  }
}

enum MeasurementTool {
  none,
  scale,
  measure,
  box,
}

enum ActionType { draw, erase, text, measure, box }

class AnnotationAction {
  final ActionType type;
  final int pageNumber;
  final dynamic oldState;
  final dynamic newState;

  AnnotationAction({
    required this.type,
    required this.pageNumber,
    this.oldState,
    required this.newState,
  });
}
