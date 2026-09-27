// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "OrarendApp",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "OrarendApp", targets: ["OrarendApp"])
    ],
    targets: [
        .executableTarget(
            name: "OrarendApp",
            path: "Sources/OrarendApp"
        ),
        .testTarget(
            name: "OrarendAppTests",
            dependencies: ["OrarendApp"],
            path: "Tests/OrarendAppTests"
        )
    ]
)
