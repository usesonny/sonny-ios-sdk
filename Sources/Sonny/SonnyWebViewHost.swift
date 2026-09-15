#if canImport(UIKit)
import UIKit
import WebKit

@MainActor final class SonnyWebViewHost: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let configuration: SonnyConfiguration
    let webView: WKWebView
    private(set) var client: SonnyClient!
    weak var activeController: SonnyViewController?
    private let onEvent: (SonnyEvent) -> Void

    init(configuration: SonnyConfiguration, onEvent: @escaping (SonnyEvent) -> Void) throws {
        self.configuration = configuration
        self.onEvent = onEvent
        let webConfiguration = WKWebViewConfiguration()
        webConfiguration.websiteDataStore = .nonPersistent()
        webConfiguration.applicationNameForUserAgent = "SonnySDK/ios/\(Sonny.version)"
        self.webView = WKWebView(frame: .zero, configuration: webConfiguration)
        super.init()
        let keychain = SonnyKeychain()
        client = try SonnyClient(configuration: configuration, read: keychain.read, write: keychain.write) { [weak self] message in
            self?.webView.callAsyncJavaScript("window.SonnyBridge.receive(message)", arguments: ["message": message], in: nil, in: .page) { _ in }
        }
        client.onEvent = { [weak self] event in
            if event.name == "openExternal", let value = event.data["url"] as? String, let url = URL(string: value) { self?.openExternal(url) }
            self?.onEvent(event)
        }
        client.setForeground(UIApplication.shared.applicationState == .active)
        webView.configuration.userContentController.add(self, name: "SonnyBridge")
        webView.navigationDelegate = self
        webView.uiDelegate = self
        webView.scrollView.contentInsetAdjustmentBehavior = .never
        webView.scrollView.bounces = false
        #if DEBUG
        if #available(iOS 16.4, *) { webView.isInspectable = true }
        #endif
        NotificationCenter.default.addObserver(self, selector: #selector(becameActive), name: UIApplication.didBecomeActiveNotification, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(enteredBackground), name: UIApplication.didEnterBackgroundNotification, object: nil)
        load()
    }

    private func load() {
        var request = URLRequest(url: configuration.embedURL)
        request.setValue("ios/\(Sonny.version)", forHTTPHeaderField: "x-sonny-sdk")
        webView.load(request)
    }
    @objc private func becameActive() { client.setForeground(true) }
    @objc private func enteredBackground() { client.setForeground(false) }

    func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
        let securityOrigin = message.frameInfo.securityOrigin
        let port = securityOrigin.port == 0 || securityOrigin.port == 443 ? "" : ":\(securityOrigin.port)"
        let origin = "\(securityOrigin.protocol)://\(securityOrigin.host)\(port)"
        guard configuration.acceptsBridgeMessage(origin: origin, isMainFrame: message.frameInfo.isMainFrame),
              let event = message.body as? [String: Any] else { return }
        client.receive(event)
    }

    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) { client.pageLoading() }

    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        guard navigationAction.targetFrame?.isMainFrame != false, let url = navigationAction.request.url else { decisionHandler(.allow); return }
        if url == configuration.embedURL || url.absoluteString == "about:blank" { decisionHandler(.allow) }
        else { decisionHandler(.cancel); openExternal(url) }
    }

    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        if navigationResponse.isForMainFrame, let response = navigationResponse.response as? HTTPURLResponse, response.statusCode >= 400 {
            decisionHandler(.cancel)
            showOffline()
        } else { decisionHandler(.allow) }
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showOffline() }
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        if (error as NSError).code != NSURLErrorCancelled { showOffline() }
    }
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) { client.pageLoading(); load() }

    func webView(_ webView: WKWebView, createWebViewWith configuration: WKWebViewConfiguration, for navigationAction: WKNavigationAction, windowFeatures: WKWindowFeatures) -> WKWebView? {
        if let url = navigationAction.request.url { openExternal(url) }
        return nil
    }

    // WKWebView's built-in iOS file input flow supplies the native photo/document picker.
    private func openExternal(_ url: URL) {
        guard ["https", "http", "mailto", "tel"].contains(url.scheme ?? "") else { return }
        UIApplication.shared.open(url, options: [:]) { [weak self] success in
            if !success { self?.onEvent(SonnyEvent(name: "error", data: ["code": "no_link_handler"])) }
        }
    }

    private func showOffline() {
        let retry = configuration.embedURL.absoluteString.replacingOccurrences(of: "&", with: "&amp;")
        webView.loadHTMLString("""
        <!doctype html><html lang="en"><head><meta name="viewport" content="width=device-width,initial-scale=1">
        <style>body{font:17px system-ui;padding:24px;color:#172033;background:white}a{display:inline-block;padding:12px 18px;border-radius:12px;background:#2563eb;color:white;text-decoration:none}</style></head>
        <body><h1>Unable to connect</h1><p>Check your connection, then try opening support again.</p><a href="\(retry)">Try again</a></body></html>
        """, baseURL: nil)
    }
}
#endif
