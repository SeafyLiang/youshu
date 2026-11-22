import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:youshu/store.dart';
import 'package:youshu/update_page.dart';

void main() {
  if (!officialUpdatesEnabled) {
    testWidgets('自行构建默认关闭官方更新通道', (t) async {
      var requests = 0;
      await http.runWithClient(
        () async {
          await t.pumpWidget(const MaterialApp(home: UpdatePage()));
          await t.pumpAndSettle();
          expect(find.textContaining('自行构建版本请从源码更新'), findsOneWidget);
          expect(requests, 0);
        },
        () => MockClient((request) async {
          requests++;
          return http.Response('', 500);
        }),
      );
    });
    return;
  }

  for (final valid in [false, true]) {
    testWidgets(valid ? '下载校验后才允许调用安装器' : '篡改安装包不可安装并清除半成品', (t) async {
      final dir = Directory.systemTemp.createTempSync('youshu-update-test-');
      final bytes = utf8.encode('isolated apk fixture');
      final calls = <String>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(system, (call) async {
            calls.add(call.method);
            switch (call.method) {
              case 'appVersion':
                return {'version': '0.2.1', 'build': 3};
              case 'updateDirectory':
                return dir.path;
              case 'installUpdate':
                expect(call.arguments['build'], 4);
                expect(await File(call.arguments['path']).readAsBytes(), bytes);
                return true;
            }
            return null;
          });
      addTearDown(() async {
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(system, null);
        dir.deleteSync(recursive: true);
      });
      await http.runWithClient(
        () async {
          await t.pumpWidget(const MaterialApp(home: UpdatePage()));
          await t.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 100)),
          );
          await t.pumpAndSettle();
          expect(find.text('发现新版本 0.3.0'), findsOneWidget);
          await t.runAsync(() async {
            await t.tap(find.text('下载更新'));
            await Future<void>.delayed(const Duration(seconds: 1));
          });
          await t.pumpAndSettle();
          expect(
            File('${dir.path}/youshu-update.apk.part').existsSync(),
            isFalse,
          );
          if (valid) {
            expect(find.text('下载完成 · SHA-256 校验通过'), findsOneWidget);
            await t.runAsync(() async {
              await t.tap(find.text('安装更新'));
              await Future<void>.delayed(const Duration(milliseconds: 100));
            });
            await t.pumpAndSettle();
            expect(calls, contains('installUpdate'));
            for (
              var attempt = 0;
              attempt < 30 && find.text('已打开系统安装器，请确认安装').evaluate().isEmpty;
              attempt++
            ) {
              await t.runAsync(
                () => Future<void>.delayed(const Duration(milliseconds: 100)),
              );
              await t.pumpAndSettle();
            }
            expect(find.text('已打开系统安装器，请确认安装'), findsOneWidget);
          } else {
            expect(find.text('安装更新'), findsNothing);
            expect(calls, isNot(contains('installUpdate')));
            expect(File('${dir.path}/youshu-update.apk').existsSync(), isFalse);
          }
        },
        () => MockClient((request) async {
          if (request.url.path.endsWith('.json')) {
            return http.Response(
              jsonEncode({
                'version': '0.3.0',
                'build': 4,
                'bytes': bytes.length,
                'sha256': valid ? sha256.convert(bytes).toString() : '0' * 64,
                'url': '/site/downloads/youshu-0.3.0-4.apk',
              }),
              200,
            );
          }
          expect(request.followRedirects, isFalse);
          return http.Response.bytes(bytes, 200);
        }),
      );
    });
  }
  testWidgets('主入口故障走官方备用源，安装授权返回后继续且不打开浏览器', (t) async {
    final dir = Directory.systemTemp.createTempSync(
      'youshu-install-permission-',
    );
    final bytes = utf8.encode('permission fixture');
    var installs = 0;
    final calls = <String>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(system, (call) async {
          calls.add(call.method);
          if (call.method == 'appVersion') {
            return {'version': '0.6.1', 'build': 12};
          }
          if (call.method == 'updateDirectory') return dir.path;
          if (call.method == 'canInstallUpdates') return true;
          if (call.method == 'installUpdate') return ++installs > 1;
          return null;
        });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(system, null);
      dir.deleteSync(recursive: true);
    });
    await http.runWithClient(
      () async {
        await t.pumpWidget(const MaterialApp(home: UpdatePage()));
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await t.pumpAndSettle();
        expect(find.text('发现新版本 0.6.2'), findsOneWidget);
        await t.runAsync(() async {
          await t.tap(find.text('下载更新'));
          await Future<void>.delayed(const Duration(seconds: 1));
        });
        await t.pumpAndSettle();
        await t.runAsync(() async {
          await t.tap(find.text('安装更新'));
          await Future<void>.delayed(const Duration(milliseconds: 100));
        });
        await t.pumpAndSettle();
        expect(installs, 1);
        expect(find.text('允许安装应用后返回即可继续'), findsOneWidget);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
        t.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 100)),
        );
        await t.pumpAndSettle();
        expect(installs, 2);
        expect(calls, isNot(contains('openExternal')));
        expect(dir.listSync().where((f) => f.path.endsWith('.part')), isEmpty);
        await t.tap(find.text('重新检查'));
        await t.pump();
        expect(find.text('安装更新'), findsNothing);
        await t.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 180)),
        );
        await t.pumpAndSettle();
      },
      () => MockClient((request) async {
        if (request.url.origin == Uri.parse(releaseEndpoint).origin) {
          return http.Response('unavailable', 503);
        }
        expect(request.url.origin, Uri.parse(releaseFallback).origin);
        if (request.url.path.endsWith('.json')) {
          return http.Response(
            jsonEncode({
              'version': '0.6.2',
              'build': 13,
              'bytes': bytes.length,
              'sha256': sha256.convert(bytes).toString(),
              'url': '/site/downloads/test.apk',
            }),
            200,
          );
        }
        expect(
          request.url.queryParameters['sha'],
          sha256.convert(bytes).toString(),
        );
        return http.Response.bytes(bytes, 200);
      }),
    );
  });
}
