import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class BelongingCropResult {
  final Uint8List bytes;
  final Rect rect;
  final bool subject;
  const BelongingCropResult(this.bytes, this.rect, this.subject);
  Map<String, dynamic> get metadata => {
    'rect': [rect.left, rect.top, rect.width, rect.height],
    'subject': subject,
  };
}

Future<Uint8List> cropBelongingImage(Uint8List bytes, Rect rect) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  try {
    final source = Rect.fromLTWH(
      rect.left * image.width,
      rect.top * image.height,
      rect.width * image.width,
      rect.height * image.height,
    );
    final width = math.max(1, source.width.round()),
        height = math.max(1, source.height.round());
    final recorder = ui.PictureRecorder();
    Canvas(recorder).drawImageRect(
      image,
      source,
      Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble()),
      Paint()..filterQuality = FilterQuality.high,
    );
    final picture = recorder.endRecording();
    final cropped = await picture.toImage(width, height);
    picture.dispose();
    try {
      final png = await cropped.toByteData(format: ui.ImageByteFormat.png);
      return png!.buffer.asUint8List();
    } finally {
      cropped.dispose();
    }
  } finally {
    image.dispose();
    codec.dispose();
  }
}

/// Crop coordinates always refer to the normalized original, independent of zoom.
class BelongingCropPage extends StatefulWidget {
  final Uint8List original;
  final bool autoSubject;
  final Map<String, dynamic>? edit;
  const BelongingCropPage(
    this.original, {
    super.key,
    this.autoSubject = false,
    this.edit,
  });
  @override
  State<BelongingCropPage> createState() => _BelongingCropPageState();
}

class _BelongingCropPageState extends State<BelongingCropPage> {
  final transform = TransformationController();
  final planeKey = GlobalKey();
  Uint8List? cutout;
  Size? imageSize;
  String? loadError;
  Rect crop = const Rect.fromLTWH(0, 0, 1, 1);
  bool subject = false, extracting = false, saving = false;
  String hint = '拖动四角或边缘裁剪，双指缩放和移动预览';
  @override
  void initState() {
    super.initState();
    final r = widget.edit?['rect'];
    if (r is List && r.length == 4) {
      crop = Rect.fromLTWH(
        (r[0] as num).toDouble(),
        (r[1] as num).toDouble(),
        (r[2] as num).toDouble(),
        (r[3] as num).toDouble(),
      );
    }
    initialize();
  }

  Future<void> initialize() async {
    try {
      final codec = await ui.instantiateImageCodec(widget.original);
      final image = (await codec.getNextFrame()).image;
      final size = Size(image.width.toDouble(), image.height.toDouble());
      image.dispose();
      codec.dispose();
      if (!mounted) return;
      setState(() => imageSize = size);
      if (widget.edit?['subject'] == true ||
          (widget.edit == null && widget.autoSubject)) {
        await extract();
      }
    } catch (_) {
      if (mounted) setState(() => loadError = '原图无法读取，请返回重新选择照片');
    }
  }

  Future<void> extract() async {
    if (cutout != null) {
      setState(() => subject = true);
      return;
    }
    setState(() {
      extracting = true;
      hint = '正在设备上提取物品主体…';
    });
    try {
      final result = await const MethodChannel('com.seafy.yousu/system')
          .invokeMapMethod<String, dynamic>(
            'extractBelongingSubject',
            widget.original,
          );
      if (!mounted) return;
      if (result?['status'] == 'ok' && result?['bytes'] is Uint8List) {
        setState(() {
          cutout = result!['bytes'];
          subject = true;
          hint = '已去除背景，可切回原图；拖动边角调整范围';
        });
      } else {
        setState(
          () => hint = result?['status'] == 'noSubject'
              ? '未识别到清晰主体，已保留原图，可继续裁剪'
              : '此设备暂不支持主体提取，已保留原图',
        );
      }
    } on PlatformException {
      if (mounted) setState(() => hint = '主体提取未完成，已保留原图，可继续裁剪');
    } on MissingPluginException {
      if (mounted) setState(() => hint = '此设备暂不支持主体提取，已保留原图');
    } finally {
      if (mounted) setState(() => extracting = false);
    }
  }

