import 'package:flutter/material.dart';
import 'package:syncfusion_flutter_pdfviewer/pdfviewer.dart';

void main() {
  runApp(MaterialApp(
    debugShowCheckedModeBanner: false,
    home: PDFViewerPage(),
  ));
}

class PDFViewerPage extends StatefulWidget {
  @override
  _PDFViewerPageState createState() => _PDFViewerPageState();
}

class _PDFViewerPageState extends State<PDFViewerPage> {
  final GlobalKey<SfPdfViewerState> _pdfViewerKey = GlobalKey();
  final PdfViewerController _pdfViewerController = PdfViewerController();

  bool _isHighlighting = false;
  bool _isDrawing = false;
  bool _isErasing = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('PDF Viewer'),
        actions: [
          IconButton(
            icon: const Icon(Icons.highlight),
            onPressed: () {
              _pdfViewerController.annotationMode = PdfAnnotationMode.highlight;
            },
          ),
          IconButton(
            icon: const Icon(Icons.brush),
            onPressed: () {
              // _pdfViewerController.annotationMode = PdfAnnotationMode.squiggly;
            },
          ),
          IconButton(
            icon: const Icon(Icons.text_fields),
            onPressed: () {},
          ),
          IconButton(
            icon: const Icon(Icons.delete),
            onPressed: () {},
          ),
        ],
      ),
      body: CustomPaint(
        child: SfPdfViewer.asset(
          'assets/sample.pdf',
          key: _pdfViewerKey,
          controller: _pdfViewerController,
          onAnnotationAdded: (annotation) {},
          onZoomLevelChanged: (details) {
            details.newZoomLevel;
            details.oldZoomLevel;
          },
        ),
      ),
    );
  }
}
