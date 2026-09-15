#if !os(iOS) || SONNY_HOSTED_TESTS
import XCTest
@testable import Sonny

final class SonnyKeychainTests: XCTestCase {
    func testVisitorPersistsAcrossStoreInstancesAndCanBeReplacedAtLogout() throws {
        let account = "test-\(UUID().uuidString):visitor"
        let store = SonnyKeychain()
        defer { try? store.write(account, nil) }
        try store.write(account, "first-visitor")
        XCTAssertEqual(try SonnyKeychain().read(account), "first-visitor")
        try store.write(account, "next-visitor")
        XCTAssertEqual(try SonnyKeychain().read(account), "next-visitor")
        try store.write(account, nil)
        XCTAssertNil(try SonnyKeychain().read(account))
    }
}
#endif
