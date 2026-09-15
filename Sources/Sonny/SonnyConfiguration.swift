import Foundation

public enum SonnyError: Error {
    case invalidConfiguration
    case alreadyConfigured
    case invalidIdentity
    case invalidAttributes
    case emptyPushToken
    case keychain(OSStatus)
}

public struct SonnyConfiguration: Equatable {
    public let siteId: String
    public let appKey: String
    public let origin: String

    public init(siteId: String, appKey: String, origin: String = "https://www.usesonny.com") throws {
        guard siteId.range(of: "^[\\w-]{1,128}$", options: .regularExpression) != nil,
              appKey.range(of: "^[\\w-]{1,128}$", options: .regularExpression) != nil,
              let url = URLComponents(string: origin), url.scheme == "https",
              let host = url.host, !host.isEmpty, url.user == nil, url.password == nil,
              url.path.isEmpty, url.query == nil, url.fragment == nil else {
            throw SonnyError.invalidConfiguration
        }
        self.siteId = siteId
        self.appKey = appKey
        self.origin = origin
    }

    public var embedURL: URL {
        var url = URLComponents(string: origin)!
        url.path = "/embed/widget"
        url.queryItems = [URLQueryItem(name: "siteId", value: siteId),
                          URLQueryItem(name: "appKey", value: appKey),
                          URLQueryItem(name: "sdk", value: "ios/\(Sonny.version)")]
        return url.url!
    }

    func acceptsBridgeMessage(origin: String, isMainFrame: Bool) -> Bool {
        isMainFrame && origin == self.origin
    }
}
