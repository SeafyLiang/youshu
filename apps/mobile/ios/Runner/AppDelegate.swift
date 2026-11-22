import Flutter
import UIKit
import WidgetKit
import UserNotifications
import Vision
import CoreImage
import ImageIO

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var keyHaptics: [String: UIImpactFeedbackGenerator] = [:]
  static var pendingAction: String?
  static var channel: FlutterMethodChannel?
  static func open(_ route: String) {
    if let channel = channel { channel.invokeMethod("quickAdd", arguments: route) }
    else { pendingAction = route }
  }
  override func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    if let shortcut = launchOptions?[.shortcutItem] as? UIApplicationShortcutItem { Self.pendingAction = shortcut.type }
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }
  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "com.seafy.yousu/system", binaryMessenger: engineBridge.applicationRegistrar.messenger())
    Self.channel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "openExternal":
        guard let value = call.arguments as? String, let url = URL(string:value), ["https", "mailto"].contains(url.scheme ?? "") else { result(false); return }
        UIApplication.shared.open(url, options:[:]) { result($0) }
      case "openPurchaseLink":
        guard let value = call.arguments as? String, let url = URL(string: value),
              ["http", "https"].contains(url.scheme ?? ""), url.host != nil,
              url.user == nil, url.password == nil else { result(false); return }
        UIApplication.shared.open(url, options: [.universalLinksOnly: true]) { opened in
          if opened { result(true) }
          else { UIApplication.shared.open(url, options: [:]) { result($0) } }
        }
      case "normalizeBelongingPhoto": self.normalizePhoto(call.arguments, result: result)
      case "extractBelongingSubject": self.extractSubject(call.arguments, result: result)
      case "successHaptic":
        UINotificationFeedbackGenerator().notificationOccurred(.success); result(nil)
      case "prepareKeyHaptic", "keyHaptic":
        let level = call.arguments as? String ?? "light"
        if level == "off" { result(nil); return }
        let style: UIImpactFeedbackGenerator.FeedbackStyle = level == "strong" ? .heavy : (level == "medium" ? .medium : .light)
        let generator = self.keyHaptics[level] ?? UIImpactFeedbackGenerator(style: style)
        self.keyHaptics[level] = generator
        if call.method == "keyHaptic" { generator.impactOccurred() }
        generator.prepare()
        result(nil)
      case "initialAction": result(Self.pendingAction); Self.pendingAction = nil
      case "updateWidget":
        if let data = call.arguments as? [String: String], let defaults = UserDefaults(suiteName: "group.com.seafy.yousu") {
          for (key, value) in data { defaults.set(value, forKey: key) }
          WidgetCenter.shared.reloadAllTimelines()
        }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
  private func normalizePhoto(_ arguments: Any?, result: @escaping FlutterResult) {
    guard let typed = arguments as? FlutterStandardTypedData, typed.data.count <= 10 * 1024 * 1024 else {
      result(FlutterError(code: "PHOTO", message: "请选择 10 MB 以内的图片", details: nil)); return
    }
    DispatchQueue.global(qos: .userInitiated).async {
      autoreleasepool {
        guard let source = CGImageSourceCreateWithData(typed.data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Double,
              let height = props[kCGImagePropertyPixelHeight] as? Double,
              width > 0, height > 0, width * height <= 80_000_000 else {
          DispatchQueue.main.async { result(FlutterError(code: "PHOTO", message: "图片尺寸过大或格式无效", details: nil)) }; return
        }
        // ImageIO applies EXIF orientation while downsampling, without decoding a full 80 MP bitmap.
        let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
          kCGImageSourceThumbnailMaxPixelSize: 1600,
          kCGImageSourceCreateThumbnailWithTransform: true,
          kCGImageSourceShouldCacheImmediately: true]
        guard let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary),
              let png = UIImage(cgImage: cg).pngData() else {
          DispatchQueue.main.async { result(FlutterError(code: "PHOTO", message: "无法读取照片", details: nil)) }; return
        }
        DispatchQueue.main.async { result(FlutterStandardTypedData(bytes: png)) }
      }
    }
  }
  private func extractSubject(_ arguments: Any?, result: @escaping FlutterResult) {
    #if targetEnvironment(simulator)
    result(["status": "unsupported"])
    #else
    guard #available(iOS 17.0, *), let typed = arguments as? FlutterStandardTypedData,
          typed.data.count <= 10 * 1024 * 1024 else { result(["status": "unsupported"]); return }
    DispatchQueue.global(qos: .userInitiated).async {
      autoreleasepool {
        do {
          guard let image = UIImage(data: typed.data)?.cgImage else {
            DispatchQueue.main.async { result(["status": "failed"]) }; return
          }
          let request = VNGenerateForegroundInstanceMaskRequest()
          let handler = VNImageRequestHandler(cgImage: image)
          try handler.perform([request])
          guard let observation = request.results?.first, !observation.allInstances.isEmpty else {
            DispatchQueue.main.async { result(["status": "noSubject"]) }; return
          }
          let buffer = try observation.generateMaskedImage(ofInstances: observation.allInstances, from: handler, croppedToInstancesExtent: false)
          let output = CIImage(cvPixelBuffer: buffer)
          guard let cg = CIContext().createCGImage(output, from: output.extent), let png = UIImage(cgImage: cg).pngData() else {
            DispatchQueue.main.async { result(["status": "failed"]) }; return
          }
          DispatchQueue.main.async { result(["status": "ok", "bytes": FlutterStandardTypedData(bytes: png)]) }
        } catch { DispatchQueue.main.async { result(["status": "failed"]) } }
      }
    }
    #endif
  }

}
