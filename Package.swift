// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RYKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15),
        .tvOS(.v13)
    ],
    products: [
        .library(name: "RYKitCore", targets: ["RYKitCore"]),
        .library(name: "RYKitNetworkHttp", targets: ["RYKitNetworkHttp"]),
        .library(name: "RYKitNetworkStomp", targets: ["RYKitNetworkStomp"])
    ],
    targets: [
        .target(
            name: "RYKitCore",
            path: "Classes/Core"
        ),
        .target(
            name: "RYKitNetworkHttp",
            dependencies: ["RYKitCore"],
            path: "Classes/Http"
        ),
        .target(
            name: "RYKitNetworkStomp",
            dependencies: ["RYKitCore"],
            path: "Classes/Stomp"
        )
    ]
)
