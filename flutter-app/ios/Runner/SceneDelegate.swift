import Flutter
import UIKit

/// Adozione del lifecycle UIScene, obbligatoria da iOS 27: senza `UIApplicationSceneManifest`
/// e senza uno `UISceneDelegate` l'app non viene avviata dal sistema.
///
/// Gli eventi che prima arrivavano all'`AppDelegate` (URL aperti, user activity, passaggio
/// in foreground) ora vengono consegnati alla scena. Qui li riceviamo e li inoltriamo
/// all'`AppDelegate`, che resta l'unico proprietario della logica di condivisione.
class SceneDelegate: FlutterSceneDelegate {

    private var appDelegate: AppDelegate? {
        UIApplication.shared.delegate as? AppDelegate
    }

    override func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        // Niente storyboard: la finestra mostra l'engine creato dall'AppDelegate
        // all'avvio, che quindi esiste anche quando iOS sveglia l'app in
        // background (push VoIP) senza collegare nessuna scena.
        if let windowScene = scene as? UIWindowScene, let engine = appDelegate?.flutterEngine {
            let window = UIWindow(windowScene: windowScene)
            window.rootViewController = FlutterViewController(engine: engine, nibName: nil, bundle: nil)
            self.window = window
            window.makeKeyAndVisible()
        }

        super.scene(scene, willConnectTo: session, options: connectionOptions)

        // App lanciata da zero tramite URL: è il caso della Share Extension che
        // apre l'app con lo scheme ShareMedia quando non è già in memoria.
        handle(urlContexts: connectionOptions.urlContexts)

        for activity in connectionOptions.userActivities {
            _ = appDelegate?.handleUserActivity(activity)
        }
    }

    override func scene(_ scene: UIScene, openURLContexts URLContexts: Set<UIOpenURLContext>) {
        super.scene(scene, openURLContexts: URLContexts)
        handle(urlContexts: URLContexts)
    }

    override func scene(_ scene: UIScene, continue userActivity: NSUserActivity) {
        super.scene(scene, continue: userActivity)
        _ = appDelegate?.handleUserActivity(userActivity)
    }

    override func sceneDidBecomeActive(_ scene: UIScene) {
        super.sceneDidBecomeActive(scene)

        // Rete di sicurezza: se l'estensione non è riuscita ad aprire l'app,
        // la coda viene svuotata al primo passaggio in foreground.
        appDelegate?.drainSharedQueue()
    }

    private func handle(urlContexts: Set<UIOpenURLContext>) {
        guard let appDelegate = appDelegate else { return }
        for context in urlContexts {
            _ = appDelegate.handleIncomingURL(context.url)
        }
    }
}
