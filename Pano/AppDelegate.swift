import UIKit

@main
final class AppDelegate: UIResponder, UIApplicationDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        AdBlocker.install()
        #if DEBUG
        installCrashLogger()
        #endif
        return true
    }

    func application(_ application: UIApplication,
                     configurationForConnecting connectingSceneSession: UISceneSession,
                     options: UIScene.ConnectionOptions) -> UISceneConfiguration {
        let config = UISceneConfiguration(name: "Default", sessionRole: connectingSceneSession.role)
        config.delegateClass = SceneDelegate.self
        return config
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?

    func scene(_ scene: UIScene, willConnectTo session: UISceneSession,
               options connectionOptions: UIScene.ConnectionOptions) {
        guard let windowScene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: windowScene)
        window.rootViewController = BrowserViewController()
        window.makeKeyAndVisible()
        self.window = window
    }
}


#if DEBUG
/// Simülatörde çökme raporu oluşmadığında nedeni görmek için: istisna / sinyal anındaki yığını Caches'e yazar.
private func installCrashLogger() {
    NSSetUncaughtExceptionHandler { exception in
        writeCrash("EXCEPTION \(exception.name.rawValue): \(exception.reason ?? "")\n" + exception.callStackSymbols.joined(separator: "\n"))
    }
    for sig in [SIGSEGV, SIGBUS, SIGILL, SIGABRT, SIGTRAP, SIGFPE] {
        signal(sig) { s in
            writeCrash("SIGNAL \(s)\n" + Thread.callStackSymbols.joined(separator: "\n"))
            signal(s, SIG_DFL)
            raise(s)
        }
    }
}

private func writeCrash(_ text: String) {
    let url = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("crash.txt")
    try? text.write(to: url, atomically: false, encoding: .utf8)
}
#endif
