// swift-tools-version: 5.9

import PackageDescription

let package = Package(
  name: "tauri-plugin-social-auth",
  platforms: [
    .iOS(.v15),
    .macOS(.v10_15)
  ],
  products: [
    .library(
      name: "tauri-plugin-social-auth",
      type: .static,
      targets: ["tauri-plugin-social-auth"]
    )
  ],
  dependencies: [
    .package(name: "Tauri", path: "../.tauri/tauri-api"),
    .package(url: "https://github.com/google/GoogleSignIn-iOS.git", exact: "9.1.0"),
    .package(url: "https://github.com/VKCOM/vkid-ios-sdk.git", exact: "2.9.2"),
    .package(url: "https://github.com/yandexmobile/yandex-login-sdk-ios.git", exact: "3.0.2")
  ],
  targets: [
    .target(
      name: "tauri-plugin-social-auth",
      dependencies: [
        .byName(name: "Tauri"),
        .product(name: "GoogleSignIn", package: "GoogleSignIn-iOS"),
        .product(name: "VKID", package: "vkid-ios-sdk"),
        .product(name: "YandexLoginSDK", package: "yandex-login-sdk-ios")
      ],
      path: "Sources"
    )
  ]
)
