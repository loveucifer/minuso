// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Minuso",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Minuso", targets: ["Minuso"])],
    targets: [
        .executableTarget(name: "Minuso"),
        .testTarget(name: "MinusoTests", dependencies: ["Minuso"])
    ]
)
