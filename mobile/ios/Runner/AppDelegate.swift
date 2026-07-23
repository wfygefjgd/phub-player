import Flutter
import UIKit
import WebKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var privacyChannel: FlutterMethodChannel?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)

    let messenger = engineBridge.applicationRegistrar.messenger()
    let channel = FlutterMethodChannel(
      name: "privacy_browser/engine",
      binaryMessenger: messenger
    )
    privacyChannel = channel
    channel.setMethodCallHandler { call, result in
      switch call.method {
      case "nuclearWipe":
        PrivacyNativeWipe.run {
          result(nil)
        }
      case "exitApp":
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
          exit(0)
        }
        result(nil)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }
}

enum PrivacyNativeWipe {
  static func run(completion: @escaping () -> Void) {
    let group = DispatchGroup()

    group.enter()
    let types = WKWebsiteDataStore.allWebsiteDataTypes()
    WKWebsiteDataStore.default().removeData(
      ofTypes: types,
      modifiedSince: Date(timeIntervalSince1970: 0)
    ) {
      group.leave()
    }

    HTTPCookieStorage.shared.cookies?.forEach { HTTPCookieStorage.shared.deleteCookie($0) }
    HTTPCookieStorage.shared.removeCookies(since: .distantPast)
    URLCache.shared.removeAllCachedResponses()
    URLCache.shared = URLCache(memoryCapacity: 0, diskCapacity: 0, diskPath: nil)

    wipeSandboxFiles()
    wipeUserDefaults()
    wipeKeychain()

    group.notify(queue: .main) {
      completion()
    }
  }

  private static func wipeSandboxFiles() {
    let fm = FileManager.default
    let home = URL(fileURLWithPath: NSHomeDirectory())
    let targets = [
      home.appendingPathComponent("Library/Cookies"),
      home.appendingPathComponent("Library/WebKit"),
      home.appendingPathComponent("Library/Caches"),
      home.appendingPathComponent("Library/HTTPStorages"),
      home.appendingPathComponent("Library/Application Support"),
      home.appendingPathComponent("tmp"),
      URL(fileURLWithPath: NSTemporaryDirectory()),
      home.appendingPathComponent("Documents"),
    ]
    for url in targets {
      wipeDirectoryContents(url, fileManager: fm)
    }
  }

  private static func wipeDirectoryContents(_ url: URL, fileManager fm: FileManager) {
    guard fm.fileExists(atPath: url.path) else { return }
    guard let items = try? fm.contentsOfDirectory(
      at: url,
      includingPropertiesForKeys: nil,
      options: []
    ) else {
      return
    }
    for item in items {
      try? fm.removeItem(at: item)
    }
  }

  private static func wipeUserDefaults() {
    if let bundleId = Bundle.main.bundleIdentifier {
      UserDefaults.standard.removePersistentDomain(forName: bundleId)
    }
    for key in UserDefaults.standard.dictionaryRepresentation().keys {
      UserDefaults.standard.removeObject(forKey: key)
    }
    UserDefaults.standard.synchronize()
  }

  private static func wipeKeychain() {
    let classes: [CFString] = [
      kSecClassGenericPassword,
      kSecClassInternetPassword,
      kSecClassCertificate,
      kSecClassKey,
      kSecClassIdentity,
    ]
    for cls in classes {
      SecItemDelete([kSecClass: cls] as CFDictionary)
    }
  }
}
