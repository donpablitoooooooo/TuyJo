import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private let appGroupId = "group.com.privatemessaging.tuyjo"

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedContent()
    }

    private func handleSharedContent() {
        guard let extensionItem = extensionContext?.inputItems.first as? NSExtensionItem,
              let attachments = extensionItem.attachments else {
            closeExtension()
            return
        }

        // Prima passa: cerca immagini
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
                handleImage(attachment)
                return
            }
        }

        // Seconda passa: cerca URL (priorità su testo)
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                    if let url = item as? URL {
                        self?.saveToAppGroup(text: url.absoluteString, key: "shared_text")
                        self?.openMainApp()
                    } else {
                        self?.closeExtension()
                    }
                }
                return
            }
        }

        // Terza passa: cerca testo
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, error) in
                    if let text = item as? String {
                        // Controlla se il testo contiene un URL
                        if let url = self?.extractURL(from: text) {
                            self?.saveToAppGroup(text: url, key: "shared_text")
                        } else {
                            self?.saveToAppGroup(text: text, key: "shared_text")
                        }
                        self?.openMainApp()
                    } else {
                        self?.closeExtension()
                    }
                }
                return
            }
        }

        closeExtension()
    }

    private func handleImage(_ attachment: NSItemProvider) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] (item, error) in
            guard let self = self else { return }

            var imageData: Data?
            var fileExtension = "jpg"

            if let url = item as? URL {
                // L'immagine è un file URL
                imageData = try? Data(contentsOf: url)
                fileExtension = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            } else if let image = item as? UIImage {
                // L'immagine è un UIImage
                imageData = image.jpegData(compressionQuality: 0.9)
                fileExtension = "jpg"
            } else if let data = item as? Data {
                // L'immagine è già Data
                imageData = data
                fileExtension = "jpg"
            }

            guard let data = imageData else {
                self.closeExtension()
                return
            }

            // Salva l'immagine nel container App Group
            if let imagePath = self.saveImageToAppGroup(data: data, extension: fileExtension) {
                self.saveToAppGroup(text: imagePath, key: "shared_image_path")
                self.openMainApp()
            } else {
                self.closeExtension()
            }
        }
    }

    private func saveImageToAppGroup(data: Data, extension ext: String) -> String? {
        guard let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            print("❌ Failed to get App Group container")
            return nil
        }

        let sharedDir = containerURL.appendingPathComponent("shared_media", isDirectory: true)

        do {
            try FileManager.default.createDirectory(at: sharedDir, withIntermediateDirectories: true)
        } catch {
            print("❌ Failed to create shared_media directory: \(error)")
            return nil
        }

        let timestamp = Int(Date().timeIntervalSince1970 * 1000)
        let fileName = "shared_\(timestamp).\(ext)"
        let fileURL = sharedDir.appendingPathComponent(fileName)

        do {
            try data.write(to: fileURL)
            print("✅ Saved image to: \(fileURL.path)")
            return fileURL.path
        } catch {
            print("❌ Failed to save image: \(error)")
            return nil
        }
    }

    private func extractURL(from text: String) -> String? {
        // Cerca URL nel testo
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        if let match = matches?.first, let range = Range(match.range, in: text) {
            return String(text[range])
        }
        return nil
    }

    private func saveToAppGroup(text: String, key: String) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            print("❌ Failed to access App Group: \(appGroupId)")
            return
        }

        userDefaults.set(text, forKey: key)
        userDefaults.synchronize()
        print("✅ Saved to App Group [\(key)]: \(text)")
    }

    private func openMainApp() {
        let urlString = "ShareMedia://open"

        guard let url = URL(string: urlString) else {
            closeExtension()
            return
        }

        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self as UIResponder

        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                break
            }
            responder = r.next
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
            self?.closeExtension()
        }
    }

    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