  @override
  void dispose() {
    transform.dispose();
    super.dispose();
  }

  Future<void> save() async {
    setState(() => saving = true);
    try {
      final bytes = await cropBelongingImage(
        subject ? cutout! : widget.original,
        crop,
      );
      if (mounted) {
        Navigator.pop(context, BelongingCropResult(bytes, crop, subject));
      }
    } catch (_) {
      if (mounted) setState(() => hint = '图片处理失败，请重试');
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  void move(Offset globalPosition, Rect fitted, int x, int y) {
    final box = planeKey.currentContext!.findRenderObject() as RenderBox;
    final p = box.globalToLocal(globalPosition);
    final px = ((p.dx - fitted.left) / fitted.width).clamp(0.0, 1.0);
    final py = ((p.dy - fitted.top) / fitted.height).clamp(0.0, 1.0);
    final minX = math.min(crop.width, math.min(.05, 16 / imageSize!.width)),
        minY = math.min(crop.height, math.min(.05, 16 / imageSize!.height));
    var l = crop.left, r = crop.right, t = crop.top, b = crop.bottom;
    if (x == -1) l = px.clamp(0.0, r - minX);
    if (x == 1) r = px.clamp(l + minX, 1.0);
    if (y == -1) t = py.clamp(0.0, b - minY);
    if (y == 1) b = py.clamp(t + minY, 1.0);
    setState(() => crop = Rect.fromLTRB(l, t, r, b));
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(
      title: const Text('裁剪物品照片'),
      actions: [
        TextButton(
          onPressed: saving || extracting || imageSize == null ? null : save,
          child: Text(saving ? '处理中…' : '完成'),
        ),
      ],
    ),
    body: SafeArea(
      child: Column(
        children: [
          Expanded(
            child: imageSize == null
                ? Center(
                    child: loadError == null
                        ? const CircularProgressIndicator()
                        : Text(loadError!),
                  )
                : LayoutBuilder(
                    builder: (context, constraints) {
                      final size = constraints.biggest;
                      final scale = math.min(
                        (size.width - 48) / imageSize!.width,
                        (size.height - 48) / imageSize!.height,
                      );
                      final fitted = Rect.fromCenter(
                        center: size.center(Offset.zero),
                        width: imageSize!.width * scale,
                        height: imageSize!.height * scale,
                      );
                      final selected = Rect.fromLTWH(
                        fitted.left + crop.left * fitted.width,
                        fitted.top + crop.top * fitted.height,
                        crop.width * fitted.width,
                        crop.height * fitted.height,
                      );
                      return InteractiveViewer(
                        transformationController: transform,
                        maxScale: 5,
                        boundaryMargin: const EdgeInsets.all(150),
                        child: SizedBox(
                          key: planeKey,
                          width: size.width,
                          height: size.height,
                          child: Stack(
                            children: [
                              Positioned.fill(
                                child: CustomPaint(painter: _CheckerPainter()),
                              ),
                              Positioned.fromRect(
                                rect: fitted,
                                child: Image.memory(
                                  subject ? cutout! : widget.original,
                                  fit: BoxFit.fill,
                                  gaplessPlayback: true,
                                ),
                              ),
                              Positioned.fill(
                                child: IgnorePointer(
                                  child: CustomPaint(
                                    painter: _CropPainter(selected),
                                  ),
                                ),
                              ),
                              for (final pair in [
                                (-1, -1),
                                (0, -1),
                                (1, -1),
                                (-1, 0),
                                (1, 0),
                                (-1, 1),
                                (0, 1),
                                (1, 1),
                              ])
                                Positioned(
                                  left:
                                      (pair.$1 == -1
                                          ? selected.left
                                          : pair.$1 == 1
                                          ? selected.right
                                          : selected.center.dx) -
                                      22,
                                  top:
                                      (pair.$2 == -1
                                          ? selected.top
                                          : pair.$2 == 1
                                          ? selected.bottom
                                          : selected.center.dy) -
                                      22,
                                  child: Semantics(
                                    label: '裁剪边界 ${pair.$1},${pair.$2}',
                                    child: GestureDetector(
                                      key: Key(
                                        'crop-handle-${pair.$1}-${pair.$2}',
                                      ),
                                      behavior: HitTestBehavior.opaque,
                                      onPanStart: (d) => move(
                                        d.globalPosition,
                                        fitted,
                                        pair.$1,
                                        pair.$2,
                                      ),
                                      onPanUpdate: (d) => move(
                                        d.globalPosition,
                                        fitted,
                                        pair.$1,
                                        pair.$2,
                                      ),
                                      child: SizedBox(
                                        width: 44,
                                        height: 44,
                                        child: Center(
                                          child: Container(
                                            width: pair.$1 == 0 ? 24 : 12,
                                            height: pair.$2 == 0 ? 24 : 12,
                                            decoration: BoxDecoration(
                                              color: Colors.white,
                                              border: Border.all(
                                                color: const Color(0xff226752),
                                                width: 2,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 12, 18, 6),
            child: Text(
              hint,
              style: const TextStyle(fontSize: 13),
              textAlign: TextAlign.center,
            ),
          ),
          if (extracting) const LinearProgressIndicator(),
          Wrap(
            alignment: WrapAlignment.center,
            spacing: 12,
            children: [
              TextButton.icon(
                onPressed: extracting || saving
                    ? null
                    : () => setState(() => subject = false),
                icon: Icon(subject ? Icons.image_outlined : Icons.check),
                label: const Text('原图'),
              ),
              TextButton.icon(
                onPressed: extracting || saving ? null : extract,
                icon: Icon(subject ? Icons.check : Icons.auto_fix_high),
                label: const Text('提取主体'),
              ),
              TextButton(
                onPressed: saving
                    ? null
                    : () => setState(() {
                        crop = const Rect.fromLTWH(0, 0, 1, 1);
                        transform.value = Matrix4.identity();
                      }),
                child: const Text('重置裁剪'),
              ),
            ],
          ),
          const SizedBox(height: 8),
        ],
      ),
    ),
  );
}

class _CropPainter extends CustomPainter {
  final Rect rect;
  _CropPainter(this.rect);
  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawPath(
      Path()
        ..fillType = PathFillType.evenOdd
        ..addRect(Offset.zero & size)
        ..addRect(rect),
      Paint()..color = Colors.black.withValues(alpha: .5),
    );
    canvas.drawRect(
      rect,
      Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );
    for (var n = 1; n < 3; n++) {
      final p = Paint()
        ..color = Colors.white.withValues(alpha: .4)
        ..strokeWidth = .5;
      canvas.drawLine(
        Offset(rect.left + rect.width * n / 3, rect.top),
        Offset(rect.left + rect.width * n / 3, rect.bottom),
        p,
      );
      canvas.drawLine(
        Offset(rect.left, rect.top + rect.height * n / 3),
        Offset(rect.right, rect.top + rect.height * n / 3),
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_CropPainter old) => old.rect != rect;
}

class _CheckerPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    for (double y = 0; y < size.height; y += 16) {
      for (double x = 0; x < size.width; x += 16) {
        canvas.drawRect(
          Rect.fromLTWH(x, y, 16, 16),
          Paint()
            ..color = ((x / 16 + y / 16).round().isEven
                ? const Color(0xffeeeeee)
                : const Color(0xffdddddd)),
        );
      }
    }
  }

  @override
  bool shouldRepaint(_CheckerPainter old) => false;
}
