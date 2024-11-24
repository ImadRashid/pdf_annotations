// import 'package:flutter/material.dart';
// import '/models/drawn_line.dart';
// import '/widgets/drawing_painter.dart';
// import '/utils/pdf_utils.dart';
// import 'package:file_picker/file_picker.dart';
// import 'package:open_file/open_file.dart';

// class DrawingScreen extends StatefulWidget {
//   @override
//   _DrawingScreenState createState() => _DrawingScreenState();
// }

// class _DrawingScreenState extends State<DrawingScreen> {
//   List<DrawnLine> lines = [];
//   List<DrawnLine> highlights = [];
//   Offset? currentPoint;
//   bool isHighlightMode = false;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       appBar: AppBar(
//         title: Text("Draw and Export to PDF"),
//         actions: [
//           IconButton(
//             icon: Icon(Icons.save),
//             onPressed: _saveAsPDF,
//           ),
//           IconButton(
//             icon: Icon(Icons.folder_open),
//             onPressed: _openPDF,
//           ),
//         ],
//       ),
//       body: GestureDetector(
//         onPanStart: (details) {
//           setState(() {
//             currentPoint = details.localPosition;
//           });
//         },
//         onPanUpdate: (details) {
//           setState(() {
//             final offset = details.localPosition;
//             if (isHighlightMode) {
//               highlights
//                   .add(DrawnLine([currentPoint!, offset], Colors.yellow, 15.0));
//             } else {
//               lines.add(DrawnLine([currentPoint!, offset], Colors.black, 3.0));
//             }
//             currentPoint = offset;
//           });
//         },
//         onPanEnd: (_) {
//           setState(() {
//             currentPoint = null;
//           });
//         },
//         child: CustomPaint(
//           size: Size.infinite,
//           painter: DrawingPainter(lines, highlights),
//         ),
//       ),
//       floatingActionButton: FloatingActionButton(
//         child: Icon(isHighlightMode ? Icons.highlight : Icons.edit),
//         onPressed: _toggleMode,
//       ),
//     );
//   }

//   void _toggleMode() {
//     setState(() {
//       isHighlightMode = !isHighlightMode;
//     });
//   }

//   Future<void> _saveAsPDF() async {
//     await PdfUtils.saveDrawingAsPDF(lines, highlights);
//   }

//   Future<void> _openPDF() async {
//     FilePickerResult? result = await FilePicker.platform.pickFiles(
//       type: FileType.custom,
//       allowedExtensions: ['pdf'],
//     );

//     if (result != null && result.files.single.path != null) {
//       OpenFile.open(result.files.single.path);
//     }
//   }
// }
