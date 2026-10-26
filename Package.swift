// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Kettle",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Kettle", targets: ["KettleApp"]),
        .executable(name: "kettle-tools", targets: ["kettle-tools"]),
    ],
    targets: [
        .target(name: "KettleCore"),
        .target(name: "KettleIcon", dependencies: ["KettleCore"]),
        .executableTarget(name: "KettleApp", dependencies: ["KettleCore", "KettleIcon"]),
        .executableTarget(name: "kettle-tools", dependencies: ["KettleCore", "KettleIcon"]),
        .testTarget(name: "KettleCoreTests", dependencies: ["KettleCore"]),
    ]
)
