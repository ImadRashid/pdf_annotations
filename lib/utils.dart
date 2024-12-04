import 'dart:io';
import 'dart:isolate';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as path;

class PdfStorageHandler {
  static Future<bool> requestStoragePermission() async {
    if (Platform.isAndroid) {
      final status = await Permission.storage.status;
      if (status.isDenied) {
        final result = await Permission.storage.request();
        return result.isGranted;
      }
      return status.isGranted;
    }
    return true;
  }

  static Future<String> generateUniqueFilePath(String originalPath) async {
    final directory = path.dirname(originalPath);
    final extension = path.extension(originalPath);
    final nameWithoutExtension = path.basenameWithoutExtension(originalPath);

    String newPath = path.join(directory, '$nameWithoutExtension$extension');
    int copyCount = 0;

    // For copy option, start with (Copy) suffix
    if (nameWithoutExtension.contains('(Copy)')) {
      newPath = originalPath;
    } else {
      newPath = path.join(directory, '$nameWithoutExtension (Copy)$extension');
    }

    while (await File(newPath).exists()) {
      copyCount++;
      String suffix =
          ' (Copy)' + ('${copyCount > 1 ? ' (Copy)' * (copyCount - 1) : ''}');
      newPath = path.join(directory, '$nameWithoutExtension$suffix$extension');
    }

    return newPath;
  }

  static Future<void> replacePdfFile(
      String sourcePath, String targetPath) async {
    try {
      final sourceFile = File(sourcePath);
      final targetFile = File(targetPath);

      if (await targetFile.exists()) {
        await targetFile.delete();
      }

      await sourceFile.copy(targetPath);
      await sourceFile.delete();
    } catch (e) {
      throw Exception('Failed to replace file: $e');
    }
  }

  static Future<String?> saveToExternalStorage(String sourcePath) async {
    try {
      if (!await requestStoragePermission()) {
        throw Exception('Storage permission denied');
      }

      final directory = Platform.isAndroid
          ? await getExternalStorageDirectory()
          : await getApplicationDocumentsDirectory();

      if (directory == null) {
        throw Exception('Unable to access external storage');
      }

      final fileName = path.basename(sourcePath);
      final targetPath = path.join(directory.path, fileName);

      // Copy the file
      final bytes = await File(sourcePath).readAsBytes();
      final file = File(targetPath);
      await file.writeAsBytes(bytes);

      return targetPath;
    } catch (e) {
      print('Error saving to external storage: $e');
      return null;
    }
  }

  static Future<String> replacePdfInIsolate(
      String sourcePath, String targetPath) async {
    try {
      final receivePort = ReceivePort();
      final rootIsolateToken = RootIsolateToken.instance!;

      final isolate = await Isolate.spawn(
        _replacePdfIsolate,
        [rootIsolateToken, receivePort.sendPort, sourcePath, targetPath],
      );

      // Wait for result
      final result = await receivePort.first;

      // Clean up isolate
      isolate.kill();
      receivePort.close();

      if (result == 'success') {
        return targetPath;
      } else {
        throw Exception(result);
      }
    } catch (e) {
      throw Exception('Failed to replace file: $e');
    }
  }
}

@pragma('vm:entry-point')
void _replacePdfIsolate(List<dynamic> args) async {
  final RootIsolateToken rootIsolateToken = args[0];
  final SendPort sendPort = args[1];
  final String sourcePath = args[2];
  final String targetPath = args[3];

  BackgroundIsolateBinaryMessenger.ensureInitialized(rootIsolateToken);

  try {
    final sourceFile = File(sourcePath);
    final targetFile = File(targetPath);

    // First read the source file
    final bytes = await sourceFile.readAsBytes();

    // Delete the target file if it exists
    if (await targetFile.exists()) {
      await targetFile.delete();
    }

    // Write the new file
    await targetFile.writeAsBytes(bytes);

    // Delete the source file (temp file)
    await sourceFile.delete();

    sendPort.send('success');
  } catch (e, st) {
    print('File Replacement Error: $e\n$st');
    sendPort.send('error: $e');
  }
}
