// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "muidprobe",
    platforms: [.macOS(.v15)],          // MKMapItem.identifier needs macOS 15 / iOS 18
    targets: [
        .executableTarget(name: "muidprobe", path: "Sources/muidprobe")
    ]
)
