import XCTest
@testable import Sonny

final class SonnyClientTests: XCTestCase {
    @MainActor func testTokenRotationRetiresOldTokenAndForegroundRetriesPendingRemovals() async throws {
        var sent: [[String: Any]] = []
        let client = try SonnyClient(configuration: SonnyConfiguration(siteId: "site-a", appKey: "key-a"),
            read: { _ in nil }, write: { _, _ in }, send: { sent.append($0) })
        client.receive(["version": 1, "event": "ready"])
        client.receive(["version": 1, "event": "result", "id": "initialize"])
        try client.registerPushToken("token-a")
        try client.registerPushToken("token-b")
        XCTAssertTrue(sent.contains { $0["command"] as? String == "unregisterPushToken" && ($0["data"] as? [String: Any])?["token"] as? String == "token-a" })
        try client.reset()
        sent.removeAll()
        client.setForeground(true)
        let removals = sent.filter { $0["command"] as? String == "unregisterPushToken" }.compactMap { ($0["data"] as? [String: Any])?["token"] as? String }
        XCTAssertEqual(Set(removals), Set(["token-a", "token-b"]))
    }

    @MainActor func testLogoutRetriesPushRemovalAcrossRelaunchUntilAcknowledged() async throws {
        var stored: [String: String] = [:]
        var sent: [[String: Any]] = []
        let configuration = try SonnyConfiguration(siteId: "site-a", appKey: "key-a")
        func makeClient() throws -> SonnyClient {
            try SonnyClient(configuration: configuration, read: { stored[$0] }, write: { stored[$0] = $1 }, send: { sent.append($0) })
        }
        func load(_ client: SonnyClient) {
            client.receive(["version": 1, "event": "ready"])
            client.receive(["version": 1, "event": "result", "id": "initialize"])
        }
        let first = try makeClient()
        load(first)
        let visitor = first.visitorId
        try first.registerPushToken("device-token")
        let generation = (sent.last?["data"] as? [String: Any])?["generation"] as? Int ?? -1
        try first.reset()
        sent.removeAll()
        let relaunched = try makeClient()
        load(relaunched)
        let removal = try XCTUnwrap(sent.first { $0["command"] as? String == "unregisterPushToken" }?["data"] as? [String: Any])
        XCTAssertEqual(removal["visitorId"] as? String, visitor)
        XCTAssertEqual(removal["token"] as? String, "device-token")
        XCTAssertGreaterThan(removal["generation"] as? Int ?? -1, generation)
        XCTAssertFalse(sent.contains { $0["command"] as? String == "registerPushToken" })
        relaunched.receive(["version": 1, "event": "pushUnregistered", "data": ["id": try XCTUnwrap(removal["id"] as? String)]])
        sent.removeAll()
        load(try makeClient())
        XCTAssertFalse(sent.contains { $0["command"] as? String == "unregisterPushToken" })
    }

    @MainActor func testReloadReplaysAllAttributesWhenAnUpdateArrivesDuringLoading() async throws {
        var sent: [[String: Any]] = []
        let client = try SonnyClient(configuration: SonnyConfiguration(siteId: "site-a", appKey: "key-a"),
            read: { _ in nil }, write: { _, _ in }, send: { sent.append($0) })
        func load() {
            client.receive(["version": 1, "event": "ready"])
            client.receive(["version": 1, "event": "result", "id": "initialize"])
        }
        load()
        try client.setAttributes(["plan": "pro", "locale": "en"])
        client.pageLoading()
        sent.removeAll()
        try client.setAttributes(["locale": "fr"])
        load()
        var restored: [String: String] = [:]
        for message in sent where message["command"] as? String == "setAttributes" {
            restored.merge(message["data"] as? [String: String] ?? [:]) { _, next in next }
        }
        XCTAssertEqual(restored, ["plan": "pro", "locale": "fr"])
    }

    @MainActor func testIdentityWaitsForInitializationAndRemainsInMemory() async throws {
        var stored: [String: String] = [:]
        var sent: [[String: Any]] = []
        let client = try SonnyClient(configuration: SonnyConfiguration(siteId: "site-a", appKey: "key-a"),
            read: { stored[$0] }, write: { stored[$0] = $1 }, send: { sent.append($0) })
        try client.identify(jwt: "signed.customer.jwt")
        XCTAssertTrue(sent.isEmpty)
        client.receive(["version": 1, "event": "ready"])
        XCTAssertEqual(sent.count, 1)
        XCTAssertEqual(sent[0]["command"] as? String, "init")
        client.receive(["version": 1, "event": "result", "id": "initialize"])
        XCTAssertEqual(sent.last?["command"] as? String, "identify")
        XCTAssertFalse(stored.values.contains("signed.customer.jwt"))
        sent.removeAll()
        client.pageLoading()
        client.receive(["version": 1, "event": "ready"])
        client.receive(["version": 1, "event": "result", "id": "initialize"])
        XCTAssertEqual((sent.last?["data"] as? [String: Any])?["userJwt"] as? String, "signed.customer.jwt")
    }

    @MainActor func testLogoutInterruptsInitializationAndIsolatesFuturePushTaps() async throws {
        var stored: [String: String] = [:]
        var sent: [[String: Any]] = []
        var events: [String] = []
        let config = try SonnyConfiguration(siteId: "site-a", appKey: "key-a")
        let client = try SonnyClient(configuration: config, read: { stored[$0] }, write: { stored[$0] = $1 }, send: { sent.append($0) })
        client.onEvent = { events.append($0.name) }
        client.setOpen(true)
        client.setForeground(false)
        let oldVisitor = client.visitorId
        let oldPush = ["sonny": "visitor", "siteId": "site-a", "appKey": "key-a", "visitorId": oldVisitor, "conversationId": "conversation-a"]
        client.receive(["version": 1, "event": "ready"])
        XCTAssertEqual((sent[0]["data"] as? [String: Any])?["active"] as? Bool, false)
        try client.identify(jwt: "old.jwt")
        try client.setAttributes(["plan": "pro"])
        try client.registerPushToken("device-token")
        try client.reset()
        XCTAssertNotEqual(client.visitorId, oldVisitor)
        XCTAssertEqual(sent.last?["command"] as? String, "reset")
        XCTAssertTrue(events.contains("close"))
        client.receive(["version": 1, "event": "result", "id": "initialize"])
        XCTAssertFalse(sent.contains { $0["command"] as? String == "identify" })
        XCTAssertFalse(sent.contains { $0["command"] as? String == "registerPushToken" })
        XCTAssertFalse(client.handlePush(oldPush))
        var push = oldPush
        push["visitorId"] = client.visitorId
        XCTAssertTrue(client.handlePush(push))
        XCTAssertEqual(sent.last?["command"] as? String, "openConversation")
        push["appKey"] = "another-app"
        XCTAssertFalse(client.handlePush(push))
        let relaunched = try SonnyClient(configuration: config, read: { stored[$0] }, write: { stored[$0] = $1 }, send: { _ in })
        XCTAssertEqual(relaunched.visitorId, client.visitorId)
    }
}
