// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "DSHMeter",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "DSHMeter", targets: ["DSHMeter"])],
    dependencies: [.package(url: "https://github.com/jpsim/Yams.git", exact: "6.1.0")],
    targets: [
        .target(name: "DSHMeterCore", dependencies: ["Yams"], path: "Sources/DSHMeterCore"),
        .executableTarget(name: "DSHMeter", dependencies: ["DSHMeterCore"], path: "DSHMeter",
                          exclude: ["Assets.xcassets", "Localizable.xcstrings"]),
        .executableTarget(name: "DSHMeterChecks", dependencies: ["DSHMeterCore"], path: "Tests/CoreChecks"),
        .testTarget(name: "DSHMeterCoreTests", dependencies: ["DSHMeterCore"], path: "Tests/DSHMeterCoreTests")
    ]
)
