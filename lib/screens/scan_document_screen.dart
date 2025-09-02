//======== 1. KUMPULAN IMPORT ========
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import 'package:http/http.dart' as http;
import 'package:http_parser/http_parser.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'camera_scan_screen.dart';
import 'document_preview_screen.dart';
import 'image_viewer_screen.dart';
import '../auth/profile_screen.dart';
import '../auth/login_screen.dart';


//======== 2. MODEL DATA ========
class DocumentModel {
  final int? id;
  final String name;
  final Uint8List image;

  DocumentModel({this.id, required this.name, required this.image});

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'name': name,
      'image': base64Encode(image),
    };
  }

  factory DocumentModel.fromJson(Map<String, dynamic> json) {
    return DocumentModel(
      id: json['id'] as int?,
      name: json['name'],
      image: base64Decode(json['image']),
    );
  }
}


//======== 3. LAYAR UTAMA (STATEFUL WIDGET) ========
class ScanDocumentScreen extends StatefulWidget {
  const ScanDocumentScreen({super.key});

  @override
  State<ScanDocumentScreen> createState() => _ScanDocumentScreenState();
}

class _ScanDocumentScreenState extends State<ScanDocumentScreen> {
  final ImagePicker _picker = ImagePicker();
  final List<DocumentModel> _scannedDocuments = [];
  String _userName = '';
  String _userEmail = '';
  final String _deletedDocumentsKey = 'deleted_documents_';

  String get _documentKey => 'documents_$_userEmail';

  @override
  void initState() {
    super.initState();
    _loadUserProfile().then((_) {
      _loadDocuments();
    });
  }

  Future<void> _loadUserProfile() async {
    final prefs = await SharedPreferences.getInstance();
    final email = prefs.getString('currentUserEmail');
    if (email != null) {
      setState(() {
        _userEmail = email;
        _userName = email.split('@')[0];
      });
    }
  }

  Future<void> _loadDocuments() async {
    final prefs = await SharedPreferences.getInstance();
    final documentsString = prefs.getStringList(_documentKey) ?? [];
    setState(() {
      _scannedDocuments.clear();
      for (var docString in documentsString) {
        try {
          final decodedJson = jsonDecode(docString);
          _scannedDocuments.add(DocumentModel.fromJson(decodedJson));
        } catch (e) {
          print('Gagal memuat dokumen dari SharedPreferences: $e');
        }
      }
    });
  }

  Future<void> _saveAndUploadDocument(Uint8List imageBytes, String name) async {
    String extractedText = '';
    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_image.jpg');
      await tempFile.writeAsBytes(imageBytes);
      final InputImage inputImage = InputImage.fromFile(tempFile);

      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);

      extractedText = recognizedText.text;
      await tempFile.delete();

