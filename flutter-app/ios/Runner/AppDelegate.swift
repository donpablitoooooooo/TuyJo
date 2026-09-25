import UIKit
import Flutter
import PushKit
import Security
import AVFoundation
import UserNotifications
import flutter_callkit_incoming

@main
@objc class AppDelegate: FlutterAppDelegate, PKPushRegistryDelegate {
  /// Engine Flutter creato all'avvio dell'app, non dallo storyboard della scena.
  ///
  /// Con il lifecycle a scene l'engine "implicito" nasce solo quando iOS
  /// collega una scena (finestra). Quando l'app viene svegliata in background
  /// da un push VoIP la scena può non esserci: senza engine il plugin CallKit
  /// non esiste, la chiamata non viene riportata a CallKit (iOS termina l'app
  /// e può smettere di consegnarle i push VoIP) e Dart non può rispondere.
  /// La SceneDelegate mostra questo stesso engine quando la finestra arriva.
  lazy var flutterEngine = FlutterEngine(name: "tuyjo")
  private let CHANNEL = "com.privatemessaging.tuyjo/shared_media"
  private let TONE_CHANNEL = "com.privatemessaging.tuyjo/tone_generator"
  private let PROXIMITY_CHANNEL = "com.privatemessaging.tuyjo/proximity"
  private let BADGE_CHANNEL = "com.privatemessaging.tuyjo/badge"
  private var methodChannel: FlutterMethodChannel?
  private var toneChannel: FlutterMethodChannel?
  private var proximityChannel: FlutterMethodChannel?
  private var badgeChannel: FlutterMethodChannel?
  private let ringback = RingbackTonePlayer()
  private var initialMediaPaths: [String]?
  private var initialSharedText: String?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    // Prima di avviare Dart: le chiavi devono essere già leggibili anche a
    // iPhone bloccato (vedi migrateKeychainAccessibility).
    migrateKeychainAccessibility()
    let center = NotificationCenter.default
    for name in [
      UIApplication.protectedDataDidBecomeAvailableNotification,
      UIApplication.didBecomeActiveNotification,
      UIApplication.willResignActiveNotification,
    ] {
      center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
        self?.migrateKeychainAccessibility()
      }
    }

    // Engine e plugin PRIMA di PushKit: un push VoIP consegnato subito dopo
    // deve trovare il plugin CallKit già registrato.
    flutterEngine.run()
    GeneratedPluginRegistrant.register(with: flutterEngine)
    setUpChannels(messenger: flutterEngine.binaryMessenger)

    // PushKit VoIP: unico modo affidabile per far squillare una chiamata
    // su iOS con app in background o terminata. Il push arriva qui e va
    // riportato SUBITO a CallKit (obbligo iOS 13+, altrimenti l'app viene
    // terminata e il push VoIP non viene più consegnato).
    let voipRegistry = PKPushRegistry(queue: DispatchQueue.main)
    voipRegistry.delegate = self
    voipRegistry.desiredPushTypes = [PKPushType.voIP]

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  /// Porta le voci del Keychain dell'app (flutter_secure_storage) da
  /// WhenUnlocked, il default del plugin, a AfterFirstUnlock.
  ///
  /// Una chiamata accettata dalla schermata di sistema con iPhone bloccato
  /// deve poter leggere chiave privata e chiavi pubbliche della coppia: con
  /// WhenUnlocked la lettura falliva, la risposta non partiva e il chiamante
  /// continuava a squillare. È la stessa accessibilità usata dalle app di
  /// chiamata. Aggiornamento in place (SecItemUpdate): il valore non viene mai
  /// cancellato né riscritto.
  ///
  /// Si può fare solo a telefono sbloccato; viene ripetuta a ogni passaggio
  /// in/da foreground così copre anche le voci create dopo il primo avvio
  /// (nascono WhenUnlocked perché Dart non imposta l'accessibilità, vedi
  /// app_secure_storage.dart). Le voci del Keychain condiviso con la Share
  /// Extension hanno un altro service e non vengono toccate.
  @discardableResult
  func migrateKeychainAccessibility() -> OSStatus {
    guard UIApplication.shared.isProtectedDataAvailable else { return errSecInteractionNotAllowed }
    let query: [CFString: Any] = [
      kSecClass: kSecClassGenericPassword,
      kSecAttrService: "flutter_secure_storage_service",
      kSecAttrAccessible: kSecAttrAccessibleWhenUnlocked,
    ]
    let attributes: [CFString: Any] = [
      kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlock,
    ]
    let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
    if status == errSecSuccess {
      print("🔐 Keychain: voci portate ad AfterFirstUnlock")
    } else if status != errSecItemNotFound {
      print("⚠️ Keychain: migrazione accessibilità fallita (\(status))")
    }
    return status
  }

  /// Method channel dell'app, registrati sull'engine creato all'avvio.
  private func setUpChannels(messenger: FlutterBinaryMessenger) {
    // Configura il Method Channel
    methodChannel = FlutterMethodChannel(name: CHANNEL, binaryMessenger: messenger)

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
    toneChannel = FlutterMethodChannel(name: TONE_CHANNEL, binaryMessenger: messenger)
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

    // Sensore di prossimità durante la chiamata: iOS spegne da solo lo
    // schermo quando il telefono è all'orecchio finché il monitoring è attivo.
    proximityChannel = FlutterMethodChannel(name: PROXIMITY_CHANNEL, binaryMessenger: messenger)
    proximityChannel?.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) in
      switch call.method {
      case "enable":
        UIDevice.current.isProximityMonitoringEnabled = true
        result(UIDevice.current.isProximityMonitoringEnabled)
      case "disable":
        UIDevice.current.isProximityMonitoringEnabled = false
        result(true)
      default:
        result(FlutterMethodNotImplemented)
      }
    })

    // Badge sull'icona: il push lo imposta al numero di non letti, l'app lo
    // azzera quando i messaggi vengono letti. Senza questo restava fisso.
    badgeChannel = FlutterMethodChannel(name: BADGE_CHANNEL, binaryMessenger: messenger)
    badgeChannel?.setMethodCallHandler({ (call: FlutterMethodCall, result: @escaping FlutterResult) in
      guard call.method == "set" else {
        result(FlutterMethodNotImplemented)
        return
      }
      let count = (call.arguments as? Int) ?? 0
      if #available(iOS 16.0, *) {
        UNUserNotificationCenter.current().setBadgeCount(count) { error in
          if let error = error {
            print("⚠️ setBadgeCount failed: \(error)")
            DispatchQueue.main.async { UIApplication.shared.applicationIconBadgeNumber = count }
          }
          result(true)
        }
      } else {
        UIApplication.shared.applicationIconBadgeNumber = count
        result(true)
      }
    })
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

  /// Legge e cancella la coda scritta dalla Share Extension
  /// (`shared_queue.json` nel container App Group) e consegna tutto a Flutter:
  /// i file in un'unica chiamata, i testi uno per uno. Gestisce anche le
  /// chiavi UserDefaults del formato precedente.
  ///
  /// Chiamata da `SceneDelegate.sceneDidBecomeActive(_:)`.
  func drainSharedQueue() {
    let appGroupId = "group.com.privatemessaging.tuyjo"
    var files: [URL] = []
    var texts: [String] = []

    if let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) {
      let queueURL = container.appendingPathComponent("shared_queue.json")
      if let data = try? Data(contentsOf: queueURL) {
        try? FileManager.default.removeItem(at: queueURL)
        if let items = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
          for item in items {
            guard let value = item["value"], !value.isEmpty else { continue }
            if item["type"] == "file" {
              files.append(URL(fileURLWithPath: value))
            } else {
              texts.append(value)
            }
          }
        }
      }
    }

    // Formato precedente (chiavi singole in UserDefaults).
    if let ud = UserDefaults(suiteName: appGroupId) {
      for key in ["shared_image_path", "shared_document_path"] {
        if let path = ud.string(forKey: key) {
          ud.removeObject(forKey: key)
          files.append(URL(fileURLWithPath: path))
        }
      }
      if let text = ud.string(forKey: "shared_text") {
        ud.removeObject(forKey: "shared_text")
        texts.append(text)
      }
      ud.removeObject(forKey: "share_debug_log")
      ud.synchronize()
    }

    if !files.isEmpty { handleSharedMedia(files) }
    for text in texts { handleSharedText(text) }
  }

  /// Gestisce l'apertura di file/foto/URL condivisi.
  ///
  /// Chiamata da `SceneDelegate`: con il lifecycle a scene gli URL arrivano a
  /// `scene(_:openURLContexts:)` invece che all'AppDelegate.
  func handleIncomingURL(_ url: URL) -> Bool {
    print("📱 AppDelegate: handleIncomingURL called with URL: \(url)")
    print("📱 URL scheme: \(url.scheme ?? "nil"), pathExtension: \(url.pathExtension)")

    // Viene dalla Share Extension: svuota la coda nel container App Group
    if url.scheme?.lowercased() == "sharemedia" {
      print("📱 ShareMedia URL detected, draining shared queue...")
      drainSharedQueue()
      return true
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

    // Non gestito qui: il `SceneDelegate` ha già inoltrato l'URL ai plugin.
    return false
  }

  /// Universal Links e handoff.
  ///
  /// Chiamata da `SceneDelegate`: con il lifecycle a scene le user activity
  /// arrivano a `scene(_:continue:)` invece che all'AppDelegate.
  func handleUserActivity(_ userActivity: NSUserActivity) -> Bool {
    print("📱 AppDelegate: handleUserActivity called")
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
    // Non gestita qui: il `SceneDelegate` ha già inoltrato l'activity ai plugin.
    return false
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
      // NON salvare anche in initialMediaPaths: Flutter riceve già il push
      // (bufferizzato dal canale finché ChatScreen registra l'handler) e poi
      // chiama getInitialMedia → i file arriverebbero due volte.
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

      // L'originale scritto dalla Share Extension nel container dell'App Group
      // non serve più: rimuovilo, altrimenti il container accumula per sempre
      // copie in chiaro dei file condivisi.
      if let groupURL = FileManager.default.containerURL(
           forSecurityApplicationGroupIdentifier: "group.com.privatemessaging.tuyjo"),
         url.path.hasPrefix(groupURL.path) {
        try? FileManager.default.removeItem(at: url)
        print("🧹 Removed App Group original")
      }

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
      // NON salvare anche in initialSharedText: il push viene bufferizzato dal
      // canale e consegnato appena ChatScreen registra l'handler; con la copia
      // in initialSharedText, getInitialSharedText lo rimandava una seconda
      // volta → link duplicato in chat (stesso fix già fatto su Android).
    } else {
      // Altrimenti salva per dopo
      print("⏳ Flutter not ready, saving as initialSharedText")
      initialSharedText = text
    }
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
