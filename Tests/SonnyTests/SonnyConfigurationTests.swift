import XCTest
@testable import Sonny

final class SonnyConfigurationTests: XCTestCase {
    func testEmbedURLIncludesOnlyPublicConfigurationAndSDKVersion() throws {
        let config = try SonnyConfiguration(siteId: "site-a", appKey: "key-a")
        let url = try XCTUnwrap(URLComponents(url: config.embedURL, resolvingAgainstBaseURL: false))
        XCTAssertEqual(url.host, "www.usesonny.com")
        XCTAssertEqual(url.path, "/embed/widget")
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: url.queryItems!.map { ($0.name, $0.value!) }),
            ["siteId": "site-a", "appKey": "key-a", "sdk": "ios/1.0.0"])
        XCTAssertTrue(config.acceptsBridgeMessage(origin: "https://www.usesonny.com", isMainFrame: true))
        XCTAssertFalse(config.acceptsBridgeMessage(origin: "https://www.usesonny.com.evil.test", isMainFrame: true))
        XCTAssertFalse(config.acceptsBridgeMessage(origin: "https://www.usesonny.com", isMainFrame: false))
    }

    func testRejectsInsecureOriginsAndInjectedIdentifiers() {
        for origin in ["http://example.test", "https://example.test/path", "https://user@example.test", "https://example.test?x=1", "https://example.test#fragment"] {
            XCTAssertThrowsError(try SonnyConfiguration(siteId: "site-a", appKey: "key-a", origin: origin))
        }
        XCTAssertThrowsError(try SonnyConfiguration(siteId: "bad&site", appKey: "key-a"))
    }
}
