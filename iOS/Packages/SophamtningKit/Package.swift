// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SophamtningKit",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [
        .library(name: "SophamtningKit", targets: ["SophamtningKit"]),
        .library(name: "SophamtningDesign", targets: ["SophamtningDesign"]),
    ],
    targets: [
        .target(
            name: "SophamtningKit",
            resources: [.process("Kommun/Resources")]
        ),
        .target(name: "SophamtningDesign", dependencies: ["SophamtningKit"]),
        .testTarget(
            name: "SophamtningKitTests",
            dependencies: ["SophamtningKit", "SophamtningDesign"],
            resources: [.copy("Fixtures")]
        ),
        // Kontraktstester mot produktions-API:t. Körs bara med SOPOR_LIVE=1.
        .testTarget(
            name: "ContractTests",
            dependencies: ["SophamtningKit"]
        ),
    ]
)
