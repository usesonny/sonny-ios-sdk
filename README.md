# Sonny visitor SDK for iOS

Swift Package Manager library for iOS 15 and later. It hosts Sonny's existing
chat widget in `WKWebView`, with native presentation, file picking, Keychain
visitor persistence, and lifecycle handling. This is separate from Sonny's agent
inbox app.

**Preview:** the hosted mobile rollout and push delivery are still being completed.
Pin a reviewed Git commit while trying the SDK; an app key from a mobile-enabled
Sonny deployment is required. There is no stable tagged release yet.

## Install with Swift Package Manager

In Xcode, choose **File → Add Package Dependencies**, enter
`https://github.com/usesonny/sonny-ios-sdk`, and select the `main` branch or a
reviewed commit. Add the **Sonny** product to your app target.

For a Swift package, add:

```swift
.package(url: "https://github.com/usesonny/sonny-ios-sdk.git", branch: "main")
```

Then add `.product(name: "Sonny", package: "sonny-ios-sdk")` to your target's
dependencies. CocoaPods consumers can use the included `Sonny.podspec` with
`pod 'Sonny', :git => 'https://github.com/usesonny/sonny-ios-sdk.git', :branch => 'main'`.
The pod has not been published to CocoaPods trunk.

## Local development

Open `Sample/SonnySample.xcodeproj` and run the **SonnySample** scheme. The sample
references the package in this directory. Enter your Sonny origin, website site
ID, and an **iOS app key**. These are public configuration values; keep your
identity signing secret and APNs credentials on your server.
The sample bundle ID is `com.usesonny.sample.ios`.

```sh
swift test
xcodebuild -project Sample/SonnySample.xcodeproj -scheme SonnySample \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' test
```

Package tests cover configuration and session state. The sample's hosted tests
exercise UIKit presentation and the real iOS Keychain. The package's macOS tests
also exercise the Keychain; the standalone iOS package runner has no application
entitlements, so Keychain tests belong to the sample host on iOS.

App-scoped token registration, logout revocation and encrypted
customer credential setup are implemented; APNs delivery remains unfinished.

In the website's **Live Chat → Mobile apps** settings, create an iOS app with
your bundle ID and copy its configuration. Under **Set up push notifications**,
upload that app's APNs `.p8` key with its team ID and key ID. Use the sandbox
environment for development builds, or production for App Store/TestFlight.
The server stores these credentials encrypted; never bundle them in the sample.

## Configure and present

Call the SDK on the main actor. Configure once during app startup; repeated
identical configuration is harmless. Changing apps requires a fresh process.

```swift
import Sonny

try Sonny.configure(siteId: "your-site-id", appKey: "your-ios-app-key")
Sonny.present(from: viewController)
Sonny.dismiss()
```

For embedded chat, add `SonnyViewController()` as a child view controller and
constrain its view inside your layout. Follow UIKit's `addChild` / `didMove` and
`willMove` / `removeFromParent` lifecycle. Modal and embedded presentations share
one chat session and WebView. The controller handles safe areas and keyboard
clearance. Add camera/microphone usage descriptions to your app if you allow
captured photo/video attachments, as shown in the sample.

## Identity, attributes, and logout

Prefer a short-lived identity JWT from your backend. The SDK keeps it in memory
and emits `identityRequired` when the host needs to fetch a fresh token. Legacy
email identification remains available for websites that permit it.

```swift
try Sonny.identify(jwt: tokenFromYourBackend)
// Or: try Sonny.identify(email: "visitor@example.com", name: "Visitor")
try Sonny.setAttributes(["plan": "pro"])

// Retain the cancellable while observing.
let events = Sonny.addListener { event in
    if event.name == "unread" {
        updateUnreadBadge(Sonny.unreadCount)
    }
}
let attributes = Sonny.watchAttributes { ["screen": currentScreen] }

// At app logout: clear native identity, cached attributes, unread state, and chat.
try Sonny.reset()
events.cancel()
attributes.cancel()
```

`reset` rotates the Keychain visitor ID. Push taps containing the previous visitor
ID, another app key, or another website are rejected. Your app owns notification
permission, APNs registration, and foreground notification presentation. The
sample shows token forwarding via `registerPushToken` and notification-tap routing
via `handlePush`; real provider delivery remains part of the pending push work.
Unfinished token removals stay in Keychain and retry on foreground/relaunch. When
logout happens offline, server revocation completes after the SDK reconnects.

## Help and contributions

- [Documentation](https://www.usesonny.com/docs/widget-mobile)
- [Report a bug or request a feature](https://github.com/usesonny/sonny-ios-sdk/issues)
- [Android SDK](https://github.com/usesonny/sonny-android-sdk)
- [React Native SDK](https://github.com/usesonny/sonny-react-native-sdk)
- [Contributing](CONTRIBUTING.md) · [Security reports](SECURITY.md) · [MIT license](LICENSE)
