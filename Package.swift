// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Sonny",
    platforms: [.iOS(.v15)],
    products: [.library(name: "Sonny", targets: ["Sonny"])],
    targets: [
        .target(name: "Sonny"),
        .testTarget(name: "SonnyTests", dependencies: ["Sonny"])
    ]
)
