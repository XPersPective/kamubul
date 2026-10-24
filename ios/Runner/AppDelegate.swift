import CryptoKit
import EventKit
import EventKitUI
import Flutter
import Security
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate,
  EKEventEditViewDelegate
{
  private var remindersChannel: FlutterMethodChannel?
  /// Bildirime dokunarak açılışta Dart henüz dinlemiyorsa hedef burada bekler.
  private var pendingReminderTap: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Eklentiler (yerel bildirim, FCM) bu temsilci üzerinden haberdar edilir.
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    let messenger = engineBridge.applicationRegistrar.messenger()
    registerSecurePush(messenger)
    registerReminders(messenger)
    registerCalendar(messenger)
    registerDevice(messenger)
  }

  // MARK: - Bildirim temsilcisi

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    let info = response.notification.request.content.userInfo
    if let url = info[DeadlineReminders.tapKey] as? String {
      pendingReminderTap = url
      remindersChannel?.invokeMethod("tap", arguments: url)
      completionHandler()
      return
    }
    super.userNotificationCenter(
      center, didReceive: response, withCompletionHandler: completionHandler)
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler:
      @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    if notification.request.identifier.hasPrefix(DeadlineReminders.prefix) {
      completionHandler([.banner, .list, .sound])
      return
    }
    super.userNotificationCenter(
      center, willPresent: notification, withCompletionHandler: completionHandler)
  }

  // MARK: - Son başvuru hatırlatmaları (Android DeadlineReminders ile aynı sözleşme)

  private func registerReminders(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "kamubul/reminders", binaryMessenger: messenger)
    remindersChannel = channel
    channel.setMethodCallHandler { [weak self] call, result in
      func failed(_ code: String) {
        result(
          FlutterError(
            code: code == "too_many_reminders" ? "reminder_capacity" : "reminders_unavailable",
            message:
              "Hatırlatmalar güncellenemedi. Bildirim iznini ve kayıtlı ilan sayısını kontrol edip yeniden deneyin.",
            details: nil))
      }
      switch call.method {
      case "enabled":
        result(DeadlineReminders.shared.enabled())
      case "sync":
        guard let args = call.arguments as? [String: Any], let plans = args["plans"] as? [Any]
        else { failed("plans"); return }
        DeadlineReminders.shared.sync(raw: plans, enabled: args["enabled"] as? Bool) { outcome in
          DispatchQueue.main.async {
            switch outcome {
            case .success(let on): result(on)
            case .failure(let error): failed((error as? DeadlineReminders.Failure)?.code ?? "")
            }
          }
        }
      case "consumeTap":
        let url = self?.pendingReminderTap
        self?.pendingReminderTap = nil
        result(url)
      default:
        result(FlutterMethodNotImplemented)
      }
    }
  }

  // MARK: - Takvim: sistem düzenleyicisi açılır, kaydetmeyi kullanıcı seçer

  private func registerCalendar(_ messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "kamubul/calendar", binaryMessenger: messenger)
      .setMethodCallHandler { [weak self] call, result in
        guard call.method == "insert" else { result(FlutterMethodNotImplemented); return }
        guard let self, let args = call.arguments as? [String: Any],
          let year = args["year"] as? Int, (1970...9998).contains(year),
          let month = args["month"] as? Int, let day = args["day"] as? Int,
          let title = args["title"] as? String, let notes = args["description"] as? String,
          !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
          title.count <= 2000, notes.count <= 8000,
          let start = Calendar.current.date(
            from: DateComponents(year: year, month: month, day: day)),
          let end = Calendar.current.date(byAdding: .day, value: 1, to: start)
        else {
          result(FlutterError(code: "calendar_unavailable", message: "Takvim açılamadı.", details: nil))
          return
        }
        let store = EKEventStore()
        let present = { (canPickCalendar: Bool) in
          guard let top = self.topViewController() else { result(false); return }
          let event = EKEvent(eventStore: store)
          event.title = title
          event.notes = notes
          event.isAllDay = true
          event.startDate = start
          event.endDate = end
          if canPickCalendar { event.calendar = store.defaultCalendarForNewEvents }
          let editor = EKEventEditViewController()
          editor.eventStore = store
          editor.event = event
          editor.editViewDelegate = self
          top.present(editor, animated: true)
          result(true)  // Düzenleyici açıldı; kaydetme kararı kullanıcıda.
        }
        if #available(iOS 17.0, *) {
          // iOS 17+: düzenleyici uygulama dışında çalışır, takvim izni gerekmez.
          present(false)
        } else {
          store.requestAccess(to: .event) { granted, _ in
            DispatchQueue.main.async { granted ? present(true) : result(false) }
          }
        }
      }
  }

  func eventEditViewController(
    _ controller: EKEventEditViewController, didCompleteWith action: EKEventEditViewAction
  ) {
    controller.dismiss(animated: true)
  }

  private func topViewController() -> UIViewController? {
    let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
    var top = scenes.flatMap(\.windows).first(where: \.isKeyWindow)?.rootViewController
    while let presented = top?.presentedViewController { top = presented }
    return top
  }

  // MARK: - Deneme süresi: yeniden kurulumda korunan rastgele kimliğin tuzlu karması

  private func registerDevice(_ messenger: FlutterBinaryMessenger) {
    FlutterMethodChannel(name: "kamubul/device", binaryMessenger: messenger)
      .setMethodCallHandler { call, result in
        guard call.method == "trialHash" else { result(FlutterMethodNotImplemented); return }
        // Ham kimlik Dart'a/sunucuya verilmez; Android ANDROID_ID karmasıyla aynı biçim.
        guard let id = Self.trialIdentifier() else { result(nil); return }
        let digest = SHA256.hash(data: Data("kamubul-trial-v1:\(id)".utf8))
        result(digest.map { String(format: "%02x", $0) }.joined())
      }
  }

  private static func trialIdentifier() -> String? {
    let query: [String: Any] = [
      kSecClass as String: kSecClassGenericPassword,
      kSecAttrService as String: "com.crazypenguin.kamubul.trial.v1",
      kSecAttrAccount as String: "device", kSecAttrSynchronizable as String: false,
    ]
    var read = query
    read[kSecReturnData as String] = true
    read[kSecMatchLimit as String] = kSecMatchLimitOne
    var item: CFTypeRef?
    if SecItemCopyMatching(read as CFDictionary, &item) == errSecSuccess,
      let data = item as? Data, let value = String(data: data, encoding: .utf8)
    {
      return value
    }
    let value = UUID().uuidString
    var added = query
    added[kSecValueData as String] = Data(value.utf8)
    added[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
    return SecItemAdd(added as CFDictionary, nil) == errSecSuccess ? value : nil
  }

  // MARK: - Sunucu bildirimi kurulum anahtarı

  private func registerSecurePush(_ messenger: FlutterBinaryMessenger) {
    let channel = FlutterMethodChannel(name: "kamubul/secure_push", binaryMessenger: messenger)
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

/// Android DeadlineReminders'ın iOS karşılığı. iOS teslim anında kod çalıştırmadığı için
/// sessiz saat ve son tarih kontrolü zamanlamada yapılır; zamanı geçen plan gönderilmiş sayılır.
/// Yalnız herkese açık ilan bilgisi tutulur; yedeğe girmez.
final class DeadlineReminders {
  static let shared = DeadlineReminders()
  static let prefix = "kamubul.deadline."
  static let tapKey = "kamubul_deadline_url"
  /// iOS bekleyen yerel bildirim sınırı 64; kalanlar sonraki eşitlemede zamanlanır.
  private static let pendingLimit = 60

  struct Failure: Error { let code: String }
  private struct Plan: Codable {
    var id: Int
    var url: String
    var title: String
    var at: Int64
    var expires: Int64
    var key: String { "\(url)|\(expires)" }
  }
  private struct Sent: Codable {
    var url: String
    var expires: Int64
    var key: String { "\(url)|\(expires)" }
  }
  private struct State: Codable {
    var version = 1
    var enabled = false
    var nextId = 1
    var plans: [Plan] = []
    var sent: [Sent] = []
  }

  private let queue = DispatchQueue(label: "kamubul.deadline")
  private let zone = TimeZone(identifier: "Europe/Istanbul")!
  private var center: UNUserNotificationCenter { .current() }

  private var file: URL {
    let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    return base.appendingPathComponent("deadline-reminders.v1")
  }

  private func read() throws -> State {
    guard FileManager.default.fileExists(atPath: file.path) else { return State() }
    let data = try Data(contentsOf: file)
    guard data.count <= 1_048_576 else { throw Failure(code: "state") }
    let state = try JSONDecoder().decode(State.self, from: data)
    guard state.version == 1 else { throw Failure(code: "state") }
    return state
  }

  private func write(_ state: State) throws {
    let data = try JSONEncoder().encode(state)
    guard data.count <= 1_048_576 else { throw Failure(code: "state") }
    var url = file
    try FileManager.default.createDirectory(
      at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    var values = URLResourceValues()
    values.isExcludedFromBackup = true
    try url.setResourceValues(values)
  }

  func enabled() -> Bool { queue.sync { (try? read().enabled) ?? false } }

  private func allowed(_ done: @escaping (Bool) -> Void) {
    center.getNotificationSettings { settings in
      switch settings.authorizationStatus {
      case .authorized, .provisional, .ephemeral: done(settings.alertSetting != .disabled)
      default: done(false)
      }
    }
  }

  /// 22:00–08:00 Türkiye saatinde gönderilmez; sabah 08:00'e kayar.
  private func quietAdjusted(_ ms: Int64) -> Int64 {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = zone
    let date = Date(timeIntervalSince1970: Double(ms) / 1000)
    let hour = calendar.component(.hour, from: date)
    guard hour < 8 || hour >= 22 else { return ms }
    var day = calendar.startOfDay(for: date)
    if hour >= 22 { day = calendar.date(byAdding: .day, value: 1, to: day)! }
    let morning = calendar.date(bySettingHour: 8, minute: 0, second: 0, of: day)!
    return Int64(morning.timeIntervalSince1970 * 1000)
  }

  func sync(raw: [Any], enabled: Bool?, done: @escaping (Result<Bool, Error>) -> Void) {
    allowed { permitted in
      self.queue.async {
        do {
          done(.success(try self.apply(raw: raw, enabled: enabled, permitted: permitted)))
        } catch {
          done(.failure(error))
        }
      }
    }
  }

  private func apply(raw: [Any], enabled: Bool?, permitted: Bool) throws -> Bool {
    let old = try read()
    let on = enabled ?? (old.enabled && permitted)
    if on && raw.count > 500 { throw Failure(code: "too_many_reminders") }
    if on && !permitted { throw Failure(code: "notification_permission_required") }
    let now = Int64(Date().timeIntervalSince1970 * 1000)
    // Zamanı gelmiş planlar sistem tarafından gösterildi; aynı son tarih tekrar hatırlatılmaz.
    var sent = old.sent + old.plans.filter { $0.at <= now }.map { Sent(url: $0.url, expires: $0.expires) }
    sent = sent.filter { $0.expires > now }
    let sentKeys = Set(sent.map(\.key))
    let previous = Dictionary(old.plans.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
    var nextId = old.nextId
    var plans: [Plan] = []
    var seen = Set<String>()
    if on {
      for entry in raw {
        guard let map = entry as? [String: Any], let url = map["url"] as? String,
          let title = map["title"] as? String,
          let at = (map["at"] as? NSNumber)?.int64Value,
          let expires = (map["expires"] as? NSNumber)?.int64Value,
          let parsed = URL(string: url), parsed.scheme == "https",
          !(parsed.host ?? "").isEmpty, parsed.user == nil, url.count <= 2000,
          !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, title.count <= 2000,
          at > 0, expires > at, expires <= now + 3_155_760_000_000
        else { throw Failure(code: "plan") }
        let key = "\(url)|\(expires)"
        guard expires > now, !sentKeys.contains(key), seen.insert(key).inserted else { continue }
        if let existing = previous[key], existing.at > now {
          plans.append(Plan(id: existing.id, url: url, title: title, at: existing.at, expires: expires))
          continue
        }
        let fire = quietAdjusted(max(at, now + 1000))
        guard fire < expires else { continue }
        guard nextId < Int.max else { throw Failure(code: "state") }
        plans.append(Plan(id: nextId, url: url, title: title, at: fire, expires: expires))
        nextId += 1
      }
    }
    // Önce kalıcı istenen durum; ardından sistem kuyruğu buna eşitlenir.
    try write(State(enabled: on, nextId: nextId, plans: plans, sent: sent))
    center.removePendingNotificationRequests(withIdentifiers: old.plans.map { Self.prefix + "\($0.id)" })
    if !on {
      center.getDeliveredNotifications { delivered in
        self.center.removeDeliveredNotifications(
          withIdentifiers: delivered.map(\.request.identifier).filter { $0.hasPrefix(Self.prefix) })
      }
    }
    let formatter = DateFormatter()
    formatter.timeZone = zone
    formatter.locale = Locale(identifier: "tr_TR")
    formatter.dateFormat = "dd.MM.yyyy HH:mm"
    for plan in plans.sorted(by: { $0.at < $1.at }).prefix(Self.pendingLimit) {
      let content = UNMutableNotificationContent()
      let deadline = Date(timeIntervalSince1970: Double(plan.expires) / 1000)
      content.title = "Son başvuru: \(formatter.string(from: deadline))"
      content.body = plan.title
      content.sound = .default
      content.userInfo = [Self.tapKey: plan.url]
      let seconds = max(1, Double(plan.at - now) / 1000)
      let trigger = UNTimeIntervalNotificationTrigger(timeInterval: seconds, repeats: false)
      center.add(UNNotificationRequest(identifier: Self.prefix + "\(plan.id)", content: content, trigger: trigger))
    }
    return on
  }
}
