// image_viewer_screen.dart

// ignore_for_file: unused_import

import 'dart:typed_data';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:google_mlkit_text_recognition/google_mlkit_text_recognition.dart';
import '../text_display_screen.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';

class ImageViewerScreen extends StatefulWidget {
  final Uint8List image;
  final int? documentId;
  final Function(int, String) onUpdateOcrText;

  const ImageViewerScreen({
    super.key,
    required this.image,
    required Uint8List imageBytes,
    this.documentId,
    required this.onUpdateOcrText,
  });

  @override
  State<ImageViewerScreen> createState() => _ImageViewerScreenState();
}

class _ImageViewerScreenState extends State<ImageViewerScreen> {
  bool _isSaving = false;
  bool _isSharing = false;
  bool _isExtractingText = false;

  Future<PermissionStatus> _requestPermission() async {
    final plugin = DeviceInfoPlugin();
    final androidInfo = await plugin.androidInfo;
    final sdkVersion = androidInfo.version.sdkInt;

    if (sdkVersion >= 30) {
      return Permission.manageExternalStorage.request();
    } else {
      return Permission.storage.request();
    }
  }

  Future<void> _saveDocument(bool asPdf) async {
    setState(() {
      _isSaving = true;
    });

    final status = await _requestPermission();

    if (status.isPermanentlyDenied) {
      if (mounted) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text('Izin Dibutuhkan'),
            content: const Text('Untuk menyimpan dokumen, kami memerlukan akses ke penyimpanan. Mohon izinkan akses di Pengaturan Aplikasi.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('Batal'),
              ),
              TextButton(
                onPressed: () {
                  Navigator.of(context).pop();
                  openAppSettings();
                },
                child: const Text('Buka Pengaturan'),
              ),
            ],
          ),
        );
      }
      setState(() { _isSaving = false; });
      return;
    }

    if (!status.isGranted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin penyimpanan ditolak.')),
        );
      }
      setState(() { _isSaving = false; });
      return;
    }

    try {
      final documentsPath = '/storage/emulated/0/Download/scan';
      final documentsDir = Directory(documentsPath);

      if (!await documentsDir.exists()) {
        await documentsDir.create(recursive: true);
      }

      String filePath;
      if (asPdf) {
        final pdf = pw.Document();
        final imagePdf = pw.MemoryImage(widget.image);
        pdf.addPage(
          pw.Page(
            pageFormat: PdfPageFormat.a4,
            build: (pw.Context context) {
              return pw.Center(
                child: pw.Image(imagePdf),
              );
            },
          ),
        );
        final file = File('$documentsPath/dokumen_scan_${DateTime.now().millisecondsSinceEpoch}.pdf');
        await file.writeAsBytes(await pdf.save());
        filePath = file.path;
      } else {
        final file = File('$documentsPath/dokumen_scan_${DateTime.now().millisecondsSinceEpoch}.jpg');
        await file.writeAsBytes(widget.image);
        filePath = file.path;
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Dokumen berhasil disimpan di: $filePath')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal menyimpan dokumen: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSaving = false;
        });
      }
    }
  }

  Future<void> _extractTextFromImage() async {
    setState(() {
      _isExtractingText = true;
    });

    try {
      final tempDir = await getTemporaryDirectory();
      final tempFile = File('${tempDir.path}/temp_image.jpg');
      await tempFile.writeAsBytes(widget.image);
      final InputImage inputImage = InputImage.fromFile(tempFile);
      
      final textRecognizer = TextRecognizer(script: TextRecognitionScript.latin);
      final RecognizedText recognizedText = await textRecognizer.processImage(inputImage);
      
      await tempFile.delete();

      if (mounted) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => TextDisplayScreen(
              recognizedText: recognizedText,
              documentId: widget.documentId,
              onUpdateOcrText: widget.onUpdateOcrText,
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekstrak teks: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isExtractingText = false;
        });
      }
    }
  }

  void _showDocumentOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.picture_as_pdf),
              title: const Text('Simpan sebagai PDF'),
              onTap: () {
                Navigator.pop(context);
                _saveDocument(true);
              },
            ),
            ListTile(
              leading: const Icon(Icons.image),
              title: const Text('Simpan sebagai Gambar'),
              onTap: () {
                Navigator.pop(context);
                _saveDocument(false);
              },
            ),
          ],
        );
      },
    );
  }

  Future<void> _sharePdf() async {
    setState(() {
      _isSharing = true;
    });

    final pdf = pw.Document();
    final imagePdf = pw.MemoryImage(widget.image);
    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Center(
            child: pw.Image(imagePdf),
          );
        },
      ),
    );

    try {
      final output = await getTemporaryDirectory();
      final file = File("${output.path}/dokumen_scan_share.pdf");
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles([XFile(file.path)], text: 'Dokumen yang di-scan dari Scan Apps!');

      if (mounted) {
        setState(() {
          _isSharing = false;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengekspor PDF untuk dibagikan: $e')),
        );
        setState(() {
          _isSharing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Lihat Dokumen'),
        actions: [
          IconButton(
            icon: _isSharing
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                    ),
                  )
                : const Icon(Icons.share),
            onPressed: _isSharing ? null : _sharePdf,
          ),
        ],
      ),
      body: Center(
        child: InteractiveViewer(
          boundaryMargin: const EdgeInsets.all(20.0),
          minScale: 0.5,
          maxScale: 4.0,
          child: Image.memory(widget.image),
        ),
      ),
      bottomNavigationBar: BottomAppBar(
        color: Colors.white,
        elevation: 8.0,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            ElevatedButton.icon(
              onPressed: _isSaving ? null : _showDocumentOptions,
              icon: _isSaving
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                      ),
                    )
                  : const Icon(Icons.save),
              label: Text(_isSaving ? "Menyimpan..." : "Opsi Dokumen"),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blue.shade600,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
                padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 24),
                elevation: 4,
              ),
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _isExtractingText ? null : _extractTextFromImage,
        child: _isExtractingText
            ? const SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                ),
              )
            : const Icon(Icons.text_fields),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endDocked,
    );
  }
}