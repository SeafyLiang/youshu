import 'notices.dart';

import 'dart:convert';
import 'dart:collection';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:file_picker/file_picker.dart';
import 'package:crypto/crypto.dart';
import 'package:xml/xml.dart';

import 'icon_names.dart';
import 'category_templates.dart';

String visualIcon(Map<String, dynamic> ledger, Map<String, dynamic>? entry) =>
    ledger['icon_overrides']?[entry?['id']] ??
    recommendedIconNames[entry?['data']?['name']] ??
    entry?['data']?['icon'] ??
    'category';

class IconCatalog {
  static final _cache = _DecodedIconCache();
  static Map<String, Uint8List> get custom => _cache;
  static void register(Map<String, dynamic> ledger) {
    _cache.syncSources({
      ..._cache.sources,
      ..._sources([ledger]),
    });
  }

  static Map<String, String> _sources(Iterable<Map<String, dynamic>> ledgers) =>
      {
        for (final ledger in ledgers)
          for (final item in (ledger['custom_icons'] as Map? ?? {}).entries)
            if (item.key is String &&
                item.value is String &&
                (item.value as String).length <= 180000)
              item.key as String: item.value as String,
      };

  static void sync(Iterable<Map<String, dynamic>> ledgers) {
    _cache.syncSources(_sources(ledgers));
  }

  static bool validPng(Uint8List b) =>
      b.length >= 24 &&
      b.length <= 128 * 1024 &&
      b[0] == 137 &&
      b[1] == 80 &&
      ByteData.sublistView(b).getUint32(16) <= 192 &&
      ByteData.sublistView(b).getUint32(20) <= 192;
}

class _DecodedIconCache extends MapBase<String, Uint8List> {
  final Map<String, Uint8List> _bytes = {};
  final _invalid = <String>{};
  Map<String, String> sources = {};
  int _size = 0;

  void syncSources(Map<String, String> next) {
    for (final key in _bytes.keys.toList()) {
      if (sources[key] == next[key]) continue;
      final value = next[key];
      if (value == null || base64Encode(_bytes[key]!) != value) remove(key);
    }
    _invalid.removeWhere((key) => sources[key] != next[key]);
    sources = next;
  }

  @override
  Uint8List? operator [](Object? key) {
    final cached = _bytes.remove(key);
    if (cached != null) {
      _bytes[key as String] = cached;
      return cached;
    }
    final source = sources[key];
    if (source == null || _invalid.contains(key)) return null;
    try {
      final bytes = base64Decode(source);
      if (IconCatalog.validPng(bytes)) {
        this[key as String] = bytes;
        return bytes;
      }
    } catch (_) {
      // Corrupt uploaded images use the existing default icon fallback.
    }
    _invalid.add(key as String);
    return null;
  }

  @override
  void operator []=(String key, Uint8List value) {
    remove(key);
    _invalid.remove(key);
    _bytes[key] = value;
    _size += value.length;
    while (_bytes.length > 64 || _size > 8 * 1024 * 1024) {
      remove(_bytes.keys.first);
    }
  }

  @override
  Iterable<String> get keys => _bytes.keys.toList(growable: false);
  @override
  Uint8List? remove(Object? key) {
    final bytes = _bytes.remove(key);
    if (bytes != null) _size -= bytes.length;
    return bytes;
  }

  @override
  void clear() {
    _bytes.clear();
    _invalid.clear();
    sources = {};
    _size = 0;
  }
}

const legacyAnt = {
  'category': 'appstore',
  'restaurant': 'coffee',
  'bus': 'car',
  'book': 'read',
  'game': 'play-circle',
  'shopping': 'shopping',
  'home': 'home',
  'flight': 'rocket',
  'favorite': 'heart',
  'work': 'bank',
  'gift': 'gift',
  'transfer': 'swap',
};

class CatalogIcon extends StatelessWidget {
  final String name;
  final double size;
  final Color? color;
  const CatalogIcon(this.name, {super.key, this.size = 24, this.color});
  @override
  Widget build(BuildContext c) {
    final b = IconCatalog.custom[name];
    if (b != null) {
      return Image.memory(
        b,
        width: size,
        height: size,
        cacheWidth: 96,
        cacheHeight: 96,
        errorBuilder: (c, e, s) =>
            Icon(Icons.image_outlined, size: size, color: color),
      );
    }
    final key = name.startsWith('ant:') ? name.substring(4) : legacyAnt[name];
    if (key == null || !antIconNames.contains(key)) {
      return Icon(Icons.category_outlined, size: size, color: color);
    }
    return SvgPicture.asset(
      'assets/ant-icons/$key.svg',
      width: size,
      height: size,
      colorFilter: ColorFilter.mode(
        color ?? Theme.of(c).colorScheme.onSurface,
        BlendMode.srcIn,
      ),
    );
  }
}

