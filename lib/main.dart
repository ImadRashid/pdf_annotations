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
