import Foundation
#if canImport(UIKit)
import UIKit
import Combine
#endif

/// Visitor support chat. Configure once on the main actor before using the SDK.
@MainActor public enum Sonny {
    nonisolated public static let version = "1.0.0"

    #if canImport(UIKit)
    static var host: SonnyWebViewHost?
    private static weak var modal: SonnyViewController?
    private static var listeners: [UUID: (SonnyEvent) -> Void] = [:]
    private static var watcher: Timer?
    private static var watcherId: UUID?

    public static var unreadCount: Int { host?.client.unreadCount ?? 0 }

    public static func configure(siteId: String, appKey: String, origin: String = "https://www.usesonny.com") throws {
        let configuration = try SonnyConfiguration(siteId: siteId, appKey: appKey, origin: origin)
        if host?.configuration == configuration { return }
        guard host == nil else { throw SonnyError.alreadyConfigured }
        host = try SonnyWebViewHost(configuration: configuration, onEvent: emit)
    }

    public static func identify(jwt: String) throws { try configured().client.identify(jwt: jwt) }
    public static func identify(email: String, name: String? = nil, attributes: [String: Any] = [:]) throws {
        try configured().client.identify(email: email, name: name, attributes: attributes)
    }
    public static func setAttributes(_ attributes: [String: Any]) throws { try configured().client.setAttributes(attributes) }
    public static func registerPushToken(_ token: Data) throws {
        try configured().client.registerPushToken(token.map { String(format: "%02x", $0) }.joined())
    }

    public static func present(from controller: UIViewController) {
        configured().client.setOpen(true)
        guard modal?.presentingViewController == nil else { return }
        let chat = SonnyViewController()
        chat.modalPresentationStyle = .fullScreen
        modal = chat
        controller.present(chat, animated: true)
    }
    public static func dismiss() { configured().client.setOpen(false) }
    public static func reset() throws {
        watcher?.invalidate()
        watcher = nil
        watcherId = nil
        try configured().client.reset()
    }

    /// Call on a notification tap. Notification permission and presentation belong to your app.
    @discardableResult public static func handlePush(_ userInfo: [AnyHashable: Any], from controller: UIViewController) -> Bool {
        var payload: [String: String] = [:]
        for (key, value) in userInfo { if let key = key as? String, let value = value as? String { payload[key] = value } }
        guard host?.client.handlePush(payload) == true else { return false }
        present(from: controller)
        return true
    }

    public static func addListener(_ listener: @escaping (SonnyEvent) -> Void) -> AnyCancellable {
        let id = UUID()
        listeners[id] = listener
        listener(SonnyEvent(name: "unread", data: ["count": unreadCount]))
        return AnyCancellable { Task { @MainActor in listeners.removeValue(forKey: id) } }
    }

    public static func watchAttributes(interval: TimeInterval = 1, getter: @escaping () -> [String: Any]) -> AnyCancellable {
        precondition(interval >= 0.25, "Attribute interval must be at least 250ms")
        watcher?.invalidate()
        let id = UUID()
        watcherId = id
        @MainActor func update() {
            guard watcherId == id else { return }
            do { try setAttributes(getter()) }
            catch { emit(SonnyEvent(name: "error", data: ["code": "attributes_failed"])) }
        }
        watcher = Timer.scheduledTimer(withTimeInterval: interval, repeats: true) { _ in Task { @MainActor in update() } }
        update()
        return AnyCancellable { Task { @MainActor in
            if watcherId == id { watcher?.invalidate(); watcher = nil; watcherId = nil }
        } }
    }

    private static func configured() -> SonnyWebViewHost {
        guard let host else { preconditionFailure("Call Sonny.configure first") }
        return host
    }
    private static func emit(_ event: SonnyEvent) {
        if event.name == "close" {
            if let modal, modal.presentingViewController != nil, !modal.isBeingDismissed { modal.dismiss(animated: true) }
            modal = nil
        }
        Array(listeners.values).forEach { $0(event) }
    }
    #endif
}
