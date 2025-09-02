import 'dart:typed_data';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

// Enum untuk tipe filter warna
enum ColorFilterType {
  original,
  blackAndWhite,
  warm,
  cool,
}

class DocumentPreviewScreen extends StatefulWidget {
  final Uint8List imageBytes;
  const DocumentPreviewScreen({super.key, required this.imageBytes});

  @override
  State<DocumentPreviewScreen> createState() => _DocumentPreviewScreenState();
}

class _DocumentPreviewScreenState extends State<DocumentPreviewScreen> {
  late img.Image _origImage;
  bool _busy = true;
  Rect? _frameRect;
  Offset? _dragStart;
  Rect? _startFrame;
  Rect? _initialFrameOnScale;
  ColorFilterType _selectedFilter = ColorFilterType.original;
  Uint8List? _previewImageBytes;
  final TextEditingController _nameController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadImage();
    _nameController.text = 'Dokumen Baru';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  Future<void> _loadImage() async {
    final decoded = img.decodeImage(widget.imageBytes);
    if (decoded == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal decode gambar')));
        Navigator.of(context).pop();
      }
      return;
    }
    _origImage = decoded;
    _previewImageBytes = widget.imageBytes;
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    setState(() => _busy = false);
  }

  img.Image _applyFilter(img.Image image, ColorFilterType filter) {
    if (image.data == null) {
      return image;
    }
    final filteredImage = img.Image.fromBytes(
      width: image.width,
      height: image.height,
      bytes: image.data!.buffer,
    );
    switch (filter) {
      case ColorFilterType.original:
        return image;
      case ColorFilterType.blackAndWhite:
        return img.grayscale(img.contrast(filteredImage, contrast: 170));
      case ColorFilterType.warm:
        for (final p in filteredImage) {
          p.r = (p.r * 1.1).round().clamp(0, 255);
          p.g = (p.g * 1.05).round().clamp(0, 255);
          p.b = (p.b * 0.95).round().clamp(0, 255);
        }
        return filteredImage;
      case ColorFilterType.cool:
        for (final p in filteredImage) {
          p.r = (p.r * 0.95).round().clamp(0, 255);
          p.g = (p.g * 1.05).round().clamp(0, 255);
          p.b = (p.b * 1.1).round().clamp(0, 255);
        }
        return filteredImage;
    }
  }

  Rect _mapDisplayRectToImage(Rect displayFrame, Size displaySize) {
    final double imgW = _origImage.width.toDouble();
    final double imgH = _origImage.height.toDouble();
    final FittedSizes fs = applyBoxFit(BoxFit.contain, Size(imgW, imgH), displaySize);
    final Size dstSize = fs.destination;
    final double scale = dstSize.width / imgW;
    final double renderW = imgW * scale;
    final double renderH = imgH * scale;
    final double offsetX = (displaySize.width - renderW) / 2;
    final double offsetY = (displaySize.height - renderH) / 2;

    final double left = (displayFrame.left - offsetX) / scale;
    final double top = (displayFrame.top - offsetY) / scale;
    final double width = displayFrame.width / scale;
    final double height = displayFrame.height / scale;

    final double lx = left.clamp(0, imgW);
    final double ty = top.clamp(0, imgH);
    final double wcl = width.clamp(1, imgW - lx);
    final double hcl = height.clamp(1, imgH - ty);

    return Rect.fromLTWH(lx, ty, wcl, hcl);
  }

  Future<Uint8List?> _cropAndSaveImage() async {
    try {
      final displaySize = MediaQuery.of(context).size;
      final imageRect = _mapDisplayRectToImage(_frameRect!, displaySize);
      
      final cx = imageRect.left.round();
      final cy = imageRect.top.round();
      final cw = imageRect.width.round();
      final ch = imageRect.height.round();
      final cropped = img.copyCrop(_origImage, x: cx, y: cy, width: cw, height: ch);
      
      final finalImage = _applyFilter(cropped, _selectedFilter);
      final jpg = img.encodeJpg(finalImage, quality: 92);
      return Uint8List.fromList(jpg);
    } catch (_) {
      return null;
    }
  }

  void _showSaveDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (BuildContext context) {
        return AlertDialog(
          title: const Text('Simpan Dokumen'),
          content: TextField(
            controller: _nameController,
            decoration: const InputDecoration(
              labelText: 'Nama Dokumen',
              hintText: 'Masukkan nama dokumen...',
            ),
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
                if (_nameController.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Nama dokumen tidak boleh kosong!')),
                  );
                  return;
                }
                
                final croppedData = await _cropAndSaveImage();
                if (croppedData == null) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Gagal memproses gambar.')));
                  }
                  return;
                }
                
                if (mounted) {
                  Navigator.of(context).pop();
                  // Mengembalikan Map berisi data gambar dan nama dokumen
                  Navigator.of(context).pop({
                    'image': croppedData,
                    'name': _nameController.text.trim(),
                  });
                }
              },
            ),
          ],
        );
      },
    );
  }

  void _showFilterOptions() {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildFilterOption(ColorFilterType.original, 'Original'),
            _buildFilterOption(ColorFilterType.blackAndWhite, 'Hitam Putih'),
            _buildFilterOption(ColorFilterType.warm, 'Hangat'),
            _buildFilterOption(ColorFilterType.cool, 'Dingin'),
          ],
        );
      },
    );
  }

  Widget _buildFilterOption(ColorFilterType filterType, String name) {
    final bool isSelected = _selectedFilter == filterType;
    return ListTile(
      leading: Icon(
        _getFilterIcon(filterType),
        color: isSelected ? Colors.blue : Colors.black,
      ),
      title: Text(
        name,
        style: TextStyle(
          color: isSelected ? Colors.blue : Colors.black,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      trailing: isSelected ? const Icon(Icons.check, color: Colors.blue) : null,
      onTap: () {
        setState(() {
          _selectedFilter = filterType;
          _updatePreview();
        });
        Navigator.pop(context);
      },
    );
  }

  IconData _getFilterIcon(ColorFilterType filterType) {
    switch (filterType) {
      case ColorFilterType.original:
        return Icons.image;
      case ColorFilterType.blackAndWhite:
        return Icons.brightness_4;
      case ColorFilterType.warm:
        return Icons.wb_sunny;
      case ColorFilterType.cool:
        return Icons.cloud;
    }
  }

  void _updatePreview() {
    if (_origImage.data == null) {
      return;
    }
    final imageCopy = img.Image.fromBytes(
      width: _origImage.width,
      height: _origImage.height,
      bytes: _origImage.data!.buffer,
    );
    final imageWithFilter = _applyFilter(imageCopy, _selectedFilter);
    _previewImageBytes = Uint8List.fromList(img.encodeJpg(imageWithFilter));
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Preview Dokumen'),
        actions: [
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
      body: _busy
          ? const Center(child: CircularProgressIndicator())
          : LayoutBuilder(builder: (context, bc) {
              final displaySize = Size(bc.maxWidth, bc.maxHeight);
              if (_frameRect == null) {
                final double w = displaySize.width * 0.9;
                final double h = displaySize.height * 0.9;
                final double size = min(w, h);
                final dx = (displaySize.width - size) / 2;
                final dy = (displaySize.height - size) / 2;
                _frameRect = Rect.fromLTWH(dx, dy, size, size);
              }

              return Column(
                children: [
                  Expanded(
                    child: Stack(
                      children: [
                        Positioned.fill(
                          child: Container(
                            color: Colors.black,
                            child: _previewImageBytes != null
                                ? FittedBox(
                                    fit: BoxFit.contain,
                                    child: Image.memory(_previewImageBytes!),
                                  )
                                : const Center(child: CircularProgressIndicator()),
                          ),
                        ),
                        Positioned.fill(
                          child: GestureDetector(
                            onScaleStart: (details) {
                              _dragStart = details.localFocalPoint;
                              _startFrame = _frameRect;
                              _initialFrameOnScale = _frameRect;
                            },
                            onScaleUpdate: (details) {
                              if (_startFrame == null || _initialFrameOnScale == null) return;
                              if (details.scale != 1.0) {
                                final scale = details.scale;
                                final f = _initialFrameOnScale!;
                                final newW = (f.width * scale).clamp(40.0, displaySize.width);
                                final newH = (f.height * scale).clamp(40.0, displaySize.height);
                                final cx = f.center.dx;
                                final cy = f.center.dy;
                                final left = (cx - newW / 2).clamp(0.0, displaySize.width - newW);
                                final top = (cy - newH / 2).clamp(0.0, displaySize.height - newH);
                                setState(() => _frameRect = Rect.fromLTWH(left, top, newW, newH));
                              }
                              else if (_dragStart != null) {
                                final delta = details.localFocalPoint - _dragStart!;
                                final newRect = _startFrame!.shift(delta);
                                final dx = newRect.left.clamp(0.0, displaySize.width - newRect.width);
                                final dy = newRect.top.clamp(0.0, displaySize.height - newRect.height);
                                setState(() => _frameRect = Rect.fromLTWH(dx, dy, newRect.width, newRect.height));
                              }
                            },
                            onScaleEnd: (_) {
                              _dragStart = null;
                              _startFrame = null;
                              _initialFrameOnScale = null;
                            },
                            child: CustomPaint(
                              size: displaySize,
                              painter: _PreviewOverlayPainter(frame: _frameRect!),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              );
            }),
      floatingActionButton: Column(
        mainAxisAlignment: MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          FloatingActionButton(
            heroTag: "filter",
            onPressed: _showFilterOptions,
            backgroundColor: Colors.white,
            foregroundColor: Colors.blue,
            child: const Icon(Icons.filter_list),
          ),
          const SizedBox(height: 16),
          FloatingActionButton(
            heroTag: "save",
            onPressed: _showSaveDialog,
            backgroundColor: Colors.blue,
            foregroundColor: Colors.white,
            child: const Icon(Icons.check),
          ),
        ],
      ),
    );
  }
}

class _PreviewOverlayPainter extends CustomPainter {
  final Rect frame;
  _PreviewOverlayPainter({required this.frame});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..isAntiAlias = true;
    final outer = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final hole = Path()..addRect(frame);
    outer.addPath(hole, Offset.zero);
    outer.fillType = PathFillType.evenOdd;
    paint.color = Colors.black.withOpacity(0.5);
    paint.style = PaintingStyle.fill;
    canvas.drawPath(outer, paint);

    final border = Paint()..style = PaintingStyle.stroke..color = Colors.white..strokeWidth = 2.2;
    canvas.drawRect(frame, border);

    final corner = Paint()..color = Colors.lightBlueAccent..strokeWidth = 4..strokeCap = StrokeCap.round;
    final double len = min(frame.width, frame.height) * 0.08;
    canvas.drawLine(frame.topLeft, frame.topLeft.translate(len, 0), corner);
    canvas.drawLine(frame.topLeft, frame.topLeft.translate(0, len), corner);
    canvas.drawLine(frame.topRight, frame.topRight.translate(-len, 0), corner);
    canvas.drawLine(frame.topRight, frame.topRight.translate(0, len), corner);
    canvas.drawLine(frame.bottomLeft, frame.bottomLeft.translate(len, 0), corner);
    canvas.drawLine(frame.bottomLeft, frame.bottomLeft.translate(0, -len), corner);
    canvas.drawLine(frame.bottomRight, frame.bottomRight.translate(-len, 0), corner);
    canvas.drawLine(frame.bottomRight, frame.bottomRight.translate(0, -len), corner);
  }

  @override
  bool shouldRepaint(covariant _PreviewOverlayPainter oldDelegate) {
    return oldDelegate.frame != frame;
  }
}