String sanitizeSvg(String value) {
  if (value.length > 128 * 1024 ||
      value.contains('<!') ||
      RegExp(
        r'<\s*(script|foreignObject|image|use|style)\b',
        caseSensitive: false,
      ).hasMatch(value)) {
    throw const FormatException('SVG 包含不支持的内容');
  }
  final doc = XmlDocument.parse(value),
      nodes = doc.descendants.whereType<XmlElement>().toList();
  if (doc.rootElement.name.local != 'svg' || nodes.length > 1500) {
    throw const FormatException('SVG 过于复杂');
  }
  const allowed = {
    'svg',
    'g',
    'path',
    'circle',
    'ellipse',
    'rect',
    'line',
    'polygon',
    'polyline',
    'defs',
    'linearGradient',
    'radialGradient',
    'stop',
    'clipPath',
    'title',
    'desc',
  };
  for (final n in nodes) {
    if (!allowed.contains(n.name.local)) {
      throw const FormatException('SVG 包含不支持的元素');
    }
    for (final a in n.attributes) {
      if (a.name.qualified == 'xmlns' &&
          a.value == 'http://www.w3.org/2000/svg') {
        continue;
      }
      if (a.name.local.toLowerCase().startsWith('on') ||
          a.name.local == 'href' ||
          RegExp(
            r'https?:|file:|data:|url\(',
            caseSensitive: false,
          ).hasMatch(a.value)) {
        throw const FormatException('请使用不含外部引用的 SVG');
      }
    }
  }
  return doc.toXmlString();
}

Future<Uint8List> iconPng(Uint8List bytes, String name) async {
  if (bytes.length > 512 * 1024) throw const FormatException('图片需小于 512 KB');
  ui.Image image;
  if (name.toLowerCase().endsWith('.svg')) {
    final svg = sanitizeSvg(utf8.decode(bytes)),
        picture = await vg.loadPicture(SvgStringLoader(svg), null);
    final size = picture.size;
    if (!size.width.isFinite ||
        size.width <= 0 ||
        size.height <= 0 ||
        !size.height.isFinite) {
      picture.picture.dispose();
      throw const FormatException('图标尺寸无效');
    }
    final recorder = ui.PictureRecorder(), canvas = Canvas(recorder);
    final scale = 96 / mathMax(size.width, size.height);
    canvas.translate(
      (96 - size.width * scale) / 2,
      (96 - size.height * scale) / 2,
    );
    canvas.scale(scale);
    canvas.drawPicture(picture.picture);
    final rendered = recorder.endRecording();
    image = await rendered.toImage(96, 96);
    rendered.dispose();
    picture.picture.dispose();
  } else {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes),
        descriptor = await ui.ImageDescriptor.encoded(buffer);
    if (descriptor.width > 4096 || descriptor.height > 4096) {
      descriptor.dispose();
      buffer.dispose();
      throw const FormatException('图片尺寸不能超过 4096');
    }
    final codec = await descriptor.instantiateCodec(
      targetWidth: 96,
      targetHeight: 96,
    );
    image = (await codec.getNextFrame()).image;
    codec.dispose();
    descriptor.dispose();
    buffer.dispose();
  }
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  final png = data!.buffer.asUint8List();
  if (!IconCatalog.validPng(png)) throw const FormatException('图标转换失败');
  return png;
}

double mathMax(double a, double b) => a > b ? a : b;

class IconChoice {
  final String key;
  final String? image;
  const IconChoice(this.key, [this.image]);
}

class IconPickerPage extends StatefulWidget {
  final String selected;
  final Map<String, dynamic> ledger;
  const IconPickerPage(this.ledger, this.selected, {super.key});
  @override
  State<IconPickerPage> createState() => _IconPickerPageState();
}

