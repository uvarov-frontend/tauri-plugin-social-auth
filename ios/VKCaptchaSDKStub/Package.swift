// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "VKCaptchaSDK",
  platforms: [
    .iOS(.v12),
    .macOS(.v10_13),
  ],
  products: [
    .library(
      name: "VKCaptchaSDK",
      targets: ["VKCaptchaSDK"]
    ),
  ],
  targets: [
    .target(
      name: "VKCaptchaSDK",
      path: "Sources/VKCaptchaSDK"
    ),
  ]
)
