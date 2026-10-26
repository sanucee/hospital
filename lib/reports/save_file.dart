import 'dart:typed_data';

import 'package:file_saver/file_saver.dart';
import 'package:flutter/material.dart';

/// Downloads (web) or saves (other platforms) an Excel workbook.
Future<void> saveXlsx(
  BuildContext context,
  String name,
  Uint8List bytes,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final path = await FileSaver.instance.saveFile(
      name: name,
      bytes: bytes,
      fileExtension: 'xlsx',
      mimeType: MimeType.microsoftExcel,
    );
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          path.isEmpty ? 'Downloaded $name.xlsx' : 'Saved to $path',
        ),
      ),
    );
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not save: $e')));
  }
}
