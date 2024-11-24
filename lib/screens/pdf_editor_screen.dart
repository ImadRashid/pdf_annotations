import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';
import '/models/drawn_line.dart';
import '/widgets/drawing_painter.dart';
import '/utils/pdf_utils.dart';
import 'package:file_picker/file_picker.dart';

class PdfEditorScreen extends StatefulWidget {
  @override
  _PdfEditorScreenState createState() => _PdfEditorScreenState();
}

class _PdfEditorScreenState extends State<PdfEditorScreen> {
  PdfViewerController _pdfViewerController = PdfViewerController();
  String? _pdfPath;
  Map<int, List<DrawnLine>> pageLines = {}; // Annotations per page
  Map<int, List<DrawnLine>> pageHighlights = {};
  int currentPage = 0; // Track the current page
  int totalPages = 0; // Total pages in the PDF
  List<DrawnLine> lines = [];
  List<DrawnLine> highlights = [];
  Offset? currentPoint;

  bool isHighlightMode = false;
  bool isEraseMode = false; // Erase mode flag
  double pointerSize = 3.0; // Default pointer size
  Color pointerColor = Colors.black; // Default pointer color

  void _updateMode(String mode) {
    setState(() {
      if (mode == 'Highlight') {
        isHighlightMode = true;
        isEraseMode = false;
      } else if (mode == 'Draw') {
        isHighlightMode = false;
        isEraseMode = false;
      } else if (mode == 'Erase') {
        isHighlightMode = false;
        isEraseMode = true;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Edit PDF"),
        actions: [
          if (_pdfPath != null) ...[
            IconButton(
              icon: Icon(Icons.undo),
              onPressed: _undo, // Undo button
            ),
            IconButton(
              icon: Icon(Icons.save),
              onPressed: _saveModifiedPDF,
            ),
          ],
          IconButton(
            icon: Icon(Icons.folder_open),
            onPressed: _pickPDF,
          ),
        ],
      ),
      body: _pdfPath == null
          ? Center(child: Text("Open a PDF to start editing"))
          : Stack(
              children: [
                SfPdfViewer.file(
                  File(_pdfPath!),
                  controller: _pdfViewerController,
                  onPageChanged: (details) {
                    setState(() {
                      // Save current page annotations
                      if (pageLines[currentPage] == null) {
                        pageLines[currentPage] = List.from(lines);
                      } else {
                        pageLines[currentPage] = lines;
                      }
                      if (pageHighlights[currentPage] == null) {
                        pageHighlights[currentPage] = List.from(highlights);
                      } else {
                        pageHighlights[currentPage] = highlights;
                      }

                      // Switch to new page
                      currentPage = details.newPageNumber;
                      lines = pageLines[currentPage] ?? [];
                      highlights = pageHighlights[currentPage] ?? [];
                    });
                  },
                ),
                GestureDetector(
                  onPanStart: (details) {
                    setState(() {
                      currentPoint = details.localPosition;
                      if (isEraseMode) {
                        _eraseLine(currentPoint!); // Erase if in eraser mode
                      }
                    });
                  },
                  onPanUpdate: (details) {
                    setState(() {
                      final offset = details.localPosition;
                      if (isEraseMode) {
                        _eraseLine(offset);
                      } else if (isHighlightMode) {
                        if (highlights.isNotEmpty &&
                            highlights.last.isDrawing) {
                          highlights.last.points.add(offset);
                        } else {
                          highlights.add(DrawnLine(
                            [offset],
                            Colors.yellow.withOpacity(0.3),
                            15.0,
                            isDrawing: true,
                          ));
                        }
                      } else {
                        if (lines.isNotEmpty && lines.last.isDrawing) {
                          lines.last.points.add(offset);
                        } else {
                          lines.add(DrawnLine(
                            [offset],
                            pointerColor,
                            pointerSize,
                            isDrawing: true,
                          ));
                        }
                      }
                      currentPoint = offset;
                    });
                  },
                  onPanEnd: (_) {
                    setState(() {
                      if (isHighlightMode && highlights.isNotEmpty) {
                        highlights.last.isDrawing = false;
                      } else if (!isHighlightMode && lines.isNotEmpty) {
                        lines.last.isDrawing = false;
                      }
                      currentPoint = null;
                    });
                  },
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: DrawingPainter(
                      lines,
                      highlights,
                    ), // Only current page's annotations
                  ),
                ),
              ],
            ),
      floatingActionButton: _pdfPath != null
          ? PopupMenuButton<String>(
              icon: Icon(Icons.menu), // Main button icon
              onSelected: (String option) {
                if (option == 'Pointer Size') {
                  _showPointerSizeSelector(
                      context); // Open pointer size selector
                } else if (option == 'Pointer Color') {
                  _showPointerColorSelector(context); // Open color picker
                } else {
                  _updateMode(option); // Update drawing mode
                }
              },
              itemBuilder: (BuildContext context) => [
                PopupMenuItem(
                  value: 'Highlight',
                  child: Row(
                    children: [
                      Icon(Icons.highlight, color: Colors.yellow),
                      SizedBox(width: 8),
                      Text('Highlight'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'Draw',
                  child: Row(
                    children: [
                      Icon(Icons.edit, color: pointerColor),
                      SizedBox(width: 8),
                      Text('Draw'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'Erase',
                  child: Row(
                    children: [
                      Icon(Icons.delete, color: Colors.red),
                      SizedBox(width: 8),
                      Text('Erase'),
                    ],
                  ),
                ),
                PopupMenuDivider(),
                PopupMenuItem(
                  value: 'Pointer Size',
                  child: Row(
                    children: [
                      Icon(Icons.linear_scale),
                      SizedBox(width: 8),
                      Text('Pointer Size'),
                    ],
                  ),
                ),
                PopupMenuItem(
                  value: 'Pointer Color',
                  child: Row(
                    children: [
                      Icon(Icons.color_lens, color: pointerColor),
                      SizedBox(width: 8),
                      Text('Pointer Color'),
                    ],
                  ),
                ),
              ],
            )
          : null,
    );
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
      if (isHighlightMode && highlights.isNotEmpty) {
        highlights.removeLast(); // Remove the last highlight
      } else if (!isHighlightMode && lines.isNotEmpty) {
        lines.removeLast(); // Remove the last line
      }
    });
  }

  void _eraseLine(Offset position) {
    setState(() {
      lines.removeWhere((line) =>
          line.points.any((point) => (point - position).distance < 10));
      highlights.removeWhere((highlight) =>
          highlight.points.any((point) => (point - position).distance < 10));
    });
  }

  Future<void> _saveModifiedPDF() async {
    if (_pdfPath == null) return;

    final Uint8List? pdfBytes = await PdfUtils.overlayDrawingOnPDF(
      _pdfPath!,
      pageLines,
      pageHighlights,
    );

    if (pdfBytes != null) {
      final file = await PdfUtils.saveToFile(pdfBytes, "a.pdf");
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('PDF saved to ${file.path}')),
      );
    }
  }

  void _showPointerSizeSelector(BuildContext context) {
    // Pointer size selector dialog logic here
  }

  void _showPointerColorSelector(BuildContext context) {
    // Pointer color selector dialog logic here
  }
}
