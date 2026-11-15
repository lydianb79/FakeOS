// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "FakeOS",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "FakeOS",
            path: "Sources/FakeOS",
            swiftSettings: [.unsafeFlags(["-Ounchecked"], .when(configuration: .release))]
        )
    ]
)
