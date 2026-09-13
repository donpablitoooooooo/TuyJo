import UIKit
import Social
import UniformTypeIdentifiers

/// Share Extension di Tuijo.
///
/// Raccoglie TUTTI gli elementi condivisi (fino a 10 immagini, documenti,
/// testo/URL), li mette in coda nel container dell'App Group e apre l'app
/// principale con lo schema `ShareMedia://open`. L'app svuota la coda in
/// `application(_:open:)` e, come rete di sicurezza, in
/// `applicationDidBecomeActive`.
///
/// Coda: file JSON `shared_queue.json` nel container (protezione
/// NSFileProtectionComplete, cancellato dall'app dopo la lettura), array di
/// `{"type": "text" | "file", "value": ...}`. I file vengono salvati in
/// `shared_media/` con la stessa protezione e rimossi dall'app dopo la copia.
class ShareViewController: UIViewController {
    private let appGroupId = "group.com.privatemessaging.tuyjo"
    static let queueFileName = "shared_queue.json"

    /// viewDidAppear può scattare più volte (l'utente torna sull'app host e
    /// l'estensione viene ripresentata): il contenuto va gestito UNA volta.
    private var didHandle = false

    private let documentTypes: [String] = [
        UTType.pdf.identifier,
        "com.microsoft.word.doc",
        "org.openxmlformats.wordprocessingml.document",
        "com.microsoft.excel.xls",
        "org.openxmlformats.spreadsheetml.sheet",
        "com.microsoft.powerpoint.ppt",
        "org.openxmlformats.presentationml.presentation",
    ]

    override func loadView() {
        let v = UIView()
        v.backgroundColor = .clear
        v.isOpaque = false
        self.view = v
    }

