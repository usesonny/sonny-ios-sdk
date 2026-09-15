import UIKit
import UserNotifications
import Sonny

@main final class AppDelegate: UIResponder, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        let settings = UserDefaults.standard
        if let site = settings.string(forKey: "siteId"), let app = settings.string(forKey: "appKey") {
            try? Sonny.configure(siteId: site, appKey: app, origin: settings.string(forKey: "origin") ?? "https://www.usesonny.com")
        }
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        do { try Sonny.registerPushToken(deviceToken) }
        catch { NotificationCenter.default.post(name: .samplePushStatus, object: "Push registration failed") }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        NotificationCenter.default.post(name: .samplePushStatus, object: "APNs registration failed. Check signing and Push Notifications capability.")
    }

    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse, withCompletionHandler completionHandler: @escaping () -> Void) {
        Task { @MainActor in
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let controller = scene.windows.first(where: \.isKeyWindow)?.rootViewController {
                Sonny.handlePush(response.notification.request.content.userInfo, from: controller)
            }
            completionHandler()
        }
    }
}

final class SceneDelegate: UIResponder, UIWindowSceneDelegate {
    var window: UIWindow?
    func scene(_ scene: UIScene, willConnectTo session: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        guard let scene = scene as? UIWindowScene else { return }
        let window = UIWindow(windowScene: scene)
        let controller = SampleViewController()
        window.rootViewController = controller
        self.window = window
        window.makeKeyAndVisible()
        if let response = connectionOptions.notificationResponse {
            Sonny.handlePush(response.notification.request.content.userInfo, from: controller)
        }
    }
}

extension Notification.Name { static let samplePushStatus = Notification.Name("samplePushStatus") }
