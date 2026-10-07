import AppIntents
import Foundation

/// Cornetta del widget piccolo (iOS 17+): nel formato piccolo un tasto
/// separato è possibile solo con un AppIntent.
///
/// Apre l'app e lascia nell'App Group la richiesta di chiamata; l'app la
/// ritira all'attivazione (AppDelegate.takePendingWidgetAction) e Flutter
/// avvia la chiamata. Funziona sia che `perform` giri nell'estensione sia
/// nell'app.
@available(iOSApplicationExtension 17.0, *)
struct CallPartnerIntent: AppIntent {
    static let title: LocalizedStringResource = "Call"
    static let openAppWhenRun: Bool = true

    func perform() async throws -> some IntentResult {
        UserDefaults(suiteName: tuyjoAppGroupId)?
            .set(Date().timeIntervalSince1970, forKey: "tuyjo_pending_call")
        return .result()
    }
}
