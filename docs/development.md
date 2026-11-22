# 开发指南

更新：2026-11-22 14:42。

## 工具链

首版整理使用 Flutter 3.47.9 / Dart 3.13.7。Flutter 依赖版本由 `apps/mobile/pubspec.lock` 固定。Android 使用 JDK 17 和 Flutter 所需 Android SDK；iOS 使用支持项目部署目标的 Xcode，当前 iOS 目标为 17.0。

若有多套 Android 工具，请将当前进程的 `ANDROID_HOME` 指向包含所需 NDK 的完整 SDK 目录；不要指向仅含 platform-tools 的目录。SDK 和 Flutter 路径由本机生成的 `android/local.properties` 保存，该文件不提交。

在 `apps/mobile` 下执行 `flutter pub get`、`flutter run`。首次运行需下载依赖。核心功能不需要账号或服务端。

## Android

Gradle 默认最多 2 个 worker，不并行构建多个目标。调试构建使用开发环境的调试签名，不要求 `key.properties`。

```sh
flutter build apk --debug
```

正式发行需要自己的签名：将 `android/key.properties.example` 复制为 `android/key.properties` 并填入自己的配置。未提供配置时 Release 是未签名产物，不能作为可安装的官方包发布。签名文件和 keystore 不得提交。

不同签名不能直接覆盖安装；测试开发版时避免覆盖日常账本，使用独立模拟器或先导出备份。

自行构建默认关闭官方 APK 更新检查。仅使用官方签名的维护者发行才应设置 `--dart-define=YOUSHU_OFFICIAL_UPDATES=true`；此开关不改变网络请求的 HTTPS、同源与 SHA-256 校验。

## iOS

```sh
flutter build ios --simulator --debug
```

真机运行请在 Xcode 中打开 `ios/Runner.xcworkspace`，为 Runner 和 YousuWidget 设置自己的 Team 与唯一 Bundle ID。App Group 必须在两个 target 的 entitlements 和对应原生源码中保持一致：

- `ios/Runner/Runner.entitlements`
- `ios/YousuWidget/YousuWidget.entitlements`
- `ios/Runner/AppDelegate.swift`
- `ios/YousuWidget/YousuWidget.swift`

模板中的 `com.seafy.yousu` 和 `group.com.seafy.yousu` 是应用标识，不是签名权限；自己的发行需替换它们。Dart 与原生侧的 MethodChannel 名称须保持一致，通常无需随 Bundle ID 改动。

## 验证

```sh
flutter analyze
flutter test --concurrency=2
flutter test --concurrency=2 --dart-define=YOUSHU_OFFICIAL_UPDATES=true test/update_page_test.dart
```

默认测试验证自行构建的更新入口；第二条更新专项命令使用 mock 网络验证安装包下载与校验，不连接真实更新服务。测试中可选的私人文件环境变量不要在公共 CI 设置；常规测试使用代码生成的虚构数据。

## 官网源码

官网按 `/site/` 路径提供资源。预览时可将 `website` 作为静态服务的 `/site` 目录。下载清单记录官方产物地址，但仓库不包含 APK 二进制。