      if (extractedText.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Teks tidak ditemukan pada dokumen.')),
          );
        }
      }
    } catch (e) {
      extractedText = '';
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('OCR gagal: $e')),
        );
      }
    }

    final url = 'http://192.168.8.127:8000/api/documents';
    try {
      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.fields['name'] = name;
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        imageBytes,
        filename: '$name.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));

      var response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(responseBody);
        final int documentId = data['document_id'];

        final prefs = await SharedPreferences.getInstance();
        final documentsString = prefs.getStringList(_documentKey) ?? [];
        final newDocument = DocumentModel(id: documentId, name: name, image: imageBytes);
        documentsString.add(jsonEncode(newDocument.toJson()));
        await prefs.setStringList(_documentKey, documentsString);
        await _loadDocuments();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dokumen berhasil diunggah!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal mengunggah dokumen. Status: ${response.statusCode}. Pesan: $responseBody')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terjadi kesalahan saat mengunggah: $e')),
        );
      }
    }
  }

  Future<void> _deleteDocument(int index) async {
    final docToDelete = _scannedDocuments[index];

    final prefs = await SharedPreferences.getInstance();
    final deletedDocumentsString = prefs.getStringList(_deletedDocumentsKey + _userEmail) ?? [];
    deletedDocumentsString.add(jsonEncode(docToDelete.toJson()));
    await prefs.setStringList(_deletedDocumentsKey + _userEmail, deletedDocumentsString);

    if (docToDelete.id != null) {
      final url = 'http://192.168.8.127:8000/api/documents/${docToDelete.id}';
      try {
        final response = await http.delete(Uri.parse(url));
        if (response.statusCode >= 200 && response.statusCode < 300) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Dokumen berhasil dihapus dari server!')),
            );
          }
        } else {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text('Gagal menghapus dokumen dari server. Status: ${response.statusCode}')),
            );
          }
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Terjadi kesalahan saat menghapus: $e')),
          );
        }
      }
    }

    setState(() {
      _scannedDocuments.removeAt(index);
    });
    final documentsString = _scannedDocuments.map((doc) => jsonEncode(doc.toJson())).toList();
    await prefs.setStringList(_documentKey, documentsString);
  }

  //====================== PERUBAHAN DI SINI ======================
  Future<void> _restoreDocument(DocumentModel docToRestore) async {
    final url = 'http://192.168.8.127:8000/api/documents';
    try {
      var request = http.MultipartRequest('POST', Uri.parse(url));
      request.fields['name'] = docToRestore.name;
      request.files.add(http.MultipartFile.fromBytes(
        'image',
        docToRestore.image,
        filename: '${docToRestore.name}.jpg',
        contentType: MediaType('image', 'jpeg'),
      ));

      var response = await request.send();
      final responseBody = await response.stream.bytesToString();

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = jsonDecode(responseBody);
        final int newDocumentId = data['document_id'];

        final restoredDocumentWithNewId = DocumentModel(
          id: newDocumentId,
          name: docToRestore.name,
          image: docToRestore.image,
        );

        final prefs = await SharedPreferences.getInstance();

        final deletedDocumentsString = prefs.getStringList(_deletedDocumentsKey + _userEmail) ?? [];
        deletedDocumentsString.removeWhere((item) {
          final docJson = jsonDecode(item);
          return docJson['name'] == docToRestore.name && docJson['image'] == base64Encode(docToRestore.image);
        });
        await prefs.setStringList(_deletedDocumentsKey + _userEmail, deletedDocumentsString);

        final currentDocumentsString = prefs.getStringList(_documentKey) ?? [];
        currentDocumentsString.add(jsonEncode(restoredDocumentWithNewId.toJson()));
        await prefs.setStringList(_documentKey, currentDocumentsString);

        await _loadDocuments();

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Dokumen berhasil dipulihkan ke server!')),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memulihkan ke server. Status: ${response.statusCode}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Terjadi kesalahan saat memulihkan: $e')),
        );
      }
    }
  }

  Future<void> _scanFromCamera() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const CameraScanScreen()),
    );
    if (result != null && result is Uint8List) {
      final croppedImageBytes = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DocumentPreviewScreen(imageBytes: result)),
      );
      if (croppedImageBytes != null && croppedImageBytes is Map<String, dynamic>) {
        final Uint8List image = croppedImageBytes['image'];
        final String name = croppedImageBytes['name'];
        await _saveAndUploadDocument(image, name);
      }
    }
  }

  Future<void> _scanFromGallery() async {
    final pickedFile = await _picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final imageBytes = await pickedFile.readAsBytes();
      final croppedImageBytes = await Navigator.push(
        context,
        MaterialPageRoute(builder: (context) => DocumentPreviewScreen(imageBytes: imageBytes)),
      );
      if (croppedImageBytes != null && croppedImageBytes is Map<String, dynamic>) {
        final Uint8List image = croppedImageBytes['image'];
        final String name = croppedImageBytes['name'];
        await _saveAndUploadDocument(image, name);
      }
    }
  }

  void _viewDocument(int index) {
    final DocumentModel doc = _scannedDocuments[index];
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ImageViewerScreen(
          image: doc.image,
          imageBytes: doc.image,
          documentId: doc.id,
          onUpdateOcrText: (docId, newText) {
            _updateOcrText(docId, newText, index);
          },
        ),
      ),
    );
  }

  Future<void> _updateOcrText(int documentId, String newText, int localIndex) async {
    final url = Uri.parse('http://192.168.8.127:8000/api/documents/$documentId');
    try {
      final response = await http.put(
        url,
        headers: {
          'Content-Type': 'application/json',
        },
        body: json.encode({
          'ocr_text': newText,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Teks dokumen berhasil diperbarui.')),
          );
        }
        setState(() {
          _scannedDocuments[localIndex] = DocumentModel(
            id: _scannedDocuments[localIndex].id,
            name: _scannedDocuments[localIndex].name,
            image: _scannedDocuments[localIndex].image,
          );
        });
        final prefs = await SharedPreferences.getInstance();
        final documentsString = _scannedDocuments.map((doc) => jsonEncode(doc.toJson())).toList();
        await prefs.setStringList(_documentKey, documentsString);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Gagal memperbarui teks dokumen. Status: ${response.statusCode}. Respon: ${response.body}')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memperbarui teks: $e')),
        );
      }
    }
  }

  Future<void> _editDocumentImage(int index) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => DocumentPreviewScreen(imageBytes: _scannedDocuments[index].image),
      ),
    );

    if (result != null && result is Map<String, dynamic>) {
      final Uint8List newImage = result['image'];
      final String newName = result['name'];

      final newDoc = DocumentModel(name: newName, image: newImage);
      setState(() {
        _scannedDocuments[index] = newDoc;
      });

      final prefs = await SharedPreferences.getInstance();
      final documentsString = _scannedDocuments.map((doc) => jsonEncode(doc.toJson())).toList();
      await prefs.setStringList(_documentKey, documentsString);
    }
  }

  Future<void> _editDocumentName(int index) async {
    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Opsi Dokumen'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.edit),
                title: const Text('Ubah Nama'),
                onTap: () {
                  Navigator.of(context).pop();
                  _showEditNameDialog(index);
                },
              ),
              ListTile(
                leading: const Icon(Icons.image),
                title: const Text('Ubah Gambar'),
                onTap: () {
                  Navigator.of(context).pop();
                  _editDocumentImage(index);
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Future<void> _showEditNameDialog(int index) async {
    final TextEditingController editNameController = TextEditingController(text: _scannedDocuments[index].name);

    await showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Edit Nama Dokumen'),
          content: TextField(
            controller: editNameController,
            decoration: const InputDecoration(labelText: 'Nama Baru'),
            autofocus: true,
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Batal'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Simpan'),
              onPressed: () async {
                if (editNameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nama tidak boleh kosong!')),
                  );
                  return;
                }

                setState(() {
                  _scannedDocuments[index] = DocumentModel(
                    id: _scannedDocuments[index].id,
                    name: editNameController.text.trim(),
                    image: _scannedDocuments[index].image,
                  );
                });

                final prefs = await SharedPreferences.getInstance();
                final documentsString = _scannedDocuments.map((doc) => jsonEncode(doc.toJson())).toList();
                await prefs.setStringList(_documentKey, documentsString);

                Navigator.of(context).pop();
              },
            ),
          ],
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(
          'DocScan'.toUpperCase(),
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 28.0,
            letterSpacing: 2.0,
          ),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.person),
            onPressed: () async {
              final prefs = await SharedPreferences.getInstance();
              final isLoggedIn = prefs.getBool('isLoggedIn') ?? false;
              if (isLoggedIn) {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => ProfileScreen(
                      userEmail: _userEmail,
                      onRestore: _restoreDocument,
                    ),
                  ),
                );
                _loadDocuments();
              } else {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (context) => const LoginScreen()),
                );
              }
            },
            tooltip: 'Profil',
          ),
        ],
      ),
      // Memanggil komponen UI yang sudah didefinisikan di bawah
      body: DocListView(
        documents: _scannedDocuments,
        onDelete: _deleteDocument,
        onView: _viewDocument,
        onEdit: _editDocumentName,
      ),
      floatingActionButton: DocScanFab(
        onScanFromCamera: _scanFromCamera,
        onScanFromGallery: _scanFromGallery,
      ),
    );
  }
}


