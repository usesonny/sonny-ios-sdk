import Foundation

public struct SonnyEvent {
    public let name: String
    public let data: [String: Any]
}

@MainActor final class SonnyClient {
    let configuration: SonnyConfiguration
    private let namespace: String
    private let write: (String, String?) throws -> Void
    private let send: ([String: Any]) -> Void
    private var ready = false
    private var bridgeLoaded = false
    private var pending: [[String: Any]] = []
    private var identity: [String: Any]?
    private var attributes: [String: Any] = [:]
    private var pushToken: String?
    private var pushGeneration: Int
    private var pushUnregistrations: [[String: Any]] = []
    private var foreground = true
    private var open = false
    private(set) var visitorId: String
    private(set) var unreadCount = 0
    var onEvent: ((SonnyEvent) -> Void)?

    init(configuration: SonnyConfiguration, read: (String) throws -> String?,
         write: @escaping (String, String?) throws -> Void, send: @escaping ([String: Any]) -> Void) throws {
        self.configuration = configuration
        self.namespace = "\(configuration.siteId):\(configuration.appKey):"
        self.write = write
        self.send = send
        self.pushToken = try read(namespace + "push")
        self.pushGeneration = Int(try read(namespace + "push-generation") ?? "") ?? Int(Date().timeIntervalSince1970 * 1000)
        try write(namespace + "push-generation", String(pushGeneration))
        if let saved = try read(namespace + "push-unregistrations"), let data = saved.data(using: .utf8) {
            pushUnregistrations = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] ?? []
        }
        if let visitor = try read(namespace + "visitor") { visitorId = visitor }
        else {
            visitorId = UUID().uuidString.lowercased()
            try write(namespace + "visitor", visitorId)
        }
    }

    func identify(jwt: String) throws {
        guard !jwt.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw SonnyError.invalidIdentity }
        identity = ["userJwt": jwt]
        command("identify", data: identity!)
    }

    func identify(email: String, name: String?, attributes: [String: Any]) throws {
        guard email.contains("@") else { throw SonnyError.invalidIdentity }
        guard JSONSerialization.isValidJSONObject(attributes) else { throw SonnyError.invalidAttributes }
        identity = ["email": email, "attributes": attributes]
        identity?["name"] = name
        command("identify", data: identity!)
    }

    func setAttributes(_ values: [String: Any]) throws {
        guard JSONSerialization.isValidJSONObject(values) else { throw SonnyError.invalidAttributes }
        attributes.merge(values) { _, next in next }
        command("setAttributes", data: attributes)
    }

    func registerPushToken(_ token: String) throws {
        guard !token.isEmpty else { throw SonnyError.emptyPushToken }
        if let pushToken, pushToken != token {
            try advancePushGeneration()
            queuePushUnregistrations()
        }
        try write(namespace + "push", token)
        pushToken = token
        command("registerPushToken", data: ["token": token, "platform": "ios", "generation": pushGeneration])
    }

    func pageLoading() { ready = false; bridgeLoaded = false }
    func setForeground(_ active: Bool) {
        foreground = active
        command("setForeground", data: ["active": active])
        if active { queuePushUnregistrations() }
    }
    func setOpen(_ value: Bool) {
        updateOpen(value)
        command(value ? "open" : "close")
    }
    private func updateOpen(_ value: Bool) {
        guard open != value else { return }
        open = value
        onEvent?(SonnyEvent(name: value ? "open" : "close", data: [:]))
    }

    func reset() throws {
        let visitor = UUID().uuidString.lowercased()
        try advancePushGeneration()
        try write(namespace + "push", nil)
        try write(namespace + "visitor", visitor)
        pending.removeAll()
        identity = nil
        attributes.removeAll()
        pushToken = nil
        visitorId = visitor
        updateUnread(0)
        updateOpen(false)
        command("reset", data: ["visitorId": visitorId, "pushUnregistrations": pushUnregistrations], immediate: true)
    }

    private func advancePushGeneration() throws {
        let nextGeneration = max(pushGeneration + 1, Int(Date().timeIntervalSince1970 * 1000))
        if let pushToken {
            let removals = pushUnregistrations + [["id": UUID().uuidString.lowercased(), "visitorId": visitorId,
                "token": pushToken, "platform": "ios", "generation": nextGeneration]]
            try persistPushUnregistrations(removals)
            pushUnregistrations = removals
        }
        try write(namespace + "push-generation", String(nextGeneration))
        pushGeneration = nextGeneration
    }

    private func queuePushUnregistrations() {
        let messages: [[String: Any]] = pushUnregistrations.filter { removal in
            !pending.contains { $0["command"] as? String == "unregisterPushToken" && ($0["data"] as? [String: Any])?["id"] as? String == removal["id"] as? String }
        }.map { ["version": 1, "command": "unregisterPushToken", "data": $0] }
        if ready { messages.forEach(send) } else { pending.insert(contentsOf: messages, at: 0) }
    }

    private func persistPushUnregistrations(_ removals: [[String: Any]]) throws {
        let value = removals.isEmpty ? nil : String(data: try JSONSerialization.data(withJSONObject: removals), encoding: .utf8)
        try write(namespace + "push-unregistrations", value)
    }

    func handlePush(_ payload: [String: String]) -> Bool {
        guard payload["sonny"] == "visitor", payload["siteId"] == configuration.siteId,
              payload["appKey"] == configuration.appKey, payload["visitorId"] == visitorId,
              let conversation = payload["conversationId"], !conversation.isEmpty else { return false }
        command("openConversation", data: ["conversationId": conversation])
        return true
    }

    private func updateUnread(_ count: Int) {
        guard unreadCount != count else { return }
        unreadCount = count
        onEvent?(SonnyEvent(name: "unread", data: ["count": count]))
    }

    private func command(_ name: String, data: [String: Any] = [:], immediate: Bool = false) {
        let message: [String: Any] = ["version": 1, "command": name, "data": data]
        if ready || (immediate && bridgeLoaded) { send(message) } else { pending.append(message) }
    }

    func receive(_ event: [String: Any]) {
        guard event["version"] as? Int == 1, let name = event["event"] as? String else { return }
        let data = event["data"] as? [String: Any] ?? [:]
        switch name {
        case "pushUnregistered":
            guard let id = data["id"] as? String else { return }
            let remaining = pushUnregistrations.filter { $0["id"] as? String != id }
            do { try persistPushUnregistrations(remaining); pushUnregistrations = remaining }
            catch { onEvent?(SonnyEvent(name: "error", data: ["code": "push_storage_failed"])) }
            return
        case "open", "close": updateOpen(name == "open"); return
        case "unread": updateUnread(max(0, data["count"] as? Int ?? 0)); return
        case "ready":
            bridgeLoaded = true
            ready = false
            if !pending.contains(where: { $0["command"] as? String == "reset" }) {
                queuePushUnregistrations()
            }
            if let identity, !pending.contains(where: { $0["command"] as? String == "identify" }) {
                pending.insert(["version": 1, "command": "identify", "data": identity], at: 0)
            }
            if !attributes.isEmpty && !pending.contains(where: { $0["command"] as? String == "setAttributes" }) {
                command("setAttributes", data: attributes)
            }
            if let pushToken, !pending.contains(where: { $0["command"] as? String == "registerPushToken" }) {
                command("registerPushToken", data: ["token": pushToken, "platform": "ios", "generation": pushGeneration])
            }
            send(["version": 1, "id": "initialize", "command": "init", "data": ["visitorId": visitorId, "active": foreground, "open": open]])
        case "result" where event["id"] as? String == "initialize":
            ready = true
            let queued = pending
            pending.removeAll()
            queued.forEach(send)
        default: break
        }
        onEvent?(SonnyEvent(name: name, data: data))
    }
}
