import UIKit
import Social
import UniformTypeIdentifiers

class ShareViewController: UIViewController {
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
            if attachment.hasItemConformingToTypeIdentifier(UTType.url.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.url.identifier, options: nil) { (item, error) in
                    if let url = item as? URL {
                        self.openMainApp(with: url.absoluteString)
                    }
                }
                return
            } else if attachment.hasItemConformingToTypeIdentifier(UTType.plainText.identifier) {
                attachment.loadItem(forTypeIdentifier: UTType.plainText.identifier, options: nil) { (item, error) in
                    if let text = item as? String {
                        self.openMainApp(with: text)
                    }
                }
                return
            }
        }
        
        closeExtension()
    }
    
    private func openMainApp(with text: String) {
        let urlScheme = "ShareMedia://shared?text=\(text.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")"
        
        if let url = URL(string: urlScheme) {
            var responder: UIResponder? = self as UIResponder
            let selector = #selector(openURL(_:))
            
            while responder != nil {
                if responder!.responds(to: selector) && responder != self {
                    responder!.perform(selector, with: url, afterDelay: 0)
                    break
                }
                responder = responder?.next
            }
        }
        
        closeExtension()
    }
    
    @objc private func openURL(_ url: URL) {
        // Questo viene chiamato dal responder chain
    }
    
    private func closeExtension() {
        extensionContext?.completeRequest(returningItems: nil, completionHandler: nil)
    }
}

