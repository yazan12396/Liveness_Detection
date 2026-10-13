import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_mlkit_document_scanner/google_mlkit_document_scanner.dart';

class DocumentScanScreen extends StatefulWidget {
  const DocumentScanScreen({super.key});

  @override
  State<DocumentScanScreen> createState() => _DocumentScanScreenState();
}

class _DocumentScanScreenState extends State<DocumentScanScreen> {
  final _scanner = DocumentScanner(
    options: DocumentScannerOptions(
      documentFormats: const {DocumentFormat.jpeg},
      mode: ScannerMode.full,
      pageLimit: 1,
      isGalleryImport: true,
    ),
  );

  String? _imagePath;
  String? _error;
  bool _busy = false;

  @override
  void dispose() {
    _scanner.close();
    super.dispose();
  }

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final result = await _scanner.scanDocument();
      final images = result.images ?? const [];
      if (!mounted) return;
      setState(() {
        if (images.isNotEmpty) _imagePath = images.first;
      });
    } catch (e) {
      // Cancelling the scanner also lands here.
      if (mounted) setState(() => _error = 'لم يكتمل المسح: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final path = _imagePath;
    return Scaffold(
      appBar: AppBar(title: const Text('تصوير الهوية')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: path == null
                  ? const Center(
                      child: Text(
                        'اضغط الزر لتصوير بطاقة الهوية.\n'
                        'سيقوم الماسح بقص البطاقة وتصحيح المنظور تلقائياً.',
                        textAlign: TextAlign.center,
                      ),
                    )
                  : InteractiveViewer(
                      child: Image.file(File(path), fit: BoxFit.contain),
                    ),
            ),
            if (path != null)
              Text(
                path,
                style: Theme.of(context).textTheme.bodySmall,
                textDirection: TextDirection.ltr,
              ),
            if (_error != null)
              Text(_error!, style: const TextStyle(color: Colors.red)),
            const SizedBox(height: 12),
            FilledButton.icon(
              onPressed: _busy ? null : _scan,
              icon: const Icon(Icons.document_scanner),
              label: Text(path == null ? 'ابدأ المسح' : 'إعادة المسح'),
            ),
          ],
        ),
      ),
    );
  }
}
