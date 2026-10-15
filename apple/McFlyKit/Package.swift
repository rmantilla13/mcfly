// swift-tools-version: 5.9
import PackageDescription

// The platform-independent half of the Apple app: models, the feed store, the
// assistant stream, pairing and admin calls. The app target (apple/McFly) adds
// the screens and the voice pipeline. `swift test --package-path apple/McFlyKit`
// runs the unit tests without Xcode.
let package = Package(
    name: "McFlyKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "McFlyKit", targets: ["McFlyKit"]),
    ],
    dependencies: [
        .package(url: "https://github.com/supabase/supabase-swift", from: "2.30.0"),
    ],
    targets: [
        .target(
            name: "McFlyKit",
            dependencies: [.product(name: "Supabase", package: "supabase-swift")],
            resources: [.process("Resources")]
        ),
        .testTarget(name: "McFlyKitTests", dependencies: ["McFlyKit"]),
    ]
)
