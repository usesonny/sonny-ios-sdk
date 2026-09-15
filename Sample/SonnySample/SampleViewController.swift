import UIKit
import Combine
import UserNotifications
import Sonny

final class SampleViewController: UIViewController {
    private let stack = UIStackView()
    private let status = UILabel()
    private var subscription: AnyCancellable?
    private var embedded: SonnyViewController?
    private var configured = UserDefaults.standard.string(forKey: "appKey") != nil

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .systemBackground
        let scroll = UIScrollView()
        scroll.keyboardDismissMode = .interactive
        scroll.translatesAutoresizingMaskIntoConstraints = false
        view.addSubview(scroll)
        stack.axis = .vertical
        stack.spacing = 12
        stack.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: view.safeAreaLayoutGuide.trailingAnchor),
            scroll.topAnchor.constraint(equalTo: view.safeAreaLayoutGuide.topAnchor),
            scroll.bottomAnchor.constraint(equalTo: view.keyboardLayoutGuide.topAnchor),
            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 20),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -20),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor, constant: 20),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor, constant: -20),
            stack.widthAnchor.constraint(equalTo: scroll.frameLayoutGuide.widthAnchor, constant: -40)
        ])
        label("Sonny visitor SDK", font: .preferredFont(forTextStyle: .title1))
        label("Use an iOS app key from your widget settings. Identity tokens come from your backend.")
        let settings = UserDefaults.standard
        let origin = field("Sonny origin", value: settings.string(forKey: "origin") ?? "https://www.usesonny.com")
        let site = field("Site ID", value: settings.string(forKey: "siteId") ?? "")
        let app = field("App key", value: settings.string(forKey: "appKey") ?? "")
        action("Configure", requiresConfiguration: false) { [weak self] in
            try Sonny.configure(siteId: site.text ?? "", appKey: app.text ?? "", origin: origin.text ?? "")
            settings.set(site.text, forKey: "siteId")
            settings.set(app.text, forKey: "appKey")
            settings.set(origin.text, forKey: "origin")
            self?.configured = true
            self?.status.text = "Configured. You can chat anonymously."
        }
        let jwt = field("Identity JWT (preferred)", secure: true)
        let email = field("Email for legacy identity")
        let name = field("Name")
        action("Identify") {
            if let token = jwt.text, !token.isEmpty { try Sonny.identify(jwt: token) }
            else { try Sonny.identify(email: email.text ?? "", name: name.text) }
        }
        action("Set sample attributes") { try Sonny.setAttributes(["plan": "sample", "platform": "ios"]) }
        action("Open support") { [weak self] in
            guard let self else { return }
            self.view.endEditing(true)
            Sonny.present(from: self)
        }
        action("Toggle embedded chat") { [weak self] in self?.toggleEmbedded() }
        action("Enable push notifications") {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { allowed, _ in
                if allowed { Task { @MainActor in UIApplication.shared.registerForRemoteNotifications() } }
            }
        }
        action("Log out") {
            try Sonny.reset()
            jwt.text = ""
            email.text = ""
            name.text = ""
        }
        status.numberOfLines = 0
        status.accessibilityIdentifier = "sdk-status"
        stack.addArrangedSubview(status)
        subscription = Sonny.addListener { [weak self] event in
            switch event.name {
            case "unread": self?.status.text = "Unread: \(event.data["count"] as? Int ?? 0)"
            case "identityRequired": self?.status.text = "Your backend must supply a fresh identity JWT."
            case "error": self?.status.text = "SDK error: \(event.data["code"] as? String ?? "unknown")"
            default: break
            }
        }
        NotificationCenter.default.addObserver(self, selector: #selector(pushStatus), name: .samplePushStatus, object: nil)
    }

    @objc private func pushStatus(_ notification: Notification) { status.text = notification.object as? String }

    private func toggleEmbedded() {
        if let embedded {
            embedded.willMove(toParent: nil)
            embedded.view.removeFromSuperview()
            embedded.removeFromParent()
            self.embedded = nil
        } else {
            let chat = SonnyViewController()
            addChild(chat)
            stack.addArrangedSubview(chat.view)
            chat.view.heightAnchor.constraint(equalToConstant: 600).isActive = true
            chat.didMove(toParent: self)
            embedded = chat
        }
    }

    private func label(_ text: String, font: UIFont = .preferredFont(forTextStyle: .body)) {
        let label = UILabel()
        label.text = text
        label.font = font
        label.adjustsFontForContentSizeCategory = true
        label.numberOfLines = 0
        stack.addArrangedSubview(label)
    }

    private func field(_ title: String, value: String = "", secure: Bool = false) -> UITextField {
        let field = UITextField()
        field.borderStyle = .roundedRect
        field.placeholder = title
        field.accessibilityIdentifier = title
        field.accessibilityLabel = title
        field.text = value
        field.isSecureTextEntry = secure
        field.autocapitalizationType = .none
        field.autocorrectionType = .no
        field.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        stack.addArrangedSubview(field)
        return field
    }

    private func action(_ title: String, requiresConfiguration: Bool = true, handler: @escaping () throws -> Void) {
        let button = UIButton(type: .system)
        button.configuration = .tinted()
        button.setTitle(title, for: .normal)
        button.accessibilityIdentifier = title
        button.heightAnchor.constraint(greaterThanOrEqualToConstant: 44).isActive = true
        button.addAction(UIAction { [weak self] _ in
            guard let self else { return }
            guard !requiresConfiguration || self.configured else { self.status.text = "Configure the SDK first."; return }
            do { try handler() }
            catch { self.status.text = "Action failed: \(error.localizedDescription)" }
        }, for: .touchUpInside)
        stack.addArrangedSubview(button)
    }
}
