// history_screen.dart

// ignore_for_file: unused_import

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async'; // Diperlukan untuk Timer
import 'dart:convert';
import 'dart:typed_data';

import 'scan_document_screen.dart'; // Pastikan DocumentModel diimpor

// ================= WIDGET NOTIFIKASI KUSTOM (BARU) =================
// Kelas ini bertugas untuk menampilkan dan menganimasikan notifikasi.
class CustomNotificationWidget extends StatefulWidget {
  final String message;
  final Color backgroundColor;
  final IconData iconData;
  final VoidCallback onDismiss;

  const CustomNotificationWidget({
    super.key,
    required this.message,
    required this.backgroundColor,
    required this.iconData,
    required this.onDismiss,
  });

  @override
  State<CustomNotificationWidget> createState() => _CustomNotificationWidgetState();
}

class _CustomNotificationWidgetState extends State<CustomNotificationWidget> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Offset> _offsetAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );

    _offsetAnimation = Tween<Offset>(
      begin: const Offset(0, -1.5), // Mulai dari atas layar
      end: Offset.zero, // Berakhir di posisi normal
    ).animate(CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
    ));

    // Mulai animasi masuk
    _controller.forward();

    // Atur timer untuk menutup notifikasi secara otomatis
    Timer(const Duration(seconds: 2), () {
      if (mounted) {
        _controller.reverse().then((_) => widget.onDismiss());
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // SafeArea memastikan notifikasi tidak tertutup oleh status bar sistem (jam, baterai, dll)
    return SafeArea(
      child: SlideTransition(
        position: _offsetAnimation,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          margin: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          decoration: BoxDecoration(
            color: widget.backgroundColor,
            borderRadius: BorderRadius.circular(12),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 10,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              Icon(widget.iconData, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.message,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ================= MANAGER NOTIFIKASI (BARU) =================
// Kelas helper untuk mempermudah menampilkan notifikasi dari mana saja.
class TopNotificationManager {
  static OverlayEntry? _overlayEntry;

  static void show(BuildContext context, String message, {bool isError = false}) {
    // Hapus notifikasi lama jika ada
    if (_overlayEntry != null) {
      _overlayEntry?.remove();
      _overlayEntry = null;
    }

    final Color backgroundColor = isError ? Colors.red.shade600 : Colors.green.shade500;
    final IconData icon = isError ? Icons.error_outline : Icons.check_circle_outline;

    _overlayEntry = OverlayEntry(
      builder: (context) => Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: Material(
          color: Colors.transparent,
          child: CustomNotificationWidget(
            message: message,
            backgroundColor: backgroundColor,
            iconData: icon,
            onDismiss: () {
              if (_overlayEntry != null) {
                _overlayEntry?.remove();
                _overlayEntry = null;
              }
            },
          ),
        ),
      ),
    );

    Overlay.of(context).insert(_overlayEntry!);
  }
}

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

  // Fungsi untuk menampilkan notifikasi kustom
  void _showNotification(String message, {bool isError = false}) {
    if (!mounted) return;
    TopNotificationManager.show(context, message, isError: isError);
  }

  // Logika untuk memulihkan dokumen
  Future<void> _restoreDocument(int index) async {
    final docToRestore = _documents[index];
    
    // Panggil callback onRestore
    widget.onRestore(docToRestore);

    // Hapus dari daftar lokal
    setState(() {
      _documents.removeAt(index);
    });

    // Simpan perubahan ke SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final docsString = _documents.map((doc) => jsonEncode(doc.toJson())).toList();
    await prefs.setStringList(_storageKey, docsString);

    // HAPUS pemanggilan notifikasi dari sini,
    // biarkan notifikasi dipicu oleh `onRestore` di ScanDocumentScreen.
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
      _showNotification('Dokumen dihapus permanen!', isError: true);
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