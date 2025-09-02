import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';

class TextDisplayScreen extends StatefulWidget {
  final RecognizedText recognizedText;
  final int? documentId;
  final Function(int, String)? onUpdateOcrText;

  const TextDisplayScreen({
    super.key,
    required this.recognizedText,
    this.documentId,
    this.onUpdateOcrText,
  });

  @override
  State<TextDisplayScreen> createState() => _TextDisplayScreenState();
}

class _TextDisplayScreenState extends State<TextDisplayScreen> {
  late TextEditingController _textController;

  @override
  void initState() {
    super.initState();
    String allText = '';
    for (var block in widget.recognizedText.blocks) {
      allText += block.text + '\n\n';
    }
    _textController = TextEditingController(text: allText.trim());
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  void _copyAllText() {
    Clipboard.setData(ClipboardData(text: _textController.text)).then((_) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Semua teks telah disalin ke clipboard!')),
      );
    });
  }

  void _updateText() {
    if (widget.documentId != null && widget.onUpdateOcrText != null) {
      widget.onUpdateOcrText!(widget.documentId!, _textController.text);
      Navigator.pop(context); // Kembali ke halaman sebelumnya setelah berhasil
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Teks Dokumen'),
        actions: [
          if (widget.documentId != null && widget.onUpdateOcrText != null)
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _updateText,
              tooltip: 'Simpan Perubahan',
            ),
          IconButton(
            icon: const Icon(Icons.copy),
            onPressed: _copyAllText,
            tooltip: 'Salin Semua Teks',
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: _textController.text.isEmpty
            ? const Center(
                child: Text(
                  "Tidak ada teks yang ditemukan.",
                  style: TextStyle(fontSize: 16),
                ),
              )
            : TextField(
                controller: _textController,
                maxLines: null,
                decoration: const InputDecoration(border: InputBorder.none),
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontSize: 16,
                    ),
              ),
      ),
    );
  }
}