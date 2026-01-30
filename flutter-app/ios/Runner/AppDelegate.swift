import UIKit
import Flutter

@main
@objc class AppDelegate: FlutterAppDelegate {
  private let CHANNEL = "com.privatemessaging.tuyjo/shared_media"
  private var methodChannel: FlutterMethodChannel?
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

    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
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