class _IconPickerPageState extends State<IconPickerPage> {
  String query = '';
  bool loading = false;
  Future<void> upload() async {
    setState(() => loading = true);
    try {
      final file = await FilePicker.pickFile(
        type: FileType.custom,
        allowedExtensions: ['png', 'jpg', 'jpeg', 'svg'],
      );
      if (file == null) return;
      if ((await file.length() ?? 0) > 512 * 1024) {
        throw const FormatException('图片需小于 512 KB');
      }
      final bytes = BytesBuilder();
      await for (final chunk in file.readAsByteStream()) {
        bytes.add(chunk);
        if (bytes.length > 512 * 1024) {
          throw const FormatException('图片需小于 512 KB');
        }
      }
      final png = await iconPng(bytes.takeBytes(), file.name),
          key = 'custom:${sha256.convert(png).toString()}';
      IconCatalog.custom[key] = png;
      if (mounted) Navigator.pop(context, IconChoice(key, base64Encode(png)));
    } catch (e) {
      if (mounted) {
        notifyApp(
          e.toString().replaceFirst('FormatException: ', ''),
          error: true,
        );
      }
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  @override
  Widget build(BuildContext c) {
    final names =
        [
              ...((widget.ledger['custom_icons'] as Map?)?.keys
                      .cast<String>() ??
                  <String>[]),
              ...antIconNames.map((n) => 'ant:$n'),
            ]
            .where(
              (n) =>
                  query.isEmpty ||
                  n.contains(query.toLowerCase()) ||
                  (aliases[n.substring(n.startsWith('ant:') ? 4 : 0)] ?? '')
                      .contains(query),
            )
            .toList();
    return Scaffold(
      appBar: AppBar(
        title: const Text('图标'),
        actions: [
          TextButton(
            onPressed: loading ? null : upload,
            child: const Text('上传'),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索图标',
              ),
              onChanged: (v) => setState(() => query = v),
            ),
          ),
          if (loading) const LinearProgressIndicator(),
          Expanded(
            child: GridView.builder(
              padding: const EdgeInsets.all(16),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 64,
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
              ),
              itemCount: names.length,
              itemBuilder: (c, i) => Tooltip(
                message:
                    aliases[names[i].replaceFirst('ant:', '')] ??
                    names[i].replaceFirst('ant:', ''),
                child: InkWell(
                  key: ValueKey(names[i]),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.pop(c, IconChoice(names[i])),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: names[i] == widget.selected
                          ? Theme.of(c).colorScheme.primaryContainer
                          : Theme.of(c).colorScheme.surface,
                    ),
                    alignment: Alignment.center,
                    child: CatalogIcon(names[i]),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

const aliases = {
  'account-book': '账本预算',
  'alipay': '支付宝',
  'wechat': '微信',
  'car': '汽车交通',
  'coffee': '咖啡餐饮',
  'shopping': '购物',
  'gift': '礼物红包',
  'home': '家庭居住',
  'heart': '健康爱心',
  'read': '阅读学习',
  'bank': '银行工资',
  'wallet': '钱包账户',
  'credit-card': '银行卡',
  'mobile': '手机数码',
  'desktop': '电脑办公',
  'laptop': '笔记本',
  'camera': '相机',
  'picture': '照片',
  'book': '书籍',
  'bulb': '灯泡电费',
  'medicine-box': '医疗药品',
  'rest': '垃圾清洁',
  'skin': '衣服服饰',
  'smile': '心情',
  'rocket': '旅行飞行',
  'global': '地球旅行',
  'environment': '位置地点',
  'shop': '商店',
  'shopping-cart': '购物车',
  'team': '家庭共享',
  'user': '个人',
  'dollar': '美元钱',
  'pay-circle': '支付',
  'money-collect': '收入',
  'fund': '投资基金',
  'stock': '股票',
  'insurance': '保险',
  'safety': '安全',
  'cloud': '云备份',
  'wifi': '网络宽带',
  'phone': '电话通信',
  'tool': '维修工具',
  'usb': '配件',
  'key': '钥匙',
  'calendar': '日历',
  'clock-circle': '时间',
  'tag': '标签',
  'trophy': '奖杯奖金',
  'video-camera': '电影视频',
  'play-circle': '娱乐游戏',
  'sound': '音乐',
  'customer-service': '耳机',
  'apple': '苹果',
  'fire': '燃气',
  'thunderbolt': '电力',
  'experiment': '实验',
  'gold': '黄金',
  'flower': '花卉',
  'sun': '太阳',
  'moon': '月亮',
};
