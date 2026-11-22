import Flutter
import UIKit

class SceneDelegate: FlutterSceneDelegate {
  override func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
    if let shortcut = connectionOptions.shortcutItem { AppDelegate.pendingAction = shortcut.type }
    if let url = connectionOptions.urlContexts.first?.url, ["youshu", "yousu"].contains(url.scheme ?? "") { AppDelegate.pendingAction = url.absoluteString }
    super.scene(scene, willConnectTo: session, options: connectionOptions)
  }
  override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
    if let url = URLContexts.first?.url, ["youshu", "yousu"].contains(url.scheme ?? "") { AppDelegate.open(url.absoluteString) }
    else { super.scene(scene, openURLContexts: URLContexts) }
  }
  override func windowScene(_ windowScene: UIWindowScene, performActionFor shortcutItem: UIApplicationShortcutItem, completionHandler: @escaping (Bool) -> Void) {
    AppDelegate.open(shortcutItem.type)
    completionHandler(true)
  }
}
