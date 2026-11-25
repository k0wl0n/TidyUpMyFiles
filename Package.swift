// swift-tools-version:5.9
import PackageDescription

let strictConcurrency: [SwiftSetting] = [.enableExperimentalFeature("StrictConcurrency")]

let package = Package(
    name: "TidyUpMyFiles",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "TidyUpMyFilesApp", targets: ["TidyUpMyFilesApp"]),
        .executable(name: "tidyup", targets: ["TidyUpMyFilesCLI"]),
        .library(name: "TidyUpMyFilesCore", targets: ["TidyUpMyFilesCore"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", exact: "6.2.2"),
    ],
    targets: [
        .target(
            name: "TidyUpMyFilesCore",
            dependencies: [.product(name: "Yams", package: "Yams")],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "TidyUpMyFilesApp",
            dependencies: ["TidyUpMyFilesCore"],
            swiftSettings: strictConcurrency
        ),
        .executableTarget(
            name: "TidyUpMyFilesCLI",
            dependencies: ["TidyUpMyFilesCore"],
            swiftSettings: strictConcurrency
        ),
        .testTarget(
            name: "TidyUpMyFilesCoreTests",
            dependencies: ["TidyUpMyFilesCore"],
            swiftSettings: strictConcurrency
        ),
    ]
)
