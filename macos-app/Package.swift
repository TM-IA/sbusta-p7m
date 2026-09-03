// swift-tools-version:5.9
// SbustaP7mCore: pure Swift port of sbusta_p7m/core.py + preferenze.py,
// no AppKit/SwiftUI dependency so `swift test` runs headless in CI —
// mirrors the separation already used on Android (cms/Estrazione.kt vs
// SbustaP7mActivity.kt). Uses only Security.framework (system, no
// external SwiftPM dependency) — see project-docs/status/macos-swift.md
// for why (CMSDecoder evaluation, step 1.1 of the plan).
//
// SbustaP7mApp: the SwiftUI app itself, depends on SbustaP7mCore.
import PackageDescription

let package = Package(
    name: "SbustaP7mCore",
    platforms: [.macOS(.v11)],
    products: [
        .library(name: "SbustaP7mCore", targets: ["SbustaP7mCore"]),
        .executable(name: "SbustaP7mApp", targets: ["SbustaP7mApp"]),
    ],
    targets: [
        .target(name: "SbustaP7mCore"),
        .executableTarget(name: "SbustaP7mApp", dependencies: ["SbustaP7mCore"]),
        .testTarget(
            name: "SbustaP7mCoreTests",
            dependencies: ["SbustaP7mCore"],
            resources: [.copy("Resources")]
        ),
    ]
)
