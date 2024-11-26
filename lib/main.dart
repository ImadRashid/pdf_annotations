import 'package:flutter/material.dart';
import '/screens/pdf_editor_screen.dart';

void main() {
  runApp(MyApp());
}

class MyApp extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'PDF Editor',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: PdfEditorScreen(),
    );
  }
}




// import 'dart:async';
// import 'dart:typed_data';
// import 'dart:ui' as ui;
// import 'package:flutter/material.dart';
// import 'package:flutter/rendering.dart';
// import 'package:open_file/open_file.dart';
// import 'package:pdf/pdf.dart';
// import 'package:pdf/widgets.dart' as pw;
// import 'package:pdf_annotations/screens/pdf_editor_screen.dart';
// import 'package:pdf_annotations/utils/pdf_utils.dart';
// import 'package:printing/printing.dart';
// import 'package:file_picker/file_picker.dart';
// import 'dart:io';
// import 'package:path_provider/path_provider.dart';
// import 'package:font_awesome_flutter/font_awesome_flutter.dart';

// enum Mode { highlight, draw, erase, pan, text }

// class PdfPageViewCanvas extends StatefulWidget {
//   @override
//   _PdfPageViewCanvasState createState() => _PdfPageViewCanvasState();
// }

// class _PdfPageViewCanvasState extends State<PdfPageViewCanvas> {
//   List<GlobalKey> _repaintBoundaryKeys = [];
//   List<Uint8List> _screenshots = [];
//   List<ui.Image> _pdfImages = [];
//   int _totalPages = 0;
//   String? _selectedPdfPath;
//   List<List<Offset?>> _drawings = [];
//   int _currentPage = 0;
//   Mode mode = Mode.pan;
//   double zoomLevel = 1.0;
//   TextEditingController _pageController = TextEditingController();
//   @override
//   void initState() {
//     super.initState();
//     _repaintBoundaryKeys = List.generate(100, (index) => GlobalKey());
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text('PDF Viewer with Drawing'),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.folder_open),
//             onPressed: _pickPdfFile,
//           ),
//           IconButton(
//             icon: Icon(Icons.save),
//             onPressed: _savePdf,
//           ),
//         ],
//       ),
//       body: _selectedPdfPath == null
//           ? Center(child: Text('Please select a PDF file to display'))
//           : _pdfImages.isEmpty
//               ? Center(child: CircularProgressIndicator())
//               : Column(
//                   children: [
//                     _buildToolbar(),
//                     Expanded(
//                       child: GestureDetector(
//                         onScaleUpdate: (details) {
//                           if (mode == Mode.draw) {
//                             setState(() {
//                               final localPosition = details.localFocalPoint;
//                               _drawings[_currentPage].add(localPosition);
//                             });
//                           }
//                         },
//                         onScaleEnd: (_) {
//                           if (mode == Mode.draw) {
//                             setState(() {
//                               _drawings[_currentPage].add(null);
//                             });
//                           }
//                         },
//                         child: RepaintBoundary(
//                           key: _repaintBoundaryKeys[_currentPage],
//                           child: Stack(
//                             children: [
//                               CustomPaint(
//                                 painter:
//                                     PdfPagePainter(_pdfImages[_currentPage]),
//                                 child: Container(),
//                               ),
//                               CustomPaint(
//                                 painter:
//                                     DrawingPainter(_drawings[_currentPage]),
//                               ),
//                             ],
//                           ),
//                         ),
//                       ),
//                     ),
//                   ],
//                 ),
//     );
//   }

//   Future<Uint8List?> _captureScreenshot(int pageIndex) async {
//     try {
//       final boundaryKey = _repaintBoundaryKeys[pageIndex];
//       final boundaryContext = boundaryKey.currentContext;

//       if (boundaryContext == null) {
//         print("RepaintBoundary context is null for page: $pageIndex");
//         return null;
//       }

//       final boundary =
//           boundaryContext.findRenderObject() as RenderRepaintBoundary;

