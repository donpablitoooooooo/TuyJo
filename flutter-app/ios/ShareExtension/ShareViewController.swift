import UIKit
import Social
import MobileCoreServices
import UniformTypeIdentifiers

class ShareViewController: UIViewController {

    private let appGroupName = "group.com.privatemessaging.tuyjo"
    private let sharedKey = "ShareKey"

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let itemProvider = extensionItem.attachments?.first else {
            closeExtension()
            return
        }

        // Controlla se è testo/URL
        if itemProvider.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
            handleURL(itemProvider)
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.text.identifier) {
            handleText(itemProvider)
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            handleImage(itemProvider)
        } else if itemProvider.hasItemConformingToTypeIdentifier(UTType.movie.identifier) {
            handleVideo(itemProvider)
        } else {
            closeExtension()
        }
    }

    private func handleURL(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
            if let url = item as? URL {
                self?.saveSharedData(type: "url", content: url.absoluteString)
            } else if let error = error {
                print("Error loading URL: \(error)")
            }
            self?.openMainApp()
        }
    }

    private func handleText(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: UTType.text.identifier, options: nil) { [weak self] (item, error) in
            if let text = item as? String {
                self?.saveSharedData(type: "text", content: text)
            } else if let error = error {
                print("Error loading text: \(error)")
            }
            self?.openMainApp()
        }
    }

    private func handleImage(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
            if let url = item as? URL {
                self?.saveSharedFile(url: url)
            } else if let error = error {
                print("Error loading image: \(error)")
            }
            self?.openMainApp()
        }
    }

    private func handleVideo(_ itemProvider: NSItemProvider) {
        itemProvider.loadItem(forTypeIdentifier: UTType.movie.identifier, options: nil) { [weak self] (item, error) in
            if let url = item as? URL {
                self?.saveSharedFile(url: url)
            } else if let error = error {
                print("Error loading video: \(error)")
            }
            self?.openMainApp()
        }
    }

    private func saveSharedData(type: String, content: String) {
        let sharedDefaults = UserDefaults(suiteName: appGroupName)
        let data: [String: Any] = [
            "type": type,
            "content": content,
            "timestamp": Date().timeIntervalSince1970
        ]

        // Salva come array per supportare multiple condivisioni
        var existingData = sharedDefaults?.array(forKey: sharedKey) as? [[String: Any]] ?? []
        existingData.append(data)
        sharedDefaults?.set(existingData, forKey: sharedKey)
        sharedDefaults?.synchronize()

        print("✅ Saved shared \(type): \(content)")
    }

    private func saveSharedFile(url: URL) {
        do {
            // Accedi al file
            let accessing = url.startAccessingSecurityScopedResource()
            defer {
                if accessing {
                    url.stopAccessingSecurityScopedResource()
                }
            }

            // Directory condivisa
            guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupName) else {
                print("❌ Cannot access app group container")
                return
            }

            let sharedDir = containerURL.appendingPathComponent("shared_media", isDirectory: true)
            try? FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)

            // Copia il file
            let timestamp = Int(Date().timeIntervalSince1970 * 1000)
            let ext = url.pathExtension
            let fileName = "shared_\(timestamp).\(ext)"
            let destURL = sharedDir.appendingPathComponent(fileName)

            if FileManager.default.fileExists(atPath: destURL.path) {
                try? FileManager.default.removeItem(at: destURL)
            }

            try FileManager.default.copyItem(at: url, to: destURL)

            // Salva il path nei UserDefaults
            let sharedDefaults = UserDefaults(suiteName: appGroupName)
            let data: [String: Any] = [
                "type": "file",
                "content": destURL.path,
                "timestamp": Date().timeIntervalSince1970
            ]

            var existingData = sharedDefaults?.array(forKey: sharedKey) as? [[String: Any]] ?? []
            existingData.append(data)
            sharedDefaults?.set(existingData, forKey: sharedKey)
            sharedDefaults?.synchronize()

            print("✅ Saved shared file: \(destURL.path)")

        } catch {
            print("❌ Error saving file: \(error)")
        }
    }

    private func openMainApp() {
        DispatchQueue.main.async { [weak self] in
            // Chiudi l'estensione e ritorna all'app principale
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: { _ in
                // Opzionale: apri l'app principale tramite URL scheme
                if let url = URL(string: "tuyjo://share") {
                    _ = self?.openURL(url)
                }
            })
        }
    }

    private func closeExtension() {
        DispatchQueue.main.async { [weak self] in
            self?.extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
        }
    }

    // Helper per aprire URL (iOS 10+)
    @discardableResult
    private func openURL(_ url: URL) -> Bool {
        var responder: UIResponder? = self
        while responder != nil {
            if let application = responder as? UIApplication {
                if #available(iOS 10.0, *) {
                    application.open(url, options: [:], completionHandler: nil)
                    return true
                } else {
                    return application.openURL(url)
                }
            }
            responder = responder?.next
        }
        return false
    }
}
