import UIKit
import Flutter

@UIApplicationMain
@objc class AppDelegate: FlutterAppDelegate {
  private let CHANNEL = "com.privatemessaging.tuyjo/shared_media"
  private var methodChannel: FlutterMethodChannel?
  private var initialMediaPaths: [String]?
  private var initialSharedText: String?
  private let appGroupName = "group.com.privatemessaging.tuyjo"
  private let sharedKey = "ShareKey"

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

    // Controlla se ci sono dati condivisi dall'estensione
    checkSharedData()

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  // Gestisce l'apertura di file/foto condivise (iOS 9+)
  override func application(_ app: UIApplication, open url: URL, options: [UIApplication.OpenURLOptionsKey : Any] = [:]) -> Bool {
    print("📱 AppDelegate: application:open:options called with URL: \(url)")
    print("📱 URL scheme: \(url.scheme ?? "nil"), pathExtension: \(url.pathExtension)")

    // Se viene dall'estensione, controlla i dati condivisi
    if url.scheme == "tuyjo" && url.host == "share" {
      checkSharedData()
      return true
    }

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
       let url = userActivity.webpageURL,
       isMediaFile(url) {
      print("📱 Handling media file from user activity: \(url)")
      handleSharedMedia([url])
      return true
    }
    return super.application(application, continue: userActivity, restorationHandler: restorationHandler)
  }

  override func applicationDidBecomeActive(_ application: UIApplication) {
    print("📱 App became active, checking for shared data")
    checkSharedData()
    super.applicationDidBecomeActive(application)
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

  private func checkSharedData() {
    print("🔍 Checking shared data from extension")

    guard let sharedDefaults = UserDefaults(suiteName: appGroupName),
          let sharedData = sharedDefaults.array(forKey: sharedKey) as? [[String: Any]],
          !sharedData.isEmpty else {
      print("⚠️ No shared data found")
      return
    }

    print("📦 Found \(sharedData.count) shared item(s)")

    var filePaths: [String] = []
    var textContents: [String] = []

    for data in sharedData {
      guard let type = data["type"] as? String,
            let content = data["content"] as? String else {
        continue
      }

      print("📋 Processing shared \(type): \(content)")

      switch type {
      case "file":
        // File già copiato dall'estensione
        filePaths.append(content)
      case "text", "url":
        // Testo o URL condiviso
        textContents.append(content)
      default:
        break
      }
    }

    // Pulisci i dati condivisi
    sharedDefaults.removeObject(forKey: sharedKey)
    sharedDefaults.synchronize()

    // Invia i dati a Flutter
    if !filePaths.isEmpty {
      if let channel = methodChannel {
        print("📲 Sending \(filePaths.count) file(s) to Flutter")
        channel.invokeMethod("onMediaShared", arguments: filePaths)
      }
      initialMediaPaths = filePaths
    }

    if !textContents.isEmpty {
      // Concatena tutti i testi con newline
      let combinedText = textContents.joined(separator: "\n")
      if let channel = methodChannel {
        print("📲 Sending text to Flutter: \(combinedText)")
        channel.invokeMethod("onTextShared", arguments: combinedText)
      }
      initialSharedText = combinedText
    }
  }
}
