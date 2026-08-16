// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "muidprobe",
    platforms: [.macOS(.v15)],          // MKMapItem.identifier needs macOS 15 / iOS 18
    targets: [
        .executableTarget(
            name: "muidprobe",
            path: "Sources/muidprobe",
            // MapKit's result types aren't Sendable; Swift 6 mode would reject them.
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "cityprobe",
            path: "Sources/cityprobe",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
