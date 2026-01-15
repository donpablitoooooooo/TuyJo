import UIKit
import Social
import MobileCoreServices
import Photos

class ShareViewController: SLComposeServiceViewController {

    // App Group deve corrispondere a quello in Runner.entitlements
    let sharedKey = "ShareKey"
    var sharedMedia: [SharedMediaFile] = []

    override func isContentValid() -> Bool {
        return true
    }

    override func viewDidLoad() {
        super.viewDidLoad()
    }

    override func didSelectPost() {
        print("ShareExtension: didSelectPost called")

        if let content = extensionContext!.inputItems[0] as? NSExtensionItem {
            if let contents = content.attachments {
                for (index, attachment) in (contents).enumerated() {
                    if attachment.hasItemConformingToTypeIdentifier(kUTTypeURL as String) {
                        handleUrl(content: content, attachment: attachment, index: index)
                    } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeImage as String) {
                        handleImages(content: content, attachment: attachment, index: index)
                    } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeMovie as String) {
                        handleVideos(content: content, attachment: attachment, index: index)
                    } else if attachment.hasItemConformingToTypeIdentifier(kUTTypeFileURL as String) {
                        handleFiles(content: content, attachment: attachment, index: index)
                    }
                }
            }
        }
    }

    override func configurationItems() -> [Any]! {
        return []
    }

    private func handleUrl (content: NSExtensionItem, attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeURL as String, options: nil) { [weak self] data, error in
            if error == nil, let item = data as? URL, let this = self {
                this.sharedMedia.append(SharedMediaFile(path: item.absoluteString, thumbnail: nil, duration: nil, type: .url))

                if index == (content.attachments?.count)! - 1 {
                    this.redirectToHostApp(type: .url)
                }
            } else {
                self?.dismissWithError()
            }
        }
    }

    private func handleImages (content: NSExtensionItem, attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeImage as String, options: nil) { [weak self] data, error in
            if error == nil, let this = self {
                var imageData: Data? = nil
                var fileName: String? = nil

                if let url = data as? URL {
                    do {
                        imageData = try Data(contentsOf: url)
                        fileName = this.getFileName(from: url, type: .image)
                    } catch {
                        print("ShareExtension: error loading image data: \(error)")
                    }
                } else if let image = data as? UIImage {
                    imageData = image.pngData()
                    fileName = UUID().uuidString + ".png"
                }

                if let imageData = imageData, let fileName = fileName {
                    let newPath = this.getNewFilePath(fileName: fileName)
                    do {
                        try imageData.write(to: URL(fileURLWithPath: newPath), options: .atomic)
                        this.sharedMedia.append(SharedMediaFile(path: newPath, thumbnail: nil, duration: nil, type: .image))
                    } catch {
                        print("ShareExtension: error writing image: \(error)")
                    }
                }

                if index == (content.attachments?.count)! - 1 {
                    this.redirectToHostApp(type: .image)
                }
            } else {
                self?.dismissWithError()
            }
        }
    }

    private func handleVideos (content: NSExtensionItem, attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeMovie as String, options: nil) { [weak self] data, error in
            if error == nil, let url = data as? URL, let this = self {
                let fileName = this.getFileName(from: url, type: .video)
                let newPath = this.getNewFilePath(fileName: fileName)

                do {
                    let videoData = try Data(contentsOf: url)
                    try videoData.write(to: URL(fileURLWithPath: newPath), options: .atomic)
                    this.sharedMedia.append(SharedMediaFile(path: newPath, thumbnail: nil, duration: nil, type: .video))
                } catch {
                    print("ShareExtension: error handling video: \(error)")
                }

                if index == (content.attachments?.count)! - 1 {
                    this.redirectToHostApp(type: .video)
                }
            } else {
                self?.dismissWithError()
            }
        }
    }

    private func handleFiles (content: NSExtensionItem, attachment: NSItemProvider, index: Int) {
        attachment.loadItem(forTypeIdentifier: kUTTypeFileURL as String, options: nil) { [weak self] data, error in
            if error == nil, let url = data as? URL, let this = self {
                let fileName = this.getFileName(from: url, type: .file)
                let newPath = this.getNewFilePath(fileName: fileName)

                do {
                    let fileData = try Data(contentsOf: url)
                    try fileData.write(to: URL(fileURLWithPath: newPath), options: .atomic)
                    this.sharedMedia.append(SharedMediaFile(path: newPath, thumbnail: nil, duration: nil, type: .file))
                } catch {
                    print("ShareExtension: error handling file: \(error)")
                }

                if index == (content.attachments?.count)! - 1 {
                    this.redirectToHostApp(type: .file)
                }
            } else {
                self?.dismissWithError()
            }
        }
    }

    private func dismissWithError() {
        print("ShareExtension: dismissing with error")
        let alert = UIAlertController(title: "Error", message: "Error loading data", preferredStyle: .alert)
        let action = UIAlertAction(title: "Error", style: .cancel) { _ in
            self.dismiss(animated: true, completion: nil)
        }
        alert.addAction(action)
        present(alert, animated: true, completion: nil)
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    private func redirectToHostApp(type: SharedMediaType) {
        let url = URL(string: "ShareMedia://dataUrl=\(sharedKey)")
        var responder = self as UIResponder?
        let selectorOpenURL = sel_registerName("openURL:")

        while (responder != nil) {
            if (responder?.responds(to: selectorOpenURL))! {
                let _ = responder?.perform(selectorOpenURL, with: url)
            }
            responder = responder!.next
        }
        extensionContext!.completeRequest(returningItems: [], completionHandler: nil)
    }

    enum SharedMediaType: Int, Codable {
        case image
        case video
        case file
        case url
    }

    func getFileName(from url: URL, type: SharedMediaType) -> String {
        var name = url.lastPathComponent

        if name.isEmpty {
            name = UUID().uuidString + "." + getExtension(from: type)
        }

        return name
    }

    func getExtension(from type: SharedMediaType) -> String {
        switch type {
        case .image:
            return "png"
        case .video:
            return "mp4"
        case .file:
            return "dat"
        case .url:
            return "txt"
        }
    }

    func getNewFilePath(fileName: String) -> String {
        let path = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: "group.com.privatemessaging.tuyjo")!
            .appendingPathComponent(fileName)
            .path

        if FileManager.default.fileExists(atPath: path) {
            do {
                try FileManager.default.removeItem(atPath: path)
            } catch {
                print("ShareExtension: error removing existing file: \(error)")
            }
        }

        return path
    }

    class SharedMediaFile: Codable {
        var path: String
        var thumbnail: String?
        var duration: Double?
        var type: SharedMediaType

        init(path: String, thumbnail: String?, duration: Double?, type: SharedMediaType) {
            self.path = path
            self.thumbnail = thumbnail
            self.duration = duration
            self.type = type
        }
    }
}
