import Foundation
import UserNotifications
import WidgetKit

/// Aggiorna il numero dei messaggi non letti del widget quando arriva un push
/// con l'app chiusa (su iOS nessun altro codice dell'app gira in quel momento).
///
/// Non decifra nulla e non tocca la notifica: legge il conteggio che il server
/// già calcola per il badge (`unread_count` nei dati, o `aps.badge`), lo salva
/// nell'App Group e chiede a WidgetKit di ridisegnare il widget.
/// Il server deve mandare `mutable-content: 1` perché questa estensione parta.
class NotificationService: UNNotificationServiceExtension {

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        let userInfo = request.content.userInfo
        var count: Int?
        if let raw = userInfo["unread_count"] as? String {
            count = Int(raw)
        } else if let value = userInfo["unread_count"] as? Int {
            count = value
        } else if let badge = request.content.badge?.intValue {
            count = badge
        }

        if let count = count {
            UserDefaults(suiteName: "group.com.privatemessaging.tuyjo")?
                .set(String(count), forKey: "tuyjo_unread")
            WidgetCenter.shared.reloadAllTimelines()
        }

        contentHandler(request.content)
    }

    override func serviceExtensionTimeWillExpire() {
        // Niente da salvare: la notifica originale viene mostrata così com'è.
    }
}
