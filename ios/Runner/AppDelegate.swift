import AVFoundation
import Flutter
import UIKit
import UserNotifications

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    UNUserNotificationCenter.current().delegate = self
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    if let registrar = engineBridge.pluginRegistry.registrar(forPlugin: "LinkMeshService") {
      MeshService.shared.attach(registrar)
    }
  }

  // Show banners and play sounds for LinkMesh notifications while the app is open
  // (the Dart side already skips them when that chat is on screen).
  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    willPresent notification: UNNotification,
    withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
  ) {
    completionHandler([.banner, .list, .sound])
  }

  override func userNotificationCenter(
    _ center: UNUserNotificationCenter,
    didReceive response: UNNotificationResponse,
    withCompletionHandler completionHandler: @escaping () -> Void
  ) {
    if let peer = response.notification.request.content.userInfo["peer_id"] as? String {
      MeshService.shared.pendingChat = peer
    }
    completionHandler()
  }
}

/// iOS side of the `linkmesh/service` channel: local notifications and sounds.
/// iOS has no foreground-service equivalent, so the start/stop calls are no-ops;
/// the Bluetooth background modes in Info.plist keep existing links working.
final class MeshService: NSObject {
  static let shared = MeshService()

  var pendingChat: String?
  private var player: AVAudioPlayer?
  private var lookupKey: ((String) -> String)?

  private let sounds = ["message": "message_chime.wav", "sos": "sos_alert.wav"]

  func attach(_ registrar: FlutterPluginRegistrar) {
    lookupKey = { registrar.lookupKey(forAsset: $0) }
    installNotificationSounds()
    let channel = FlutterMethodChannel(name: "linkmesh/service", binaryMessenger: registrar.messenger())
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let args = call.arguments as? [String: Any] ?? [:]
    switch call.method {
    case "start", "stop", "setStatus", "requestBatteryExemption":
      result(nil)
    case "isEnabled", "isRunning":
      result(false)
    case "isIgnoringBatteryOptimizations":
      result(true)
    case "sdkInt":
      result(0)
    case "notifyMessage":
      post(
        id: "msg:\(args["peerId"] as? String ?? "")",
        title: args["title"] as? String ?? "",
        body: args["body"] as? String ?? "",
        peer: args["peerId"] as? String,
        sound: "message_chime.wav",
        alert: true)
      result(nil)
    case "notifySos":
      post(
        id: "sos:\(args["senderId"] as? String ?? "")",
        title: args["title"] as? String ?? "",
        body: args["body"] as? String ?? "",
        peer: "sos",
        sound: "sos_alert.wav",
        alert: args["alert"] as? Bool ?? true)
      result(nil)
    case "cancel":
      if let key = args["key"] as? String {
        UNUserNotificationCenter.current().removeDeliveredNotifications(withIdentifiers: [key])
      }
      result(nil)
    case "playSound":
      play(args["kind"] as? String ?? "message")
      result(nil)
    case "takePendingChat":
      result(pendingChat)
      pendingChat = nil
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  /// Notification sounds must live in the app bundle or Library/Sounds; the
  /// files ship as Flutter assets, so copy them to Library/Sounds once.
  private func installNotificationSounds() {
    let fm = FileManager.default
    guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
    let dir = library.appendingPathComponent("Sounds", isDirectory: true)
    try? fm.createDirectory(at: dir, withIntermediateDirectories: true)
    for file in sounds.values {
      let target = dir.appendingPathComponent(file)
      guard let source = assetURL(file) else { continue }
      try? fm.removeItem(at: target)
      try? fm.copyItem(at: source, to: target)
    }
  }

  private func assetURL(_ file: String) -> URL? {
    guard let key = lookupKey?("assets/sounds/\(file)"),
      let path = Bundle.main.path(forResource: key, ofType: nil)
    else { return nil }
    return URL(fileURLWithPath: path)
  }

  private func post(id: String, title: String, body: String, peer: String?, sound: String, alert: Bool) {
    let content = UNMutableNotificationContent()
    content.title = title
    content.body = body
    content.threadIdentifier = id
    if let peer = peer { content.userInfo = ["peer_id": peer] }
    // Repeat SOS broadcasts update the existing notification silently.
    if alert { content.sound = UNNotificationSound(named: UNNotificationSoundName(sound)) }
    if id.hasPrefix("sos:") { content.interruptionLevel = .timeSensitive }
    let request = UNNotificationRequest(identifier: id, content: content, trigger: nil)
    UNUserNotificationCenter.current().add(request)
  }

  private func play(_ kind: String) {
    guard let file = sounds[kind], let url = assetURL(file) else { return }
    // SOS ignores the silent switch; messages respect it.
    try? AVAudioSession.sharedInstance().setCategory(kind == "sos" ? .playback : .ambient)
    try? AVAudioSession.sharedInstance().setActive(true)
    player = try? AVAudioPlayer(contentsOf: url)
    player?.play()
  }
}
