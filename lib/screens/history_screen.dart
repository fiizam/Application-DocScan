// history_screen.dart

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:convert';
import 'scan_document_screen.dart'; // Pastikan DocumentModel diimpor

// Enum untuk menentukan jenis histori yang akan ditampilkan
enum HistoryType { deleted, downloaded }

class HistoryScreen extends StatefulWidget {
  final String userEmail;
  final HistoryType historyType;
  final Function(DocumentModel) onRestore;

  const HistoryScreen({
    super.key,
    required this.userEmail,
    required this.historyType,
    required this.onRestore,
  });

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<DocumentModel> _documents = [];
  late String _title;
  late String _storageKey;

  @override
  void initState() {
    super.initState();
    _initialize();
    _loadDocumentsHistory();
  }

  // Mengatur judul dan kunci SharedPreferences berdasarkan tipe histori
  void _initialize() {
    if (widget.historyType == HistoryType.deleted) {
      _title = 'Histori Dokumen Dihapus';
      _storageKey = 'deleted_documents_${widget.userEmail}';
    } else {
      _title = 'Histori Dokumen Diunduh';
      // Ganti dengan key yang sesuai untuk dokumen diunduh
      _storageKey = 'downloaded_documents_${widget.userEmail}';
    }
  }

  // Logika untuk memuat data dari SharedPreferences dipindahkan ke sini
  Future<void> _loadDocumentsHistory() async {
    final prefs = await SharedPreferences.getInstance();
    final docsString = prefs.getStringList(_storageKey) ?? [];
    if (mounted) {
      setState(() {
        _documents = docsString
            .map((docString) => DocumentModel.fromJson(jsonDecode(docString)))
            .toList();
      });
    }
  }

  // Logika untuk memulihkan dokumen
  Future<void> _restoreDocument(int index) async {
    final docToRestore = _documents[index];
    
    // Panggil callback onRestore yang dioper dari ProfileScreen -> ScanDocumentScreen
    widget.onRestore(docToRestore);

    // Hapus dari daftar lokal
    setState(() {
      _documents.removeAt(index);
    });

    // Simpan perubahan ke SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final docsString = _documents.map((doc) => jsonEncode(doc.toJson())).toList();
    await prefs.setStringList(_storageKey, docsString);

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dokumen berhasil dipulihkan!')),
      );
    }
  }

  // Logika untuk menghapus permanen
  Future<void> _deletePermanent(int index) async {
    // Hapus dari daftar lokal
    setState(() {
      _documents.removeAt(index);
    });

    // Simpan perubahan ke SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final docsString = _documents.map((doc) => jsonEncode(doc.toJson())).toList();
    await prefs.setStringList(_storageKey, docsString);
    
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Dokumen berhasil dihapus permanen!')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    bool canRestore = widget.historyType == HistoryType.deleted;

    return Scaffold(
      appBar: AppBar(
        title: Text(_title),
        backgroundColor: Colors.blue.shade600,
        foregroundColor: Colors.white,
      ),
      body: _documents.isEmpty
          ? Center(
              child: Text(
                'Belum ada dokumen di sini.',
                style: TextStyle(fontSize: 16, color: Colors.grey.shade600),
              ),
            )
          : ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 8),
              itemCount: _documents.length,
              itemBuilder: (context, index) {
                final doc = _documents[index];
                return Card(
                  elevation: 2,
                  margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                  child: ListTile(
                    leading: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: Image.memory(
                        doc.image,
                        width: 50,
                        height: 50,
                        fit: BoxFit.cover,
                      ),
                    ),
                    title: Text(doc.name),
                    subtitle: Text(_title),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (canRestore) // Hanya tampilkan tombol pulihkan jika itu adalah histori hapus
                          IconButton(
                            icon: const Icon(Icons.restore, color: Colors.blue),
                            onPressed: () => _restoreDocument(index),
                            tooltip: 'Pulihkan',
                          ),
                        IconButton(
                          icon: const Icon(Icons.delete_forever, color: Colors.red),
                          onPressed: () {
                            showDialog(
                              context: context,
                              builder: (BuildContext dialogContext) {
                                return AlertDialog(
                                  title: const Text('Hapus Permanen?'),
                                  content: const Text(
                                      'Apakah Anda yakin ingin menghapus dokumen ini secara permanen?'),
                                  actions: <Widget>[
                                    TextButton(
                                      child: const Text('Batal'),
                                      onPressed: () => Navigator.of(dialogContext).pop(),
                                    ),
                                    TextButton(
                                      child: const Text('Hapus'),
                                      onPressed: () {
                                        Navigator.of(dialogContext).pop();
                                        _deletePermanent(index);
                                      },
                                    ),
                                  ],
                                );
                              },
                            );
                          },
                          tooltip: 'Hapus Permanen',
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
    );
  }
}