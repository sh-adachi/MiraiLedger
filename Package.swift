// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MiraiLedgerCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [.library(name: "MiraiLedgerCore", targets: ["MiraiLedgerCore"])],
    targets: [
        .target(name: "MiraiLedgerCore", path: "Core"),
        .testTarget(name: "MiraiLedgerCoreTests", dependencies: ["MiraiLedgerCore"], path: "Tests/MiraiLedgerCoreTests")
    ]
)
