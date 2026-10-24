// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Calcsmith",
    platforms: [.macOS(.v15), .iOS(.v18)],
    products: [
        .library(name: "CalcsmithCore", targets: ["CalcsmithCore"]),
        .library(name: "CalcsmithUI", targets: ["CalcsmithUI"]),
    ],
    targets: [
        // Platform-independent math, formatting, and the formula library.
        .target(name: "CalcsmithCore"),
        // SwiftUI views shared by the macOS and iOS apps.
        .target(name: "CalcsmithUI", dependencies: ["CalcsmithCore"]),
        .testTarget(name: "CalcsmithCoreTests", dependencies: ["CalcsmithCore"]),
    ]
)
