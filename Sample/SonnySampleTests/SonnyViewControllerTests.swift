#if canImport(UIKit)
import XCTest
import UIKit
@testable import Sonny

final class SonnyViewControllerTests: XCTestCase {
    @MainActor func testTemporaryFullScreenPresentationDoesNotCloseChat() async throws {
        if Sonny.host == nil { try Sonny.configure(siteId: "native-lifecycle-tests", appKey: "ios-lifecycle-tests") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let root = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow)?.rootViewController)
        let chat = SonnyViewController()
        chat.modalPresentationStyle = .fullScreen
        await present(chat, from: root)
        let overlay = UIViewController()
        overlay.modalPresentationStyle = .fullScreen
        await present(overlay, from: chat)
        XCTAssertTrue(Sonny.host?.activeController === chat)
        XCTAssertTrue(Sonny.host?.webView.superview === chat.view)
        await withCheckedContinuation { continuation in overlay.dismiss(animated: false) { continuation.resume() } }
        await withCheckedContinuation { continuation in chat.dismiss(animated: false) { continuation.resume() } }
    }

    @MainActor func testPresentingFullScreenPickerKeepsChatMounted() async throws {
        if Sonny.host == nil { try Sonny.configure(siteId: "native-lifecycle-tests", appKey: "ios-lifecycle-tests") }
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes.first as? UIWindowScene)
        let root = try XCTUnwrap(scene.windows.first(where: \.isKeyWindow)?.rootViewController)
        let chat = SonnyViewController()
        chat.modalPresentationStyle = .fullScreen
        await present(chat, from: root)
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.data])
        picker.modalPresentationStyle = .fullScreen
        await present(picker, from: chat)
        XCTAssertTrue(Sonny.host?.activeController === chat)
        XCTAssertTrue(Sonny.host?.webView.superview === chat.view)
        await withCheckedContinuation { continuation in picker.dismiss(animated: false) { continuation.resume() } }
        XCTAssertTrue(Sonny.host?.webView.superview === chat.view)
        await withCheckedContinuation { continuation in chat.dismiss(animated: false) { continuation.resume() } }
        XCTAssertNil(Sonny.host?.activeController)
        XCTAssertNil(Sonny.host?.webView.superview)
    }

    @MainActor private func present(_ controller: UIViewController, from parent: UIViewController) async {
        await withCheckedContinuation { continuation in
            parent.present(controller, animated: false) { continuation.resume() }
        }
    }
}
#endif
