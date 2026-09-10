import UIKit
import Flutter
import PushKit
import AVFoundation
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  private let CHANNEL = "com.privatemessaging.tuyjo/shared_media"
  private let TONE_CHANNEL = "com.privatemessaging.tuyjo/tone_generator"
  private var methodChannel: FlutterMethodChannel?
  private var toneChannel: FlutterMethodChannel?
  private let ringback = RingbackTonePlayer()
  private var initialMediaPaths: [String]?
  private var initialSharedText: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    GeneratedPluginRegistrant.register(with: self)

    // Configura il Method Channel
    let controller = window?.rootViewController as! FlutterViewController
    methodChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: controller.binaryMessenger)

    methodChannel?.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      if call.method == "getInitialMedia" {
        result(self?.initialMediaPaths)
        self?.initialMediaPaths = nil
      } else if call.method == "getInitialSharedText" {
        result(self?.initialSharedText)
        self?.initialSharedText = nil
      } else {
        result(FlutterMethodNotImplemented)
      }
    })

    // Ringback tone (chiamata in uscita): stesso canale usato su Android
    toneChannel = FlutterMethodChannel(name: TONE_CHANNEL, binaryMessenger: controller.binaryMessenger)
    toneChannel?.setMethodCallHandler({ [weak self] (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "startRingback":
        self?.ringback.start()
        result(true)
      case "stopRingback":
        self?.ringback.stop()
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // PushKit VoIP: unico modo affidabile per far squillare una chiamata
    // su iOS con app in background o terminata. Il push arriva qui e va
    // riportato SUBITO a CallKit (obbligo iOS 13+, altrimenti l'app viene
    // terminata e il push VoIP non viene più consegnato).
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [PKPushType.voIP]

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // MARK: - PKPushRegistryDelegate (VoIP push)

  func pushRegistry(_ registry: PKPushRegistry, didUpdate credentials: PKPushCredentials, for type: PKPushType) {
    guard type == .voIP else { return }
    let token = credentials.token.map { String(format: "%02x", $0) }.joined()
    print("📞 VoIP push token: \(token)")
    // Il plugin lo espone a Flutter (getDevicePushTokenVoIP + evento
    // actionDidUpdateDevicePushTokenVoip) che lo salva su Firestore.
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP(token)
  }

  func pushRegistry(_ registry: PKPushRegistry, didInvalidatePushTokenFor type: PKPushType) {
    guard type == .voIP else { return }
    print("📞 VoIP push token invalidated")
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.setDevicePushTokenVoIP("")
  }

  func pushRegistry(_ registry: PKPushRegistry, didReceiveIncomingPushWith payload: PKPushPayload, for type: PKPushType, completion: @escaping () -> Void) {
    guard type == .voIP else {
      completion()
      return
    }
    print("📞 VoIP push received: \(payload.dictionaryPayload)")

    // Il payload è già nel formato CallKitParams (costruito dalla Cloud Function):
    // id, nameCaller, handle, type, duration, extra{familyChatId, callerId}, ios{...}
    var args: [String: Any?] = [:]
    for (key, value) in payload.dictionaryPayload {
      if let k = key as? String { args[k] = value }
    }
    if args["id"] == nil || (args["id"] as? String)?.isEmpty == true {
      args["id"] = UUID().uuidString
    }
    let data = flutter_callkit_incoming.Data(args: args)
    SwiftFlutterCallkitIncomingPlugin.sharedInstance?.showCallkitIncoming(data, fromPushKit: true)

    // Dai a CallKit il tempo di registrare la chiamata prima di completare
    DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) {
      completion()
    }
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    super.applicationDidBecomeActive(application)

    // Print Share Extension debug log if present
    let appGroupId = "group.com.privatemessaging.tuyjo"
    if let ud = UserDefaults(suiteName: appGroupId) {
      if let log = ud.string(forKey: "share_debug_log"), !log.isEmpty {
        print("📋 Share Extension debug log:\n\(log)")
        ud.removeObject(forKey: "share_debug_log")
        ud.synchronize()
      }
    }

    // Pick up any pending shared data (safety net for iOS 26+
    // where the extension may not be able to open the app directly)
    if let imagePath = loadSharedImagePathFromAppGroup() {
      handleSharedMedia([URL(fileURLWithPath: imagePath)])
    } else if let documentPath = loadSharedDocumentPathFromAppGroup() {
      handleSharedMedia([URL(fileURLWithPath: documentPath)])
    } else if let sharedText = loadSharedTextFromAppGroup() {
      handleSharedText(sharedText)
    }
  }

  // Gestisce l'apertura di file/foto/URL condivisi (iOS 9+)
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    print("📱 AppDelegate: application:open:options called with URL: \(url)")
    print("📱 URL scheme: \(url.scheme ?? "nil"), pathExtension: \(url.pathExtension)")

    // Controlla se viene da ShareExtension tramite App Group
    if url.scheme?.lowercased() == "sharemedia" {
      print("📱 ShareMedia URL detected, checking App Group...")

      // Prima controlla se c'è un'immagine condivisa
      if let imagePath = loadSharedImagePathFromAppGroup() {
        print("📱 Found shared image from App Group: \(imagePath)")
        handleSharedMedia([URL(fileURLWithPath: imagePath)])
        return true
      }

      // Controlla se c'è un documento condiviso
      if let documentPath = loadSharedDocumentPathFromAppGroup() {
        print("📱 Found shared document from App Group: \(documentPath)")
        handleSharedMedia([URL(fileURLWithPath: documentPath)])
        return true
      }

      // Poi controlla se c'è del testo condiviso
      if let sharedText = loadSharedTextFromAppGroup() {
        print("📱 Found shared text from App Group: \(sharedText)")
        handleSharedText(sharedText)
        return true
      }
    }

    // Controlla se è un URL web (http/https) condiviso
    if let scheme = url.scheme, (scheme == "http" || scheme == "https") {
      print("📱 Web URL shared: \(url.absoluteString)")
      handleSharedText(url.absoluteString)
      return true
    }

    // Controlla se è un file media
    if isMediaFile(url) {
      handleSharedMedia([url])
      return true
    }

    return super.application(app, open: url, options: options)
  }

  // iOS 13+ per Universal Links e handoff
  override func application(_ application: UIApplication, continue userActivity: NSUserActivity, restorationHandler: @escaping ([UIUserActivityRestoring]?) -> Void) -> Bool {
    print("📱 AppDelegate: application:continue:restorationHandler called")
    print("📱 Activity type: \(userActivity.activityType)")

    if userActivity.activityType == NSUserActivityTypeBrowsingWeb,
       let url = userActivity.webpageURL {
      // Se è un URL web, condividilo come testo
      if let scheme = url.scheme, (scheme == "http" || scheme == "https") {
        print("📱 Web URL from user activity: \(url.absoluteString)")
        handleSharedText(url.absoluteString)
        return true
      }
      // Se è un file media, copialo
      if isMediaFile(url) {
        print("📱 Handling media file from user activity: \(url)")
        handleSharedMedia([url])
        return true
      }
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  private func isMediaFile(_ url: URL) -> Bool {
    let ext = url.pathExtension.lowercased()
    let imageExtensions = ["jpg", "jpeg", "png", "gif", "heic", "heif", "webp"]
    let videoExtensions = ["mp4", "mov", "m4v", "avi", "mkv"]

    return imageExtensions.contains(ext) || videoExtensions.contains(ext)
  }

  private func handleSharedMedia(_ urls: [URL]) {
    print("📤 handleSharedMedia called with \(urls.count) file(s)")

    var copiedPaths: [String] = []

    for url in urls {
      print("📎 Processing: \(url)")
      print("📎 Is file URL: \(url.isFileURL)")
      print("📎 Path: \(url.path)")

      if let copiedPath = copyFileToAppStorage(url) {
        print("✅ File copied to: \(copiedPath)")
        copiedPaths.append(copiedPath)
      } else {
        print("❌ Failed to copy file: \(url)")
      }
    }

    guard !copiedPaths.isEmpty else {
      print("⚠️ No files were copied successfully")
      return
    }

    print("📋 Total files copied: \(copiedPaths.count)")

    // Se Flutter è già pronto, invia subito
    if let channel = methodChannel {
      print("📲 Flutter ready, invoking onMediaShared")
      channel.invokeMethod("onMediaShared", arguments: copiedPaths)
      // Salva anche come initialMediaPaths per getInitialMedia
      initialMediaPaths = copiedPaths
    } else {
      // Altrimenti salva per dopo
      print("⏳ Flutter not ready, saving as initialMediaPaths")
      initialMediaPaths = copiedPaths
    }
  }

  private func copyFileToAppStorage(_ url: URL) -> String? {
    do {
      print("📋 Starting copy from: \(url)")

      // Accedi al file in modo sicuro
      let accessing = url.startAccessingSecurityScopedResource()
      print("📋 Security scoped resource: \(accessing)")
      defer {
        if accessing {
          url.stopAccessingSecurityScopedResource()
          print("📋 Released security scoped resource")
        }
      }

      // Verifica esistenza file
      guard FileManager.default.fileExists(atPath: url.path) else {
        print("❌ File does not exist: \(url.path)")
        return nil
      }

      // Directory Caches (più stabile di /tmp/)
      let cachesDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
      let tempDir = cachesDir.appendingPathComponent("shared_media", isDirectory: true)
      try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
      print("📋 Caches directory: \(tempDir.path)")

      // Nome file unico
      let timestamp = Int(Date().timeIntervalSince1970 * 1000)
      let ext = url.pathExtension
      let fileName = "shared_\(timestamp).\(ext)"
      let destURL = tempDir.appendingPathComponent(fileName)
      print("📋 Destination: \(destURL.path)")

      // Rimuovi se esiste
      if FileManager.default.fileExists(atPath: destURL.path) {
        print("📋 Removing existing file")
        try? FileManager.default.removeItem(at: destURL)
      }

      // Copia
      try FileManager.default.copyItem(at: url, to: destURL)
      print("✅ Copy successful")

      return destURL.path
    } catch {
      print("❌ Copy error: \(error)")
      print("❌ Details: \(error.localizedDescription)")
      return nil
    }
  }

  private func handleSharedText(_ text: String) {
    print("📝 handleSharedText called with: \(text)")

    // Se Flutter è già pronto, invia subito
    if let channel = methodChannel {
      print("📲 Flutter ready, invoking onTextShared")
      channel.invokeMethod("onTextShared", arguments: text)
      // Salva anche come initialSharedText per getInitialSharedText
      initialSharedText = text
    } else {
      // Altrimenti salva per dopo
      print("⏳ Flutter not ready, saving as initialSharedText")
      initialSharedText = text
    }
  }

  private func loadSharedTextFromAppGroup() -> String? {
    let appGroupId = "group.com.privatemessaging.tuyjo"
    guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
      print("❌ Failed to access App Group: \(appGroupId)")
      return nil
    }

    guard let sharedText = userDefaults.string(forKey: "shared_text") else {
      print("⚠️ No shared text found in App Group")
      return nil
    }

    // Rimuovi dopo aver letto (usa solo una volta)
    userDefaults.removeObject(forKey: "shared_text")
    userDefaults.synchronize()

    return sharedText
  }

  private func loadSharedImagePathFromAppGroup() -> String? {
    let appGroupId = "group.com.privatemessaging.tuyjo"
    guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
      print("❌ Failed to access App Group: \(appGroupId)")
      return nil
    }

    guard let imagePath = userDefaults.string(forKey: "shared_image_path") else {
      print("⚠️ No shared image path found in App Group")
      return nil
    }

    // Rimuovi dopo aver letto (usa solo una volta)
    userDefaults.removeObject(forKey: "shared_image_path")
    userDefaults.synchronize()

    return imagePath
  }

  private func loadSharedDocumentPathFromAppGroup() -> String? {
    let appGroupId = "group.com.privatemessaging.tuyjo"
    guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
      print("❌ Failed to access App Group: \(appGroupId)")
      return nil
    }

    guard let documentPath = userDefaults.string(forKey: "shared_document_path") else {
      print("⚠️ No shared document path found in App Group")
      return nil
    }

    // Rimuovi dopo aver letto (usa solo una volta)
    userDefaults.removeObject(forKey: "shared_document_path")
    userDefaults.synchronize()

    return documentPath
  }
}


