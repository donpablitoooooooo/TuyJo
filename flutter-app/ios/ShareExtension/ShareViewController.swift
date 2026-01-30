import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
    private let appGroupId = "group.com.privatemessaging.tuyjo"

    override func loadView() {
        // No visible UI — just process and open the main app
        let v = UIView()
        v.backgroundColor = .clear
        v.isOpaque = false
        self.view = v
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        handleSharedContent()
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        // Also clear the system-provided container background
        view.superview?.backgroundColor = .clear
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

        // Seconda passa: cerca URL o testo (PRIMA dei documenti per evitare che .html venga trattato come documento)
        var hasText = false
        var hasUrl = false
        var textAttachment: NSItemProvider?
        var urlAttachment: NSItemProvider?

        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                hasText = true
                textAttachment = attachment
            }
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                hasUrl = true
                urlAttachment = attachment
            }
        }

        // Se c'è un URL o testo con URL, gestiscilo come link (non come documento)
        if hasUrl || hasText {
            handleTextOrUrl(hasText: hasText, hasUrl: hasUrl, textAttachment: textAttachment, urlAttachment: urlAttachment)
            return
        }

        // Terza passa: cerca documenti (PDF, DOC, XLS, PPT, etc.) - solo se non c'è URL
        for attachment in attachments {
            // Controlla tipi specifici di documento (esclude fileURL generico per evitare conflitti con link)
            if attachment.hasItemConformingToTypeIdentifier(UTType.pdf.identifier) ||
               attachment.hasItemConformingToTypeIdentifier("com.microsoft.word.doc") ||
               attachment.hasItemConformingToTypeIdentifier("org.openxmlformats.wordprocessingml.document") ||
               attachment.hasItemConformingToTypeIdentifier("com.microsoft.excel.xls") ||
               attachment.hasItemConformingToTypeIdentifier("org.openxmlformats.spreadsheetml.sheet") ||
               attachment.hasItemConformingToTypeIdentifier("com.microsoft.powerpoint.ppt") ||
               attachment.hasItemConformingToTypeIdentifier("org.openxmlformats.presentationml.presentation") {
                handleDocument(attachment)
                return
            }
        }

        // Quarta passa: fileURL generico (solo per file locali, non web)
        for attachment in attachments {
            if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                // Verifica che non sia un URL web
                attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] (item, error) in
                    if let url = item as? URL {
                        let urlString = url.absoluteString.lowercased()
                        // Se è un URL web, trattalo come link
                        if urlString.hasPrefix("http://") || urlString.hasPrefix("https://") {
                            self?.saveToAppGroup(text: url.absoluteString, key: "shared_text")
                            self?.openMainApp()
                        } else {
                            // È un file locale, trattalo come documento
                            self?.handleDocumentFromFileURL(url)
                        }
                    } else {
                        self?.closeExtension()
                    }
                }
                return
            }
        }

        closeExtension()
    }

    private func handleTextOrUrl(hasText: Bool, hasUrl: Bool, textAttachment: NSItemProvider?, urlAttachment: NSItemProvider?) {
        // Strategia: preferisci il testo se contiene un URL (più completo)
        // Altrimenti usa l'URL diretto
        if hasText, let textAtt = textAttachment {
            textAtt.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, error) in
                if let text = item as? String {
                    // Controlla se il testo contiene un URL
                    if let extractedUrl = self?.extractURL(from: text) {
                        // Se il testo è SOLO l'URL, salva l'URL
                        // Se il testo contiene altro oltre all'URL, salva il testo completo
                        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
                        if trimmedText == extractedUrl {
                            self?.saveToAppGroup(text: extractedUrl, key: "shared_text")
                        } else {
                            // Testo contiene più dell'URL - salva tutto
                            self?.saveToAppGroup(text: text, key: "shared_text")
                        }
                        self?.openMainApp()
                    } else if hasUrl, let urlAtt = urlAttachment {
                        // Il testo non ha URL, prova con l'URL attachment
                        urlAtt.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (urlItem, urlError) in
                            if let url = urlItem as? URL {
                                // Combina testo + URL se il testo non è vuoto
                                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    self?.saveToAppGroup(text: "\(text)\n\(url.absoluteString)", key: "shared_text")
                                } else {
                                    self?.saveToAppGroup(text: url.absoluteString, key: "shared_text")
                                }
                                self?.openMainApp()
                            } else {
                                // Salva solo il testo
                                self?.saveToAppGroup(text: text, key: "shared_text")
                                self?.openMainApp()
                            }
                        }
                    } else {
                        // Solo testo senza URL
                        self?.saveToAppGroup(text: text, key: "shared_text")
                        self?.openMainApp()
                    }
                } else {
                    self?.closeExtension()
                }
            }
            return
        }

        // Se non c'è testo, usa solo l'URL
        if hasUrl, let urlAtt = urlAttachment {
            urlAtt.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                if let url = item as? URL {
                    self?.saveToAppGroup(text: url.absoluteString, key: "shared_text")
                    self?.openMainApp()
                } else {
                    self?.closeExtension()
                }
            }
            return
        }

        closeExtension()
    }

    private func handleDocumentFromFileURL(_ url: URL) {
        // Accedi al file con security scope se necessario
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing { url.stopAccessingSecurityScopedResource() }
        }

        if let data = try? Data(contentsOf: url) {
            let fileName = url.lastPathComponent
            if let documentPath = saveDocumentToAppGroup(data: data, fileName: fileName) {
                saveToAppGroup(text: documentPath, key: "shared_document_path")
                openMainApp()
                return
            }
        }
        closeExtension()
    }

    private func handleDocument(_ attachment: NSItemProvider) {
        // Prova con fileURL prima (più comune per documenti)
        if attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] (item, error) in
                guard let self = self else { return }

                if let url = item as? URL {
                    // Accedi al file con security scope se necessario
                    let accessing = url.startAccessingSecurityScopedResource()
                    defer {
                        if accessing { url.stopAccessingSecurityScopedResource() }
                    }

                    if let data = try? Data(contentsOf: url) {
                        let fileName = url.lastPathComponent
                        if let documentPath = self.saveDocumentToAppGroup(data: data, fileName: fileName) {
                            self.saveToAppGroup(text: documentPath, key: "shared_document_path")
                            self.openMainApp()
                            return
                        }
                    }
                }
                self.closeExtension()
            }
            return
        }

        // Fallback: prova con data generico
        if attachment.hasItemConformingToTypeIdentifier(UTType.data.identifier) {
            attachment.loadItem(forTypeIdentifier: UTType.data.identifier, options: nil) { [weak self] (item, error) in
                guard let self = self else { return }

                var documentData: Data?
                var fileName = "shared_document"

                if let url = item as? URL {
                    documentData = try? Data(contentsOf: url)
                    fileName = url.lastPathComponent
                } else if let data = item as? Data {
                    documentData = data
                    // Prova a determinare l'estensione dal suggestedName
                    if let suggestedName = attachment.suggestedName {
                        fileName = suggestedName
                    }
                }

                guard let data = documentData else {
                    self.closeExtension()
                    return
                }

                if let documentPath = self.saveDocumentToAppGroup(data: data, fileName: fileName) {
                    self.saveToAppGroup(text: documentPath, key: "shared_document_path")
                    self.openMainApp()
                } else {
                    self.closeExtension()
                }
            }
            return
        }

        closeExtension()
    }

    private func saveDocumentToAppGroup(data: Data, fileName: String) -> String? {
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
        // Usa il nome file originale con timestamp per evitare conflitti
        let safeFileName = "\(timestamp)_\(fileName)"
        let fileURL = sharedDir.appendingPathComponent(safeFileName)

        do {
            try data.write(to: fileURL)
            print("✅ Saved document to: \(fileURL.path)")
            return fileURL.path
        } catch {
            print("❌ Failed to save document: \(error)")
            return nil
        }
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
        // Cerca tutti gli URL nel testo
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count))

        guard let matches = matches, !matches.isEmpty else {
            return nil
        }

        // Estrai tutti gli URL trovati
        var urls: [String] = []
        for match in matches {
            if let range = Range(match.range, in: text) {
                urls.append(String(text[range]))
            }
        }

        // Se c'è un solo URL, restituiscilo
        if urls.count == 1 {
            return urls.first
        }

        // Se ci sono più URL, preferisci quello con https://
        if let httpsUrl = urls.first(where: { $0.lowercased().hasPrefix("https://") }) {
            return httpsUrl
        }

        // Altrimenti preferisci quello con http://
        if let httpUrl = urls.first(where: { $0.lowercased().hasPrefix("http://") }) {
            return httpUrl
        }

        // Fallback al primo URL trovato
        return urls.first
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
        guard let url = URL(string: "ShareMedia://open") else {
            closeExtension()
            return
        }

        // Must dispatch to main thread — called from loadItem background callbacks
        DispatchQueue.main.async { [weak self] in
            guard let self = self else { return }

            // 1) Try the official NSExtensionContext.open API
            self.extensionContext?.open(url) { success in
                if success {
                    // App opened — do NOT call completeRequest, it can cancel the open
                    return
                }
                // 2) Fallback: walk the responder chain with the modern selector
                DispatchQueue.main.async {
                    self.openViaResponderChain(url)
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                        self.closeExtension()
                    }
                }
            }
        }
    }

    private func openViaResponderChain(_ url: URL) {
        // Modern open(_:options:completionHandler:) — needed on iOS 18+
        let selector = sel_registerName("openURL:options:completionHandler:")
        var responder: UIResponder? = self as UIResponder

        while let r = responder {
            if r.responds(to: selector), let imp = r.method(for: selector) {
                typealias Fn = @convention(c) (AnyObject, Selector, Any, Any, Any?) -> Void
                let open = unsafeBitCast(imp, to: Fn.self)
                let cb: @convention(block) (Bool) -> Void = { _ in }
                open(r, selector, url as Any, [:] as NSDictionary as Any, cb as Any)
                return
            }
            responder = r.next
        }

        // Legacy openURL: for iOS < 18
        let legacy = sel_registerName("openURL:")
        responder = self as UIResponder
        while let r = responder {
            if r.responds(to: legacy) {
                r.perform(legacy, with: url)
                return
            }
            responder = r.next
        }
    }

    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
