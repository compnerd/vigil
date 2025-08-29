// swift-tools-version: 6.2

import PackageDescription

let _ = Package(name: "vigil",
                dependencies: [
                  .package(url: "https://github.com/compnerd/swift-platform-core",
                           branch: "main"),
                  .package(url: "https://github.com/apple/swift-argument-parser",
                           from: "1.6.0"),
                ],
                targets: [
                  .executableTarget(name: "vigil", dependencies: [
                    .product(name: "ArgumentParser", package: "swift-argument-parser"),
                    .product(name: "WindowsCore", package: "swift-platform-core"),
                  ], swiftSettings: [
                    .enableExperimentalFeature("AccessLevelOnImport"),
                  ], plugins: [
                    .plugin(name: "PackageVersion"),
                  ]),
                  .plugin(name: "PackageVersion", capability: .buildTool),
                ])
