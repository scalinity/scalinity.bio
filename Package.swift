// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "scalinity.bio",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "scalinity.bio", targets: ["ScalinityBio"])
    ],
    targets: [
        .executableTarget(
            name: "ScalinityBio",
            path: ".",
            exclude: [
                "ML",
                "Tests",
                "README.md",
                "requirements.txt",
                "requirements-optional.txt",
                "ENV.example",
                ".gitignore",
                ".cache"
            ],
            sources: ["App"],
            resources: [
                .process("Resources"),
                .process("Data")
            ]
        ),
        .testTarget(
            name: "ScalinityBioTests",
            dependencies: ["ScalinityBio"],
            path: "Tests/ScalinityBioTests"
        )
    ]
)


