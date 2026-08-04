// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "cmux",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "cmux", targets: ["cmux"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.5.0")
    ],
    targets: [
        .executableTarget(
            name: "cmux",
            dependencies: ["SwiftTerm"],
            path: "Sources"
        )
    ]
)
