import 'dart:typed_data';
import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'dart:io';
import 'dart:math';

// A screen for a live camera feed with a custom frame overlay.
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

  // New UI controls for the overlay
  bool _showGuides = true;
  double _frameScale = 0.85; // This value determines the size of the frame.

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  // Initializes the camera controller.
  Future<void> _initCamera() async {
    try {
      // Ensure cameras are available before proceeding.
      _cameras = await availableCameras();
      if (_cameras!.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('Tidak ada kamera tersedia.')));
        }
        return;
      }
      final back = _cameras!.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => _cameras!.first,
      );
      _controller = CameraController(back, ResolutionPreset.high, enableAudio: false);
      await _controller!.initialize();
      if (!mounted) return;
      setState(() => _isInitializing = false);
    } catch (e) {
      if (!mounted) return;
      setState(() => _isInitializing = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal inisialisasi kamera: $e')));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  // Captures a photo and returns the image bytes to the previous screen.
  Future<void> _takePhoto() async {
    if (_controller == null || !_controller!.value.isInitialized || _isTaking) return;
    setState(() => _isTaking = true);
    try {
      final XFile file = await _controller!.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      // Pop the current screen and pass the image bytes back.
      Navigator.of(context).pop<Uint8List>(bytes);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal ambil foto: $e')));
    } finally {
      if (mounted) setState(() => _isTaking = false);
    }
  }

  // Switches between available cameras (front/back).
  Future<void> _switchCamera() async {
    if (_cameras == null || _cameras!.length < 2) return;
    try {
      final current = _controller!.description;
      final idx = _cameras!.indexOf(current);
      final next = _cameras![(idx + 1) % _cameras!.length];
      await _controller!.dispose();
      _controller = CameraController(next, ResolutionPreset.high, enableAudio: false);
      setState(() => _isInitializing = true);
      await _controller!.initialize();
      if (mounted) setState(() => _isInitializing = false);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Gagal ganti kamera: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan - Kamera'),
        actions: [
          IconButton(
            icon: Icon(_showGuides ? Icons.grid_on : Icons.grid_off),
            onPressed: () => setState(() => _showGuides = !_showGuides),
            tooltip: _showGuides ? 'Sembunyikan garis bantu' : 'Tampilkan garis bantu',
          ),
        ],
      ),
      body: _isInitializing
          ? const Center(child: CircularProgressIndicator())
          : Stack(
              children: [
                // Camera preview fills the entire screen
                Positioned.fill(
                  child: _controller != null && _controller!.value.isInitialized
                      ? CameraPreview(_controller!)
                      : const Center(child: Text('Tidak ada preview kamera')),
                ),

                // Overlay painter for the frame and guides
                Positioned.fill(
                  child: LayoutBuilder(builder: (context, constraints) {
                    const double frameAspectRatio = 0.707; // A4-like aspect ratio
                    return CustomPaint(
                      painter: _OverlayPainter(
                        frameAspectRatio: frameAspectRatio,
                        scale: _frameScale.clamp(0.4, 0.98),
                        showGuides: _showGuides,
                        borderColor: Colors.white.withOpacity(0.95),
                        shadeColor: Colors.black.withOpacity(0.45),
                        cornerColor: Colors.lightBlueAccent,
                      ),
                      size: Size(constraints.maxWidth, constraints.maxHeight),
                    );
                  }),
                ),

                // Top UI for info and frame size slider
                Positioned(
                  top: 12,
                  left: 12,
                  right: 12,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.photo_size_select_large, color: Colors.white, size: 18),
                            const SizedBox(width: 8),
                            Text('Bingkai dokumen', style: TextStyle(color: Colors.white.withOpacity(0.95))),
                            const SizedBox(width: 10),
                            Text('${(_frameScale * 100).round()}%', style: TextStyle(color: Colors.white70)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                      SizedBox(
                        height: 36,
                        child: SliderTheme(
                          data: SliderTheme.of(context).copyWith(
                            trackHeight: 2,
                            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                            overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
                          ),
                          child: Slider(
                            value: _frameScale,
                            min: 0.5,
                            max: 0.95,
                            divisions: 9,
                            activeColor: Colors.white,
                            inactiveColor: Colors.white24,
                            onChanged: (v) => setState(() => _frameScale = v),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // Bottom controls (close, capture, switch camera)
                Positioned(
                  bottom: 24,
                  left: 0,
                  right: 0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      FloatingActionButton(
                        onPressed: _isTaking ? null : () => Navigator.of(context).pop(),
                        backgroundColor: Colors.grey.shade700,
                        child: const Icon(Icons.close),
                        heroTag: 'close_camera',
                      ),
                      const SizedBox(width: 24),
                      GestureDetector(
                        onTap: _takePhoto,
                        child: Container(
                          width: 72,
                          height: 72,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: Colors.white, width: 6),
                            color: _isTaking ? Colors.white54 : Colors.white,
                          ),
                          child: Center(
                            child: _isTaking
                                ? const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  )
                                : const Icon(Icons.camera_alt, color: Colors.black),
                          ),
                        ),
                      ),
                      const SizedBox(width: 24),
                      FloatingActionButton(
                        onPressed: _controller != null && _controller!.value.isInitialized ? _switchCamera : null,
                        child: const Icon(Icons.flip_camera_android),
                        heroTag: 'flip_camera',
                      ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}

/// Custom painter that draws a dark mask, a precise centered frame with
/// rounded corners, corner brackets, and an optional rule-of-thirds grid.
class _OverlayPainter extends CustomPainter {
  final double frameAspectRatio; // width / height
  final double scale; // 0.0..1.0 of available shorter side
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
    // Determine the framed document's size
    final double shorterSide = min(size.width, size.height);
    final double frameWidth = shorterSide * scale;
    final double frameHeight = frameWidth / frameAspectRatio;
    
    // adjust if it overflows the screen on either axis
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

    // Main overlay - draw the dark semi-transparent mask
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()..addRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(8)));
    final path = Path.combine(PathOperation.difference, outer, hole);
    final shadePaint = Paint()..color = shadeColor..style = PaintingStyle.fill;
    canvas.drawPath(path, shadePaint);

    // Border
    final borderPaint = Paint()..color = borderColor..style = PaintingStyle.stroke..strokeWidth = 2.2;
    canvas.drawRRect(RRect.fromRectAndRadius(frameRect, const Radius.circular(8)), borderPaint);

    // Corner brackets
    final cornerPaint = Paint()..color = cornerColor..strokeWidth = 4..strokeCap = StrokeCap.round;
    final double bracketLen = min(frameRect.width, frameRect.height) * 0.08;

    // Top-left
    canvas.drawLine(frameRect.topLeft, frameRect.topLeft.translate(bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.topLeft, frameRect.topLeft.translate(0, bracketLen), cornerPaint);

    // Top-right
    canvas.drawLine(frameRect.topRight, frameRect.topRight.translate(-bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.topRight, frameRect.topRight.translate(0, bracketLen), cornerPaint);

    // Bottom-left
    canvas.drawLine(frameRect.bottomLeft, frameRect.bottomLeft.translate(bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.bottomLeft, frameRect.bottomLeft.translate(0, -bracketLen), cornerPaint);

    // Bottom-right
    canvas.drawLine(frameRect.bottomRight, frameRect.bottomRight.translate(-bracketLen, 0), cornerPaint);
    canvas.drawLine(frameRect.bottomRight, frameRect.bottomRight.translate(0, -bracketLen), cornerPaint);
    
    // rule-of-thirds grid and center guide
    if (showGuides) {
      final guidePaint = Paint()
        ..color = Colors.white.withOpacity(0.6)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.0;

      // vertical thirds
      for (int i = 1; i <= 2; i++) {
        final dxv = frameRect.left + frameRect.width * (i / 3);
        canvas.drawLine(Offset(dxv, frameRect.top + 6), Offset(dxv, frameRect.bottom - 6), guidePaint);
      }
      // horizontal thirds
      for (int i = 1; i <= 2; i++) {
        final dyh = frameRect.top + frameRect.height * (i / 3);
        canvas.drawLine(Offset(frameRect.left + 6, dyh), Offset(frameRect.right - 6, dyh), guidePaint);
      }

      // subtle center crosshair
      final center = frameRect.center;
      final crossLen = (frameWidth < frameHeight ? frameWidth : frameHeight) * 0.03;
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
