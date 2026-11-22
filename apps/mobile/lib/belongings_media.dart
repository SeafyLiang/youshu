import 'dart:ui' as ui;

import 'dart:io';

import 'package:image_picker/image_picker.dart';
import 'package:flutter/services.dart';

import 'belongings_crop.dart';

import 'package:flutter/material.dart';

import 'belongings_store.dart';

class BelongingPhotoEdit {
  final String media;
  final String? source;
  final BJson metadata;
  const BelongingPhotoEdit(this.media, this.source, this.metadata);
}

Future<BelongingPhotoEdit?> pickBelongingPhoto(
  BuildContext context,
  BelongingsStore store, {
  bool cover = false,
  String? source,
  BJson? edit,
}) async {
  final choice = await showModalBottomSheet<String>(
    context: context,
    builder: (c) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.photo_library_outlined),
            title: const Text('从相册选择'),
            onTap: () => Navigator.pop(c, 'gallery'),
          ),
          ListTile(
            leading: const Icon(Icons.camera_alt_outlined),
            title: const Text('拍照添加'),
            onTap: () => Navigator.pop(c, 'camera'),
          ),
          if (source != null)
            ListTile(
              leading: const Icon(Icons.crop),
              title: const Text('重新裁剪 / 还原原图'),
              onTap: () => Navigator.pop(c, 'edit'),
            ),
        ],
      ),
    ),
  );
  if (choice == null) return null;
  Uint8List bytes;
  if (choice == 'edit') {
    bytes = await store.mediaFile(source!).readAsBytes();
  } else {
    try {
      final selected = await ImagePicker().pickImage(
        source: choice == 'camera' ? ImageSource.camera : ImageSource.gallery,
        requestFullMetadata: false,
      );
      if (selected == null) return null;
      if (await selected.length() > 10 * 1024 * 1024) {
        throw const FormatException('请选择 10 MB 以内的图片');
      }
      bytes = await selected.readAsBytes();
    } on PlatformException catch (e) {
      throw FormatException(
        e.code.contains('access') ? '请在系统设置中允许使用相机或照片' : '无法打开相机或照片，请重试',
      );
    }
    if (bytes.isEmpty || bytes.length > 10 * 1024 * 1024) {
      throw const FormatException('请选择 10 MB 以内的图片');
    }
    if (Platform.isIOS) {
      bytes = (await const MethodChannel('com.seafy.yousu/system')
          .invokeMethod<Uint8List>('normalizeBelongingPhoto', bytes))!;
    } else {
      bytes = await normalizeBelongingImage(bytes);
    }
  }
  if (!context.mounted) return null;
  final result = await Navigator.of(context).push<BelongingCropResult>(
    MaterialPageRoute(
      builder: (_) => BelongingCropPage(
        bytes,
        autoSubject: cover,
        edit: choice == 'edit' ? edit : null,
      ),
    ),
  );
  if (result == null) return null;
  final original = cover ? await store.addMedia(bytes) : null;
  return BelongingPhotoEdit(
    await store.addMedia(result.bytes),
    original,
    result.metadata,
  );
}

Future<String?> pickBelongingImage(
  BuildContext context,
  BelongingsStore store,
) async => (await pickBelongingPhoto(context, store))?.media;

Future<Uint8List> normalizeBelongingImage(Uint8List bytes) async {
  ui.ImmutableBuffer? buffer;
  ui.ImageDescriptor? descriptor;
  ui.Codec? codec;
  ui.Image? image;
  try {
    buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width * descriptor.height > 80000000) {
      throw const FormatException('图片尺寸过大');
    }
    final scale =
        1600 /
        (descriptor.width > descriptor.height
            ? descriptor.width
            : descriptor.height);
    codec = await descriptor.instantiateCodec(
      targetWidth: scale < 1 ? (descriptor.width * scale).round() : null,
      targetHeight: scale < 1 ? (descriptor.height * scale).round() : null,
    );
    image = (await codec.getNextFrame()).image;
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    if (data == null) throw const FormatException('无法读取图片');
    return data.buffer.asUint8List();
  } catch (_) {
    throw const FormatException('无法读取图片，请选择有效照片');
  } finally {
    image?.dispose();
    codec?.dispose();
    descriptor?.dispose();
    buffer?.dispose();
  }
}

class BelongingImage extends StatelessWidget {
  final BelongingsStore store;
  final String icon;
  final String? media;
  final double size, radius;
  const BelongingImage(
    this.store, {
    super.key,
    required this.icon,
    this.media,
    this.size = 64,
    this.radius = 14,
  });
  @override
  Widget build(BuildContext context) => ClipRRect(
    borderRadius: BorderRadius.circular(radius),
    child: SizedBox(
      width: size,
      height: size,
      child: media == null
          ? Image.asset('assets/belongings/$icon.png', fit: BoxFit.cover)
          : Image.file(
              store.mediaFile(media!),
              fit: BoxFit.contain,
              cacheWidth: 640,
              errorBuilder: (_, _, _) => const ColoredBox(
                color: Color(0xffe9eeeb),
                child: Icon(Icons.broken_image_outlined),
              ),
            ),
    ),
  );
}
