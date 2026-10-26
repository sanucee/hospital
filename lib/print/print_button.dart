import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:printing/printing.dart';

/// Opens the system print / preview dialog for a generated PDF. On phones
/// and the web this also offers "save as PDF" and sharing.
Future<void> printPdf(
  BuildContext context,
  String name,
  Future<Uint8List> Function() build,
) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    await Printing.layoutPdf(name: name, onLayout: (_) => build());
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Could not print: $e')));
  }
}

class PrintButton extends StatelessWidget {
  const PrintButton({
    super.key,
    required this.name,
    required this.document,
    this.tooltip = 'Print',
  });

  /// File name offered when saving.
  final String name;
  final Future<Uint8List> Function() document;
  final String tooltip;

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    icon: const Icon(Icons.print),
    onPressed: () => printPdf(context, name, document),
  );
}
