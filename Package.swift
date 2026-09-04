// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SFTPManager",
    platforms: [.macOS(.v15)],
    dependencies: [
        .package(url: "https://github.com/orlandos-nl/Citadel.git", from: "0.12.1"),
        // Terminal emulation (ANSI/vt100 rendering and key encoding) for the
        // shell panel; the SSH side of it is Citadel's PTY channel.
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "SFTPManager",
            dependencies: [
                .product(name: "Citadel", package: "Citadel"),
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/SFTPManager",
            swiftSettings: [
                .swiftLanguageMode(.v5)
            ]
        )
    ]
)
