import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import 'store.dart';
import 'ui.dart';

const officialUpdatesEnabled = bool.fromEnvironment('YOUSHU_OFFICIAL_UPDATES');

const releaseEndpoint =
    'https://youshu.894700104.xyz:8443/site/app-release.json';
const releaseFallback =
    'https://youshu-site.894700104.xyz/site/app-release.json';
Json validateRelease(Json data, Uri endpoint) {
  final url = endpoint.resolve(data['url'] as String);
  if (url.scheme != 'https' ||
      url.origin != endpoint.origin ||
      url.userInfo.isNotEmpty ||
      !url.path.endsWith('.apk') ||
      data['build'] is! int ||
      data['bytes'] is! int ||
      data['bytes'] <= 0 ||
      data['bytes'] > 250 * 1024 * 1024 ||
      !RegExp(r'^[a-f0-9]{64}$').hasMatch(data['sha256'] ?? '') ||
      data['version'] is! String) {
    throw const FormatException('更新信息不合法');
  }
  return {
    ...data,
    'downloadUrl': url
        .replace(
          queryParameters: {...url.queryParameters, 'sha': data['sha256']},
        )
        .toString(),
  };
}

class UpdatePage extends StatefulWidget {
  const UpdatePage({super.key});
  @override
  State<UpdatePage> createState() => _UpdatePageState();
}

Future<String> _fileHash(String path) async =>
    (await sha256.bind(File(path).openRead()).first).toString();

