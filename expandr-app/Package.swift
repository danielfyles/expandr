// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExpandrSnippets",
    // Source language of the UI strings. Translations live in
    // Localization/<target>/<lang>.lproj/Localizable.strings and are copied into
    // the .app bundles by the build scripts (Bundle.main resolves them).
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],  // NavigationSplitView (3-pane) needs macOS 13+
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "ExpandrSnippets",
            dependencies: ["Yams", .product(name: "Sparkle", package: "Sparkle")]
        ),
        // Native form renderer: reads an espanso form spec as JSON on stdin,
        // shows the form, writes the filled values as JSON on stdout.
        .executableTarget(
            name: "ExpandrForm",
            resources: [.copy("Fonts")]
        ),
    ]
)