    override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        view.superview?.backgroundColor = .clear
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !didHandle else { return }
        didHandle = true
        handleSharedContent()
    }

    private func debugLog(_ msg: String) {
        #if DEBUG
        print("📤 [ShareExtension] \(msg)")
        #endif
    }

    // MARK: - Raccolta degli elementi condivisi

    private func handleSharedContent() {
        guard let items = extensionContext?.inputItems as? [NSExtensionItem] else {
            closeExtension()
            return
        }
        let attachments = items.compactMap { $0.attachments }.flatMap { $0 }
        guard !attachments.isEmpty else {
            closeExtension()
            return
        }
        debugLog("found \(attachments.count) attachment(s)")

        let group = DispatchGroup()
        let lock = NSLock()
        var filePaths: [String] = []
        var texts: [String] = []
        var handledAny = false

        func addFile(_ path: String) {
            lock.lock(); filePaths.append(path); lock.unlock()
        }
        func addText(_ text: String) {
            lock.lock(); texts.append(text); lock.unlock()
        }

        // 1) Immagini: tutte, non solo la prima (il plist ne dichiara fino a 10).
        for attachment in attachments where attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            handledAny = true
            group.enter()
            loadImage(attachment) { path in
                if let path = path { addFile(path) }
                group.leave()
            }
        }

        // 2) Documenti (prima di URL/testo: un documento conforma anche a UTType.url).
        for attachment in attachments where !attachment.hasItemConformingToTypeIdentifier(UTType.image.identifier) {
            let isDocument = documentTypes.contains { attachment.hasItemConformingToTypeIdentifier($0) }
            guard isDocument else { continue }
            handledAny = true
            group.enter()
            loadDocument(attachment) { path in
                if let path = path { addFile(path) }
                group.leave()
            }
        }

        // 3) Testo / URL (solo se non ci sono già immagini o documenti).
        if !handledAny {
            let textAttachment = attachments.first { $0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) }
            let urlAttachment = attachments.first { $0.hasItemConformingToTypeIdentifier(UTType.url.identifier) }
            if textAttachment != nil || urlAttachment != nil {
                handledAny = true
                group.enter()
                loadTextOrUrl(textAttachment: textAttachment, urlAttachment: urlAttachment) { text in
                    if let text = text { addText(text) }
                    group.leave()
                }
            }
        }

        // 4) fileURL generico (file locale) come documento; URL web come link.
        if !handledAny {
            for attachment in attachments where attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) {
                handledAny = true
                group.enter()
                attachment.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { [weak self] item, _ in
                    defer { group.leave() }
                    guard let self = self, let url = item as? URL else { return }
                    let s = url.absoluteString.lowercased()
                    if s.hasPrefix("http://") || s.hasPrefix("https://") {
                        addText(url.absoluteString)
                    } else if let path = self.saveFileURL(url) {
                        addFile(path)
                    }
                }
                break
            }
        }

        guard handledAny else {
            closeExtension()
            return
        }

        group.notify(queue: .main) { [weak self] in
            guard let self = self else { return }
            var queue: [[String: String]] = []
            for p in filePaths { queue.append(["type": "file", "value": p]) }
            for t in texts { queue.append(["type": "text", "value": t]) }
            guard !queue.isEmpty, self.appendToQueue(queue) else {
                self.debugLog("nothing to enqueue or write failed")
                self.closeExtension()
                return
            }
            self.openMainApp()
        }
    }

    // MARK: - Caricamento singoli elementi

    private func loadImage(_ attachment: NSItemProvider, completion: @escaping (String?) -> Void) {
        attachment.loadItem(forTypeIdentifier: UTType.image.identifier, options: nil) { [weak self] item, _ in
            guard let self = self else { completion(nil); return }
            var data: Data?
            var ext = "jpg"
            if let url = item as? URL {
                data = self.readData(url)
                ext = url.pathExtension.isEmpty ? "jpg" : url.pathExtension
            } else if let image = item as? UIImage {
                data = image.jpegData(compressionQuality: 0.9)
            } else if let d = item as? Data {
                data = d
            }
            guard let bytes = data else { completion(nil); return }
            completion(self.saveToSharedMedia(bytes, fileName: "shared_\(self.uniqueSuffix()).\(ext)"))
        }
    }

    private func loadDocument(_ attachment: NSItemProvider, completion: @escaping (String?) -> Void) {
        let typeId = attachment.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier)
            ? UTType.fileURL.identifier
            : UTType.data.identifier
        attachment.loadItem(forTypeIdentifier: typeId, options: nil) { [weak self] item, _ in
            guard let self = self else { completion(nil); return }
            if let url = item as? URL {
                completion(self.saveFileURL(url))
            } else if let data = item as? Data {
                let name = attachment.suggestedName ?? "shared_document"
                completion(self.saveToSharedMedia(data, fileName: "\(self.uniqueSuffix())_\(name)"))
            } else {
                completion(nil)
            }
        }
    }

    private func loadTextOrUrl(textAttachment: NSItemProvider?, urlAttachment: NSItemProvider?,
                               completion: @escaping (String?) -> Void) {
        if let textAtt = textAttachment {
            textAtt.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] item, _ in
                guard let self = self, let text = item as? String else {
                    // Testo non leggibile: prova con l'URL.
                    if let strongSelf = self {
                        strongSelf.loadUrl(urlAttachment, completion: completion)
                    } else {
                        completion(nil)
                    }
                    return
                }
                let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
                if self.extractURL(from: text) != nil || urlAttachment == nil {
                    // Il testo contiene già il link (o non c'è un URL separato).
                    completion(trimmed.isEmpty ? nil : text)
                    return
                }
                // Testo senza URL + URL separato: combina.
                self.loadUrl(urlAttachment) { url in
                    if let url = url {
                        completion(trimmed.isEmpty ? url : "\(text)\n\(url)")
                    } else {
                        completion(trimmed.isEmpty ? nil : text)
                    }
                }
            }
            return
        }
        loadUrl(urlAttachment, completion: completion)
    }

    private func loadUrl(_ attachment: NSItemProvider?, completion: @escaping (String?) -> Void) {
        guard let att = attachment else { completion(nil); return }
        att.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { item, _ in
            completion((item as? URL)?.absoluteString)
        }
    }

    // MARK: - File nel container App Group

    private func readData(_ url: URL) -> Data? {
        let accessing = url.startAccessingSecurityScopedResource()
        defer { if accessing { url.stopAccessingSecurityScopedResource() } }
        return try? Data(contentsOf: url)
    }

    private func saveFileURL(_ url: URL) -> String? {
        guard let data = readData(url) else { return nil }
        return saveToSharedMedia(data, fileName: "\(uniqueSuffix())_\(url.lastPathComponent)")
    }

    private func uniqueSuffix() -> String {
        "\(Int(Date().timeIntervalSince1970 * 1000))_\(Int.random(in: 1000...9999))"
    }

    private func sharedMediaDir() -> URL? {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return nil
        }
        let dir = container.appendingPathComponent("shared_media", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    /// Scrive il file con NSFileProtectionComplete: leggibile solo a telefono
    /// sbloccato (l'app lo legge in foreground e lo cancella subito dopo).
    private func saveToSharedMedia(_ data: Data, fileName: String) -> String? {
        guard let dir = sharedMediaDir() else { return nil }
        let fileURL = dir.appendingPathComponent(fileName)
        do {
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return fileURL.path
        } catch {
            debugLog("save failed: \(error)")
            return nil
        }
    }

    /// Accoda gli elementi al file JSON (append: due condivisioni ravvicinate
    /// non si sovrascrivono più).
    private func appendToQueue(_ items: [[String: String]]) -> Bool {
        guard let container = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupId) else {
            return false
        }
        let fileURL = container.appendingPathComponent(ShareViewController.queueFileName)
        var queue: [[String: String]] = []
        if let data = try? Data(contentsOf: fileURL),
           let existing = try? JSONSerialization.jsonObject(with: data) as? [[String: String]] {
            queue = existing
        }
        queue.append(contentsOf: items)
        do {
            let data = try JSONSerialization.data(withJSONObject: queue)
            try data.write(to: fileURL, options: [.atomic, .completeFileProtection])
            return true
        } catch {
            debugLog("queue write failed: \(error)")
            return false
        }
    }

    private func extractURL(from text: String) -> String? {
        let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
        let matches = detector?.matches(in: text, options: [], range: NSRange(location: 0, length: text.utf16.count)) ?? []
        for match in matches {
            if let range = Range(match.range, in: text) {
                let s = String(text[range]).lowercased()
                if s.hasPrefix("http://") || s.hasPrefix("https://") { return String(text[range]) }
            }
        }
        return matches.isEmpty ? nil : matches.compactMap { Range($0.range, in: text).map { String(text[$0]) } }.first
    }

    // MARK: - Apertura dell'app principale

    private func openMainApp() {
        guard let url = URL(string: "ShareMedia://open"), let ctx = extensionContext else {
            showOpenAppHint()
            return
        }
        // Solo l'API ufficiale delle estensioni. Se non riesce, il contenuto
        // resta in coda e l'app lo prende al prossimo avvio: lo diciamo
        // all'utente invece di usare API private (rischio App Review).
        ctx.open(url) { [weak self] success in
            DispatchQueue.main.async {
                if success {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { self?.closeExtension() }
                } else {
                    self?.showOpenAppHint()
                }
            }
        }
    }

    /// Testi localizzati in codice: l'estensione non ha risorse .lproj.
    private func localized(_ key: String) -> String {
        let lang = Locale.preferredLanguages.first?.lowercased() ?? "en"
        let code = lang.hasPrefix("it") ? "it" : lang.hasPrefix("es") ? "es" : lang.hasPrefix("ca") ? "ca" : "en"
        let table: [String: [String: String]] = [
            "title": ["it": "Quasi fatto", "en": "Almost done", "es": "Casi listo", "ca": "Gairebé fet"],
            "body": [
                "it": "Apri Tuijo per completare l'invio: il contenuto è pronto e verrà inserito appena apri l'app.",
                "en": "Open Tuijo to finish sending: the content is ready and will be added as soon as you open the app.",
                "es": "Abre Tuijo para completar el envío: el contenido está listo y se añadirá en cuanto abras la app.",
                "ca": "Obre Tuijo per completar l'enviament: el contingut està a punt i s'afegirà tan bon punt obris l'app.",
            ],
            "ok": ["it": "OK", "en": "OK", "es": "OK", "ca": "D'acord"],
        ]
        return table[key]?[code] ?? table[key]?["en"] ?? key
    }

    private func showOpenAppHint() {
        let alert = UIAlertController(title: localized("title"), message: localized("body"), preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: localized("ok"), style: .default) { [weak self] _ in
            self?.closeExtension()
        })
        present(alert, animated: true)
    }

    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
