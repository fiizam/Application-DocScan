// ignore_for_file: unused_import

import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math' as math; // Tambahkan import ini
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

class CameraScanScreen extends StatefulWidget {
  const CameraScanScreen({super.key});

  @override
  State<CameraScanScreen> createState() => _CameraScanScreenState();
}

class _CameraScanScreenState extends State<CameraScanScreen> {
  CameraController? _controller;
  bool _isInitializing = true;
  bool _isTaking = false;
  List<CameraDescription>? _cameras;
  bool _showGuides = true;
  double _frameScale = 0.85;
  bool _isFlashOn = false;

  @override
  void initState() {
    super.initState();
    _checkPermissionAndInitCamera();
  }

  Future<void> _checkPermissionAndInitCamera() async {
    final cameraStatus = await Permission.camera.request();
    if (cameraStatus.isGranted) {
      await _initCamera();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Izin kamera diperlukan untuk scan dokumen')),
        );
      }
    }
  }

  Future<void> _initCamera() async {
    try {
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Tidak ada kamera tersedia')),
          );
        }
        return;
      }

      final back = _cameras!.firstWhere(
        (camera) => camera.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );

      _controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      if (mounted) {
        setState(() => _isInitializing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error inisialisasi kamera: $e')),
        );
      }
    }
  }

  Future<void> _toggleFlash() async {
    if (_controller == null || !_controller!.value.isInitialized) return;
    try {
      if (_controller!.value.flashMode == FlashMode.off) {
        await _controller!.setFlashMode(FlashMode.torch);
      } else {
        await _controller!.setFlashMode(FlashMode.off);
      }
      setState(() => _isFlashOn = !_isFlashOn);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal mengubah mode flash')),
      );
    }
  }

  Future<void> _processAndSaveImage(XFile file) async {
    try {
      final bytes = await file.readAsBytes();
      if (mounted) Navigator.of(context).pop<Uint8List>(bytes);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal memproses gambar: $e')),
        );
      }
    }
  }

  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTaking) return;
    
    setState(() => _isTaking = true);
    try {
      final XFile file = await _controller!.takePicture();
      await _processAndSaveImage(file);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengambil foto: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _isTaking = false);
    }
  }

  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    
    try {
      final current = _controller!.description;
      final idx = _cameras!.indexOf(current);
      final next = _cameras![(idx + 1) % _cameras!.length];
      
      await _controller!.dispose();
      _controller = CameraController(
        next,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      
      setState(() => _isInitializing = true);
      await _controller!.initialize();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal mengganti kamera: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan Dokumen'),
        actions: [
          // Toggle flash button
          IconButton(
            icon: Icon(_isFlashOn ? Icons.flash_on : Icons.flash_off),
            onPressed: _toggleFlash,
            tooltip: 'Toggle Flash',
          ),
          // Toggle guide lines button
          IconButton(
            icon: Icon(_showGuides ? Icons.grid_on : Icons.grid_off),
            onPressed: () => setState(() => _showGuides = !_showGuides),
            tooltip: _showGuides ? 'Sembunyikan Panduan' : 'Tampilkan Panduan',
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Camera preview
                if (_controller != null && _controller!.value.isInitialized)
                  Positioned.fill(
                    child: AspectRatio(
                      aspectRatio: _controller!.value.aspectRatio,
                      child: CameraPreview(_controller!),
                    ),
                  ),

                // Document frame overlay
                if (_showGuides)
                  Positioned.fill(
                    child: CustomPaint(
                      painter: _OverlayPainter(
                        frameAspectRatio: 0.707,
                        scale: _frameScale,
                        showGuides: _showGuides,
                        borderColor: Colors.white.withOpacity(0.95),
                        shadeColor: Colors.black.withOpacity(0.45),
                        cornerColor: Colors.lightBlueAccent,
                      ),
                    ),
                  ),

                // Bottom controls
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 24,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      FloatingActionButton(
                        heroTag: 'close',
                        onPressed: () => Navigator.pop(context),
                        backgroundColor: Colors.red,
                        child: const Icon(Icons.close),
                      ),
                      FloatingActionButton.large(
                        heroTag: 'capture',
                        onPressed: _isTaking ? null : _takePhoto,
                        child: _isTaking
                            ? const CircularProgressIndicator(color: Colors.white)
                            : const Icon(Icons.camera_alt, size: 36),
                      ),
                      FloatingActionButton(
                        heroTag: 'switch',
                        onPressed: _switchCamera,
                        child: const Icon(Icons.flip_camera_ios),
                      ),
                    ],
                  ),
                ),

                // Frame size indicator
                Positioned(
                  top: 16,
                  left: 0,
                  right: 0,
                  child: Column(
                    children: [
                      Text(
                        'Ukuran Frame: ${(_frameScale * 100).round()}%',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Slider(
                        value: _frameScale,
                        min: 0.5,
                        max: 0.95,
                        divisions: 9,
                        onChanged: (v) => setState(() => _frameScale = v),
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

class _OverlayPainter extends CustomPainter {
  final double frameAspectRatio;
  final double scale;
  final bool showGuides;
  final Color borderColor;
  final Color shadeColor;
  final Color cornerColor;

  _OverlayPainter({
    required this.frameAspectRatio,
    required this.scale,
    required this.showGuides,
    required this.borderColor,
    required this.shadeColor,
    required this.cornerColor,
  });

  @override
  void paint(Canvas canvas, Size size) {
    // Gunakan math.min untuk mengakses fungsi min
    final double shorterSide = math.min(size.width, size.height);
    final double frameWidth = shorterSide * scale;
    final double frameHeight = frameWidth / frameAspectRatio;
    
    Rect frameRect;
    if (frameHeight > size.height) {
      final newHeight = size.height * scale;
      final newWidth = newHeight * frameAspectRatio;
      frameRect = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: newWidth.clamp(100, size.width),
          height: newHeight.clamp(100, size.height));
    } else {
      frameRect = Rect.fromCenter(
          center: size.center(Offset.zero),
          width: frameWidth.clamp(100, size.width),
          height: frameHeight.clamp(100, size.height));
    }

    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(8)));
    final path = Path.combine(PathOperation.difference, outer, hole);
    final shadePaint = Paint()..color = shadeColor..style = PaintingStyle.fill;
    canvas.drawPath(path, shadePaint);

    final borderPaint = Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = 2.2;
    canvas.drawRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(8)), borderPaint);

    final cornerPaint = Paint()..color = cornerColor..strokeWidth = 4..strokeCap = StrokeCap.round;
    // Gunakan math.min untuk corner brackets
    final double bracketLen = math.min(frameRect.width, frameRect.height) * 0.08;

    // Corner brackets
    canvas.drawLine(frameRect.topLeft, frameRect.topLeft.translate(bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.topLeft, frameRect.topLeft.translate(0, bracketLen), cornerPaint);

    canvas.drawLine(frameRect.topRight, frameRect.topRight.translate(-bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.topRight, frameRect.topRight.translate(0, bracketLen), cornerPaint);

    canvas.drawLine(frameRect.bottomLeft, frameRect.bottomLeft.translate(bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.bottomLeft, frameRect.bottomLeft.translate(0, -bracketLen), cornerPaint);

    canvas.drawLine(frameRect.bottomRight, frameRect.bottomRight.translate(-bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.bottomRight, frameRect.bottomRight.translate(0, -bracketLen), cornerPaint);
    
    if (showGuides) {
      final guidePaint = Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      for (int i = 1; i <= 2; i++) {
        final dxv = frameRect.left + frameRect.width * (i / 3);
        canvas.drawLine(Offset(dxv, frameRect.top + 6), Offset(dxv, frameRect.bottom - 6), guidePaint);
      }

      for (int i = 1; i <= 2; i++) {
        final dyh = frameRect.top + frameRect.height * (i / 3);
        canvas.drawLine(Offset(frameRect.left + 6, dyh), Offset(frameRect.right - 6, dyh), guidePaint);
      }

      final center = frameRect.center;
      // Gunakan math.min untuk crosshair
      final crossLen = (math.min(frameWidth, frameHeight)) * 0.03;
      final crossPaint = Paint()
        ..color = Colors.white.withOpacity(0.9)
        ..strokeWidth = 1.6
        ..strokeCap = StrokeCap.round;
      canvas.drawLine(center.translate(-crossLen, 0), center.translate(crossLen, 0), crossPaint);
      canvas.drawLine(center.translate(0, -crossLen), center.translate(0, crossLen), crossPaint);
    }
  }

  @override
  bool shouldRepaint(covariant _OverlayPainter oldDelegate) {
    return oldDelegate.scale != scale || oldDelegate.showGuides != showGuides;
  }
}