class _UpdatePageState extends State<UpdatePage> with WidgetsBindingObserver {
  Json? release, installed;
  http.Client? client;
  bool busy = false, ready = false, downloading = false;
  bool cancelled = false, permissionPending = false, installing = false;
  int received = 0;
  String status = '正在检查更新', path = '';
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    check();
  }

  @override
  void dispose() {
    cancelled = true;
    client?.close();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && permissionPending) {
      permissionPending = false;
      resumeInstall();
    }
  }

  Future<void> resumeInstall() async {
    try {
      final allowed = await system.invokeMethod<bool>('canInstallUpdates');
      if (mounted && allowed == true && ready) await install();
    } catch (_) {
      /* The visible install button remains available. */
    }
  }

  void cancel() {
    cancelled = true;
    client?.close();
  }

  Future<void> check() async {
    if (!officialUpdatesEnabled) {
      setState(() => status = '自行构建版本请从源码更新；官方安装包请前往官网获取。');
      return;
    }
    if (busy) return;
    setState(() {
      busy = true;
      cancelled = false;
      ready = false;
      release = null;
      received = 0;
      status = '正在检查更新';
    });
    try {
      installed = Map<String, dynamic>.from(
        await system.invokeMethod('appVersion'),
      );
      for (final endpoint in [releaseEndpoint, releaseFallback]) {
        if (cancelled || !mounted) return;
        final current = http.Client();
        client = current;
        try {
          final request = http.Request(
            'GET',
            Uri.parse('$endpoint?t=${DateTime.now().millisecondsSinceEpoch}'),
          )..followRedirects = false;
          final response = await current
              .send(request)
              .timeout(const Duration(seconds: 15));
          if (response.statusCode != 200) {
            throw const FormatException('更新服务暂时不可用');
          }
          final body = await response.stream.bytesToString().timeout(
            const Duration(seconds: 15),
          );
          if (cancelled || !mounted) return;
          release = validateRelease(jsonDecode(body), Uri.parse(endpoint));
          break;
        } catch (_) {
          if (endpoint == releaseFallback) rethrow;
        } finally {
          current.close();
        }
      }
      if (cancelled || !mounted) return;
      status = release!['build'] > installed!['build']
          ? '发现新版本 ${release!['version']}'
          : '当前已是最新版本 ${installed!['version']}';
    } catch (_) {
      status = '检查失败，请重试';
    } finally {
      if (cancelled) status = '已取消检查';
      if (mounted) setState(() => busy = false);
    }
  }

  Future<void> download() async {
    if (busy || release == null) return;
    final target = Map<String, dynamic>.from(release!);
    setState(() {
      busy = true;
      downloading = true;
      cancelled = false;
      received = 0;
      status = '正在应用内下载';
      ready = false;
    });
    IOSink? sink;
    File? temporaryFile;
    final current = http.Client();
    client = current;
    try {
      final folder = await system.invokeMethod<String>('updateDirectory');
      if (folder == null) throw const FormatException('无法打开下载目录');
      if (cancelled || !mounted) return;
      path = '$folder/youshu-update.apk';
      final file = File('$path.${DateTime.now().microsecondsSinceEpoch}.part');
      temporaryFile = file;
      final request = http.Request('GET', Uri.parse(target['downloadUrl']))
        ..followRedirects = false;
      final response = await current
          .send(request)
          .timeout(const Duration(seconds: 20));
      if (response.statusCode != 200 ||
          (response.contentLength != null &&
              response.contentLength != target['bytes'])) {
        throw const FormatException('安装包长度不匹配');
      }
      sink = file.openWrite();
      final repaint = Stopwatch()..start();
      await for (final chunk in response.stream.timeout(
        const Duration(seconds: 30),
      )) {
        if (cancelled || !mounted) break;
        received += chunk.length;
        if (received > target['bytes']) {
          throw const FormatException('安装包超出声明长度');
        }
        sink.add(chunk);
        if (repaint.elapsedMilliseconds >= 120) {
          if (mounted) setState(() {});
          repaint.reset();
        }
      }
      await sink.close();
      sink = null;
      if (cancelled || !mounted) return;
      setState(() => status = '正在校验安装包');
      if (received != target['bytes'] ||
          await compute(_fileHash, file.path) != target['sha256']) {
        throw const FormatException('安装包校验失败');
      }
      if (cancelled || !mounted) return;
      await file.rename(path);
      ready = true;
      status = '下载完成 · SHA-256 校验通过';
      if (mounted) notifyApp('下载完成，可以安装更新');
    } catch (_) {
      status = '下载失败，请重试';
    } finally {
      await sink?.close();
      current.close();
      if (temporaryFile != null && await temporaryFile.exists()) {
        await temporaryFile.delete();
      }
      if (cancelled) status = '已取消下载';
      if (mounted) {
        setState(() {
          busy = false;
          downloading = false;
        });
      }
    }
  }

  Future<void> install() async {
    if (!ready || installing) return;
    setState(() => installing = true);
    try {
      final launched = await system.invokeMethod<bool>('installUpdate', {
        'path': path,
        'build': release!['build'],
      });
      permissionPending = launched == false;
      if (mounted) {
        setState(
          () => status = launched == true ? '已打开系统安装器，请确认安装' : '允许安装应用后返回即可继续',
        );
      }
    } catch (_) {
      if (mounted) setState(() => status = '无法安装，请重新下载安装包');
    } finally {
      if (mounted) setState(() => installing = false);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: AppBar(title: const Text('检查更新')),
    body: ListView(
      padding: EdgeInsets.all(pageGutter(context)),
      children: [
        const SizedBox(height: 20),
        Center(
          child: Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primaryContainer,
              borderRadius: BorderRadius.circular(26),
            ),
            child: const Icon(Icons.system_update_rounded, size: 38),
          ),
        ),
        const SizedBox(height: 20),
        Text(
          status,
          textAlign: TextAlign.center,
          style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 22),
        panel(
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (installed != null)
                Text('当前版本 ${installed!['version']} (${installed!['build']})'),
              if (release != null) ...[
                space,
                hint(
                  '官网版本 ${release!['version']} (${release!['build']}) · ${(release!['bytes'] / 1048576).toStringAsFixed(1)} MB',
                ),
              ],
              if (busy) ...[
                space,
                LinearProgressIndicator(
                  value: downloading && received > 0
                      ? received / release!['bytes']
                      : null,
                ),
                space,
                Text(
                  downloading
                      ? '${(received / 1048576).toStringAsFixed(1)} MB · ${release == null ? 0 : (received / release!['bytes'] * 100).round()}%'
                      : '正在连接更新服务',
                ),
                TextButton(onPressed: cancel, child: const Text('取消')),
              ],
            ],
          ),
        ),
        if (!busy && ready)
          FilledButton(
            onPressed: installing ? null : install,
            child: const Text('安装更新'),
          ),
        if (!busy &&
            !ready &&
            release != null &&
            release!['build'] > (installed?['build'] ?? 999999))
          FilledButton(onPressed: download, child: const Text('下载更新')),
        if (!busy) TextButton(onPressed: check, child: const Text('重新检查')),
        space,
        Center(child: hint('应用内下载，由系统确认安装')),
      ],
    ),
  );
}
