import Foundation
import Tauri
import UIKit

struct SocialAccessTokenResult: Encodable {
  let accessToken: String
}

struct SocialIdTokenResult: Encodable {
  let idToken: String
}

struct AppleSignInResult: Encodable {
  let idToken: String
  let userIdentifier: String
  let authorizationCode: String?
  let email: String?
  let givenName: String?
  let familyName: String?
}

enum SocialAuthBridge {
  private static let socialAuthConfig: [String: Any] = {
    guard
      let configUrl = Bundle.main.url(forResource: "SocialAuthConfig", withExtension: "plist"),
      let data = NSDictionary(contentsOf: configUrl) as? [String: Any]
    else {
      return [:]
    }

    return data
  }()

  static func runOnMain(_ block: @escaping () -> Void) {
    if Thread.isMainThread {
      block()
      return
    }

    DispatchQueue.main.async(execute: block)
  }

  static func trimToNil(_ value: String?) -> String? {
    guard let value else { return nil }
    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
  }

  static func presentingViewController(from manager: PluginManager) -> UIViewController? {
    manager.viewController
  }

  static func presentingWindow(from viewController: UIViewController?) -> UIWindow? {
    if let window = viewController?.view.window {
      return window
    }

    return UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
      .first(where: \.isKeyWindow)
  }

  static func decodeDataString(_ data: Data?) -> String? {
    guard let data, !data.isEmpty else { return nil }
    return trimToNil(String(data: data, encoding: .utf8))
  }

  static func hasURLScheme(_ scheme: String) -> Bool {
    guard !scheme.isEmpty else { return false }

    let urlTypes = Bundle.main.infoDictionary?["CFBundleURLTypes"] as? [[String: Any]] ?? []
    for type in urlTypes {
      let schemes = type["CFBundleURLSchemes"] as? [String] ?? []
      if schemes.contains(where: { $0.caseInsensitiveCompare(scheme) == .orderedSame }) {
        return true
      }
    }

    return false
  }

  static func hasQueryScheme(_ scheme: String) -> Bool {
    guard !scheme.isEmpty else { return false }

    let querySchemes = Bundle.main.infoDictionary?["LSApplicationQueriesSchemes"] as? [String] ?? []
    return querySchemes.contains(where: { $0.caseInsensitiveCompare(scheme) == .orderedSame })
  }

  static func socialConfigValue(_ key: String) -> String? {
    if let infoValue = trimToNil(Bundle.main.object(forInfoDictionaryKey: key) as? String) {
      return infoValue
    }

    return trimToNil(socialAuthConfig[key] as? String)
  }
}
