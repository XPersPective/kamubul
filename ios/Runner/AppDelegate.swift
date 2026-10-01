import Flutter
import UIKit
import Security

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let channel = FlutterMethodChannel(name: "kamubul/secure_push",
      binaryMessenger: engineBridge.applicationRegistrar.messenger())
    channel.setMethodCallHandler { call, result in
      let query: [String: Any] = [kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: "com.crazypenguin.kamubul.push.v1",
        kSecAttrAccount as String: "installation", kSecAttrSynchronizable as String: false]
      func failed() { result(FlutterError(code: "secure_storage_unavailable",
        message: "Bildirim anahtarı güvenli saklanamadı.", details: nil)) }
      // Keychain can survive uninstall; a fresh install must have a fresh identity.
      let marker = "kamubul.securePush.installation"
      if !UserDefaults.standard.bool(forKey: marker) {
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { failed(); return }
        UserDefaults.standard.set(true, forKey: marker)
      }
      switch call.method {
      case "read":
        var read = query
        read[kSecReturnData as String] = true
        read[kSecMatchLimit as String] = kSecMatchLimitOne
        var item: CFTypeRef?
        let status = SecItemCopyMatching(read as CFDictionary, &item)
        if status == errSecItemNotFound { result(nil); return }
        guard status == errSecSuccess, let data = item as? Data, data.count <= 131072,
          let value = String(data: data, encoding: .utf8) else { failed(); return }
        result(value)
      case "write":
        guard let value = call.arguments as? String, let data = value.data(using: .utf8),
          data.count <= 131072 else { failed(); return }
        let attributes: [String: Any] = [kSecValueData as String: data,
          kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
          var added = query
          attributes.forEach { added[$0.key] = $0.value }
          guard SecItemAdd(added as CFDictionary, nil) == errSecSuccess else { failed(); return }
        } else if status != errSecSuccess { failed(); return }
        result(nil)
      default: result(FlutterMethodNotImplemented)
      }
    }
  }
}
