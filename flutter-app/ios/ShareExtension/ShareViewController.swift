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

        // Gestisci URL/Text
        for attachment in attachments {
            // Prova URL prima
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { [weak self] (item, error) in
                    if let url = item as? URL {
                        self?.saveToAppGroup(text: url.absoluteString)
                        self?.openMainApp()
                    } else {
                        self?.closeExtension()
                    }
                }
                return
            }
            // Poi prova plain text
            else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { [weak self] (item, error) in
                    if let text = item as? String {
                        self?.saveToAppGroup(text: text)
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

    private func saveToAppGroup(text: String) {
        guard let userDefaults = UserDefaults(suiteName: appGroupId) else {
            print("❌ Failed to access App Group: \(appGroupId)")
            return
        }

        // Salva il testo nell'App Group
        userDefaults.set(text, forKey: "shared_text")
        userDefaults.synchronize()
        print("✅ Saved text to App Group: \(text)")
    }

    private func openMainApp() {
        // Usa URL scheme per aprire l'app principale
        let urlString = "ShareMedia://open"

        guard let url = URL(string: urlString) else {
            closeExtension()
            return
        }

        // Apri l'app con extensionContext (modo corretto su iOS moderno)
        let selector = sel_registerName("openURL:")
        var responder: UIResponder? = self as UIResponder

        while let r = responder {
            if r.responds(to: selector) {
                r.perform(selector, with: url)
                break
            }
            responder = r.next
        }

        closeExtension()
    }

    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}