// MARK: - Ringback tone (425 Hz, 1 s on / 4 s off, cadenza europea)
//
// Sintetizzato con AVAudioEngine così non servono asset audio. Suona sulla
// sessione audio già configurata da CallKit/WebRTC (playAndRecord, voiceChat),
// quindi esce dall'auricolare o dall'altoparlante come la chiamata.
final class RingbackTonePlayer {
  private var engine: AVAudioEngine?
  private var sourceNode: AVAudioSourceNode?
  private var phase: Double = 0
  private var elapsedFrames: Double = 0

  private let frequency: Double = 425
  private let onSeconds: Double = 1.0
  private let periodSeconds: Double = 5.0
  private let amplitude: Float = 0.25

  func start() {
    stop()
    let engine = AVAudioEngine()
    var sampleRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    if sampleRate <= 0 { sampleRate = 48000 }
    let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1)
    phase = 0
    elapsedFrames = 0

    let node = AVAudioSourceNode { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
      guard let self = self else { return noErr }
      let ablPointer = UnsafeMutableAudioBufferListPointer(audioBufferList)
      let phaseIncrement = 2.0 * Double.pi * self.frequency / sampleRate
      for frame in 0..<Int(frameCount) {
        let t = self.elapsedFrames / sampleRate
        let inPeriod = t.truncatingRemainder(dividingBy: self.periodSeconds)
        let on = inPeriod < self.onSeconds
        let sample: Float = on ? Float(sin(self.phase)) * self.amplitude : 0
        self.phase += phaseIncrement
        if self.phase > 2.0 * Double.pi { self.phase -= 2.0 * Double.pi }
        self.elapsedFrames += 1
        for buffer in ablPointer {
          let buf = UnsafeMutableBufferPointer<Float>(buffer)
          buf[frame] = sample
        }
      }
      return noErr
    }

    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    engine.connect(engine.mainMixerNode, to: engine.outputNode, format: nil)
    engine.mainMixerNode.outputVolume = 1.0

    do {
      try engine.start()
      self.engine = engine
      self.sourceNode = node
      print("🔔 Ringback started")
    } catch {
      print("⚠️ Ringback engine failed to start: \(error)")
    }
  }

  func stop() {
    guard let engine = engine else { return }
    engine.stop()
    if let node = sourceNode {
      engine.detach(node)
    }
    self.engine = nil
    self.sourceNode = nil
    print("🔔 Ringback stopped")
  }
}
