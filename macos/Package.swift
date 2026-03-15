// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "SocialAuthMacOS",
  platforms: [
    .macOS(.v12),
  ],
  products: [
    .library(
      name: "SocialAuthMacOS",
      type: .static,
      targets: ["SocialAuthMacOS"]
    ),
  ],
  dependencies: [
    .package(url: "https://github.com/Brendonovich/swift-rs", from: "1.0.7"),
  ],
  targets: [
    .target(
      name: "SocialAuthMacOS",
      dependencies: [
        .product(name: "SwiftRs", package: "swift-rs"),
      ]
    ),
  ]
)