//======== 4. KOMPONEN UI: DAFTAR DOKUMEN (STATELESS WIDGET) ========
class DocListView extends StatelessWidget {
  final List<DocumentModel> documents;
  final Function(int) onDelete;
  final Function(int) onView;
  final Function(int) onEdit;

  const DocListView({
    super.key,
    required this.documents,
    required this.onDelete,
    required this.onView,
    required this.onEdit,
  });

  @override
  Widget build(BuildContext context) {
    return documents.isEmpty
        ? const Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.folder_open,
                  size: 80,
                  color: Colors.grey,
                ),
                SizedBox(height: 16),
                Text(
                  "Tidak ada dokumen yang dipindai.",
                  style: TextStyle(fontSize: 18, color: Colors.grey),
                ),
                SizedBox(height: 8),
                Text(
                  "Mulai pindai dokumen pertama Anda!",
                  style: TextStyle(fontSize: 14, color: Colors.grey),
                ),
              ],
            ),
          )
        : ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 16.0, horizontal: 8.0),
            itemCount: documents.length,
            itemBuilder: (context, index) {
              final doc = documents[index];
              final bool isImageValid = doc.image.isNotEmpty;

              return Dismissible(
                key: Key(doc.name + index.toString()),
                background: Container(
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  padding: const EdgeInsets.only(left: 20.0),
                  color: Colors.red.shade400,
                  alignment: Alignment.centerLeft,
                  child: const Row(
                    children: [
                      Icon(Icons.delete_sweep, color: Colors.white, size: 30),
                      SizedBox(width: 8),
                      Text("Hapus", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
                direction: DismissDirection.startToEnd,
                onDismissed: (direction) => onDelete(index),
                child: GestureDetector(
                  onTap: () => onView(index),
                  onLongPress: () => onEdit(index),
                  child: Card(
                    elevation: 5,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(15),
                    ),
                    margin: const EdgeInsets.symmetric(vertical: 8),
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: isImageValid
                                ? Image.memory(
                                    doc.image,
                                    width: 70,
                                    height: 70,
                                    fit: BoxFit.cover,
                                  )
                                : const SizedBox(
                                    width: 70,
                                    height: 70,
                                    child: Icon(Icons.broken_image, color: Colors.grey),
                                  ),
                          ),
                          const SizedBox(width: 16),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  doc.name,
                                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                  ),
                                  maxLines: 2,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Tekan lama untuk edit",
                                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
  }
}


//======== 5. KOMPONEN UI: TOMBOL AKSI (STATELESS WIDGET) ========
class DocScanFab extends StatelessWidget {
  final VoidCallback onScanFromCamera;
  final VoidCallback onScanFromGallery;

  const DocScanFab({
    super.key,
    required this.onScanFromCamera,
    required this.onScanFromGallery,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        FloatingActionButton.extended(
          heroTag: "camera",
          onPressed: onScanFromCamera,
          icon: const Icon(Icons.camera_alt),
          label: const Text("Kamera"),
        ),
        const SizedBox(height: 12),
        FloatingActionButton.extended(
          heroTag: "gallery",
          onPressed: onScanFromGallery,
          icon: const Icon(Icons.image),
          label: const Text("Galeri"),
        ),
      ],
    );
  }
}