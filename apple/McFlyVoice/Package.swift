// swift-tools-version: 6.0
import PackageDescription

// McFly's voice: Kokoro-82M on Core ML, the voice the display and the web speak
// with, bundled in the app (KokoroVoice). Its own package, apart from McFlyKit,
// so the kit's tests and CI never compile the Core ML pipeline or copy its
// ~190 MB of model files. Those are fetched into Sources/McFlyVoice/Kokoro by
// scripts/fetch-kokoro.sh; without them the app builds and speaks with the
// system voice. `swift test --package-path apple/McFlyVoice` runs its tests
// (the one that speaks needs the files).
let package = Package(
    name: "McFlyVoice",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "McFlyVoice", targets: ["McFlyVoice"]),
    ],
    targets: [
        .target(
            name: "McFlyVoice",
            dependencies: ["KokoroPipeline", "KokoroG2P"],
            resources: [.copy("Kokoro")]
        ),
        // Vendored from github.com/mattmireles/kokoro-coreml (Apache-2.0), by way of
        // Homestead; see ThirdParty/.
        .target(
            name: "KokoroPipeline",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .target(
            name: "KokoroG2P",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "McFlyVoiceTests",
            dependencies: ["McFlyVoice", "KokoroG2P", "KokoroPipeline"]
        ),
    ]
)