//       if (boundary.debugNeedsPaint) {
//         print("Waiting for RepaintBoundary to be painted...");
//         await Future.delayed(Duration(milliseconds: 100)); // Wait briefly
//       }

//       final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
//       final ByteData? byteData =
//           await image.toByteData(format: ui.ImageByteFormat.png);

//       return byteData?.buffer.asUint8List();
//     } catch (e) {
//       print("Error capturing screenshot: $e");
//       return null;
//     }
//   }

//   Future<void> _savePdf() async {
//     try {
//       final pdf = pw.Document();

//       for (int i = 0; i < _totalPages; i++) {
//         // Capture screenshot
//         final Uint8List? screenshot = await _captureScreenshot(i);
//         if (screenshot != null) {
//           final pdfImage = pw.MemoryImage(screenshot);

//           // Add the screenshot as a PDF page
//           pdf.addPage(
//             pw.Page(
//               build: (pw.Context context) {
//                 return pw.Center(
//                   child: pw.Image(pdfImage),
//                 );
//               },
//             ),
//           );
//         }
//       }

//       // Save the PDF
//       final data = await pdf.save();
//       final file = await PdfUtils.saveToFile(data, "annotated_screenshots.pdf");

//       ScaffoldMessenger.of(context).showSnackBar(
//         SnackBar(content: Text('PDF saved to ${file.path}')),
//       );
//       await OpenFile.open(file.path);
//     } catch (e) {
//       print('Error saving PDF: $e');
//     }
//   }

//   Future<void> _pickPdfFile() async {
//     try {
//       FilePickerResult? result = await FilePicker.platform.pickFiles(
//         type: FileType.custom,
//         allowedExtensions: ['pdf'],
//       );

//       if (result != null) {
//         String? filePath = result.files.single.path;

//         if (filePath != null) {
//           setState(() {
//             _selectedPdfPath = filePath;
//             _pdfImages = [];
//             _totalPages = 0;
//             _drawings = [];
//           });

//           _loadAndRasterizePdf(filePath);
//         }
//       }
//     } catch (e) {
//       print('Error picking file: $e');
//     }
//   }

//   Future<void> _loadAndRasterizePdf(String filePath) async {
//     try {
//       final file = File(filePath);
//       final documentBytes = await file.readAsBytes();

//       final pages = Printing.raster(documentBytes, dpi: 300);

//       int pageCount = 0;
//       final List<ui.Image> images = [];
//       await for (var page in pages) {
//         final image = await page.toImage();
//         images.add(image);
//         _drawings.add([]);
//         pageCount++;
//       }

//       setState(() {
//         _pdfImages = images;
//         _totalPages = pageCount;
//       });
//     } catch (e) {
//       print('Error loading or rasterizing PDF: $e');
//     }
//   }

