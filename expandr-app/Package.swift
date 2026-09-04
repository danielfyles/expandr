// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ExpandrSnippets",
    platforms: [.macOS(.v13)],  // NavigationSplitView (3-pane) needs macOS 13+
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "ExpandrSnippets",
            dependencies: ["Yams"]
        ),
        // Native form renderer: reads an espanso form spec as JSON on stdin,
        // shows the form, writes the filled values as JSON on stdout.
        .executableTarget(
            name: "ExpandrForm"
        ),
    ]
)
