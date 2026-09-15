#if canImport(UIKit)
import UIKit

/// Embed as a child view controller, or present with Sonny.present(from:).
@MainActor public final class SonnyViewController: UIViewController {
    private let host: SonnyWebViewHost

    public init() {
        guard let host = Sonny.host else { preconditionFailure("Call Sonny.configure first") }
        self.host = host
        super.init(nibName: nil, bundle: nil)
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("Use init()") }
    public override var preferredStatusBarStyle: UIStatusBarStyle { .darkContent }

    public override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .white
    }

    public override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        host.webView.removeFromSuperview()
        host.activeController = self
        let chat = host.webView
        chat.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(chat)
        NSLayoutConstraint.activate([
            chat.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            chat.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            chat.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            chat.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor)
        ])
        host.client.setOpen(true)
    }

    public override func viewDidDisappear(_ animated: Bool) {
        super.viewDidDisappear(animated)
        guard host.activeController === self else { return }
        // A full-screen picker can cover chat without removing its session.
        guard presentedViewController == nil || isBeingDismissed else { return }
        host.client.setOpen(false)
        host.webView.removeFromSuperview()
        host.activeController = nil
    }
}
#endif
