import 'dart:developer';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';
import 'package:open_file/open_file.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
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
}

class PdfEditorScreen extends StatefulWidget {
  @override
  _PdfEditorScreenState createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  Mode mode = Mode.pan;
  final PdfViewerController _pdfViewerController = PdfViewerController();
  String? _pdfPath;
  Map<int, List<DrawnLine>> pageLines = {}; // Annotations per page
  Map<int, List<DrawnLine>> pageHighlights = {};
  int currentPage = 0; // Track the current page
  int totalPages = 0; // Total pages in the PDF
  List<DrawnLine> lines = [];
  List<DrawnLine> highlights = [];
  Offset? currentPoint;

  double pointerSize = 3.0; // Default pointer size
  Color pointerColor = Colors.black; // Default pointer color
  bool showOptions = true;
  Map<int, List<TextAnnotation>> pageTexts = {}; // Text annotations per page
  List<TextAnnotation> texts = []; // Current page's text annotations

  // Page dimensions and zoom factor
  Size? pageSize;
  double zoomLevel = 1.0;
  bool isZooming = false;
  TextEditingController _pageController = TextEditingController();
  @override
  Widget build(BuildContext context) {
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
              onPressed: _saveModifiedPDF,
            ),
          ],
          // IconButton(
          //   icon: Icon(Icons.folder_open),
          //   onPressed: _pickPDF,
          // ),
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
                  child: Stack(
                    children: [
                      SfPdfViewer.file(
                        File(_pdfPath!),
                        pageLayoutMode: PdfPageLayoutMode.single,
                        controller: _pdfViewerController,
                        onDocumentLoaded: (details) {
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

                          // Load new page annotations
                          lines = pageLines[currentPage] ?? [];
                          highlights = pageHighlights[currentPage] ?? [];
                          texts = pageTexts[currentPage] ?? [];

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
                      GestureDetector(
                        onScaleStart: (details) {
                          print("Scale start: ${details.pointerCount}");
                          // Check if this is a zoom or pan gesture
                          setState(() {
                            isZooming = details.pointerCount > 1;
                          });

                          if (!isZooming && mode != Mode.pan) {
                            if (mode == Mode.text) {
                              _addTextAnnotation(details.localFocalPoint);
                            } else {
                              setState(() {
                                currentPoint = _getNormalizedOffset(
                                    details.localFocalPoint);
                                if (mode == Mode.erase) {
                                  _eraseLine(currentPoint!);
                                }
                              });
                            }
                          }
                        },
                        onScaleUpdate: (details) {
                          if (isZooming) {
                            print("Zooming");
                            if ((details.scale - 1.0).abs() > 0.01) {
                              // Threshold for significant changes
                              setState(() {
                                zoomLevel =
                                    (zoomLevel * details.scale).clamp(1.0, 3.0);

                                _pdfViewerController.zoomLevel = zoomLevel;
                              });
                            }
                          } else if (mode != Mode.pan) {
                            print("Single finger action");
                            setState(() {
                              final offset =
                                  _getNormalizedOffset(details.localFocalPoint);
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

                                  // Save the new highlight immediately
                                  if (pageHighlights[currentPage] == null) {
                                    pageHighlights[currentPage] = [];
                                  }
                                  pageHighlights[currentPage]!
                                      .add(newHighlight);
                                }
                              } else if (mode == Mode.draw) {
                                if (lines.isNotEmpty && lines.last.isDrawing) {
                                  lines.last.points.add(offset);
                                } else {
                                  final newLine = DrawnLine(
                                    [offset],
                                    pointerColor,
                                    pointerSize,
                                    isDrawing: true,
                                  );
                                  lines.add(newLine);

                                  // Save the new line immediately
                                  if (pageLines[currentPage] == null) {
                                    pageLines[currentPage] = [];
                                  }
                                  pageLines[currentPage]!.add(newLine);
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

                          if (mode != Mode.pan) {
                            setState(() {
                              if (mode == Mode.highlight &&
                                  highlights.isNotEmpty) {
                                highlights.last.isDrawing = false;
                              } else if (mode == Mode.draw &&
                                  lines.isNotEmpty) {
                                lines.last.isDrawing = false;
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
                                  color: Colors.red.withOpacity(0.3),
                                  width: pageSize!.width * zoomLevel,
                                  height: pageSize!.height * zoomLevel,
                                  child: CustomPaint(
                                    isComplex: true,
                                    painter: DrawingPainter(
                                      _getAbsoluteLines(lines),
                                      _getAbsoluteLines(highlights),
                                      _getAbsoluteTexts(texts),
                                    ),
                                  ),
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
                _buildToolbar(),
              ],
            ),
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

  void _addTextAnnotation(Offset localPosition) async {
    final normalizedPosition = _getNormalizedOffset(localPosition);
    String? inputText = await _showTextInputDialog();
    if (inputText != null && inputText.isNotEmpty) {
      setState(() {
        final annotation = TextAnnotation(
          normalizedPosition,
          inputText,
          TextStyle(color: pointerColor, fontSize: pointerSize * 4),
        );
        texts.add(annotation);

        // Save the annotation immediately
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
        if (textBounds.contains(normalizedPosition)) {
          text.isSelected = !text.isSelected;
        } else {
          text.isSelected = false;
        }
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

  Widget _buildToolbar() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_pdfPath != null && showOptions)
          Container(
            color: Colors.grey[300],
            padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
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
                  icon: Icon(Icons.brush, color: pointerColor),
                  tooltip: 'Draw',
                  onPressed: () {
                    _updateMode(Mode.draw);
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
                  color: mode == Mode.pan ? Colors.red : Colors.black,
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
                  color: mode == Mode.pan ? Colors.red : Colors.black,
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
          color: Colors.grey[200],
          padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
          child: Row(
            children: [
              IconButton(
                icon: Icon(Icons.arrow_back),
                onPressed: () {
                  if (currentPage > 1) {
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
                icon: Icon(Icons.arrow_forward),
                onPressed: () {
                  if (currentPage < totalPages) {
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

  Offset _getNormalizedOffset(Offset localPosition) {
    if (pageSize == null) return localPosition;

    return Offset(
      localPosition.dx / pageSize!.width,
      localPosition.dy / pageSize!.height,
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
      }
    });
  }

  void _eraseLine(Offset position) {
    setState(() {
      lines.removeWhere((line) {
        final isErased =
            line.points.any((point) => (point - position).distance < 10);
        if (isErased) {
          // Remove the line from the saved annotations
          pageLines[currentPage]?.remove(line);
        }
        return isErased;
      });

      highlights.removeWhere((highlight) {
        final isErased =
            highlight.points.any((point) => (point - position).distance < 10);
        if (isErased) {
          // Remove the highlight from the saved annotations
          pageHighlights[currentPage]?.remove(highlight);
        }
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