//   Widget _buildToolbar() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         if (_selectedPdfPath != null)
//           Container(
//             color: Colors.grey[300],
//             padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
//             child: Row(
//               mainAxisAlignment: MainAxisAlignment.spaceEvenly,
//               children: [
//                 IconButton(
//                   color: mode == Mode.highlight ? Colors.yellow : Colors.black,
//                   icon: Icon(Icons.highlight),
//                   tooltip: 'Highlight',
//                   onPressed: () {
//                     _updateMode(Mode.highlight);
//                   },
//                 ),
//                 IconButton(
//                   color: mode == Mode.draw ? Colors.red : Colors.black,
//                   icon: Icon(Icons.brush),
//                   tooltip: 'Draw',
//                   onPressed: () {
//                     _updateMode(Mode.draw);
//                   },
//                 ),
//                 IconButton(
//                   color: mode == Mode.erase ? Colors.red : Colors.black,
//                   icon: Icon(FontAwesomeIcons.eraser),
//                   tooltip: 'Erase',
//                   onPressed: () {
//                     _updateMode(Mode.erase);
//                   },
//                 ),
//                 IconButton(
//                   color: mode == Mode.pan ? Colors.red : Colors.black,
//                   icon: Icon(FontAwesomeIcons.hand),
//                   tooltip: 'Pan',
//                   onPressed: () {
//                     _updateMode(Mode.pan);
//                   },
//                 ),
//                 IconButton(
//                   color: mode == Mode.text ? Colors.blue : Colors.black,
//                   icon: Icon(Icons.text_fields),
//                   tooltip: 'Add Text',
//                   onPressed: () {
//                     _updateMode(Mode.text);
//                   },
//                 ),
//                 IconButton(
//                   icon: Icon(Icons.zoom_in),
//                   tooltip: 'Zoom in',
//                   onPressed: () {
//                     setState(() {
//                       zoomLevel += 0.1;
//                     });
//                   },
//                 ),
//                 IconButton(
//                   icon: Icon(Icons.zoom_out),
//                   tooltip: 'Zoom out',
//                   onPressed: () {
//                     setState(() {
//                       zoomLevel -= 0.1;
//                     });
//                   },
//                 ),
//               ],
//             ),
//           ),
//         Container(
//           color: Colors.grey[200],
//           padding: EdgeInsets.symmetric(vertical: 8, horizontal: 16),
//           child: Row(
//             children: [
//               IconButton(
//                 icon: Icon(Icons.arrow_back),
//                 onPressed: () {
//                   if (_currentPage > 0) {
//                     setState(() {
//                       _currentPage--;
//                     });
//                   }
//                 },
//               ),
//               Expanded(
//                 child: Row(
//                   children: [
//                     Text("Page:"),
//                     SizedBox(width: 8),
//                     SizedBox(
//                       width: 50,
//                       child: TextField(
//                         controller: _pageController,
//                         decoration: InputDecoration(
//                           isDense: true,
//                           contentPadding: EdgeInsets.symmetric(vertical: 4),
//                           border: OutlineInputBorder(),
//                         ),
//                         keyboardType: TextInputType.number,
//                         onSubmitted: (value) {
//                           final int? page = int.tryParse(value);
//                           if (page != null &&
//                               page > 0 &&
//                               page <= _totalPages &&
//                               page != _currentPage) {
//                             setState(() {
//                               _currentPage = page - 1;
//                             });
//                           }
//                         },
//                       ),
//                     ),
//                     Text(" / $_totalPages"),
//                   ],
//                 ),
//               ),
//               IconButton(
//                 icon: const Icon(Icons.arrow_forward),
//                 onPressed: () {
//                   if (_currentPage < _totalPages - 1) {
//                     setState(() {
//                       _currentPage++;
//                     });
//                   }
//                 },
//               ),
//             ],
//           ),
//         ),
//       ],
//     );
//   }

//   void _updateMode(Mode newMode) {
//     setState(() {
//       mode = newMode;
//     });
//   }
// }

// // Custom painter for PDF pages
// class PdfPagePainter extends CustomPainter {
//   final ui.Image image;

//   PdfPagePainter(this.image);

//   @override
//   void paint(Canvas canvas, Size size) {
//     paintImage(
//       canvas: canvas,
//       rect: Rect.fromLTWH(0, 0, size.width, size.height),
//       image: image,
//       fit: BoxFit.contain,
//     );
//   }

//   @override
//   bool shouldRepaint(CustomPainter oldDelegate) => false;
// }

// // Custom painter for drawing
// class DrawingPainter extends CustomPainter {
//   final List<Offset?> points;

//   DrawingPainter(this.points);

//   @override
//   void paint(Canvas canvas, Size size) {
//     final paint = Paint()
//       ..color = Colors.red
//       ..strokeCap = StrokeCap.round
//       ..strokeWidth = 5.0;

//     for (int i = 0; i < points.length - 1; i++) {
//       if (points[i] != null && points[i + 1] != null) {
//         canvas.drawLine(points[i]!, points[i + 1]!, paint);
//       } else if (points[i] != null && points[i + 1] == null) {
//         canvas.drawCircle(points[i]!, 5.0, paint);
//       }
//     }
//   }

//   @override
//   bool shouldRepaint(CustomPainter oldDelegate) => true;
// }

// void main() {
//   runApp(MaterialApp(
//     home: PdfEditorScreen(),
//   ));
// }
