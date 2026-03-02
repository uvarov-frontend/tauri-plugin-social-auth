import Foundation
import Tauri

#if canImport(VKID)
import VKID
#endif

private struct VkSignInArgs: Decodable {
  let theme: String?
}

@objc(VkAuthPlugin)
class VkAuthPlugin: Plugin {
#if canImport(VKID)
  private var configuredClientId: String?
  private var configuredClientSecret: String?
#endif

  @objc public func signIn(_ invoke: Invoke) {
    SocialAuthBridge.runOnMain {
      let args = try? invoke.parseArgs(VkSignInArgs.self)

#if canImport(VKID)
      guard let presentingViewController = SocialAuthBridge.presentingViewController(from: self.manager) else {
        invoke.reject("VK ID Sign-In failed: presenting view controller is missing", code: "VK_AUTH_INIT_FAILED")
        return
      }

      guard let clientId = SocialAuthBridge.socialConfigValue("VK_IOS_CLIENT_ID") else {
        invoke.reject(
          "VK ID Sign-In failed: VK_IOS_CLIENT_ID is missing in iOS build config",
          code: "VK_AUTH_INIT_FAILED"
        )
        return
      }

      guard let clientSecret = SocialAuthBridge.socialConfigValue("VK_IOS_CLIENT_SECRET") else {
        invoke.reject(
          "VK ID Sign-In failed: VK_IOS_CLIENT_SECRET is missing in iOS build config",
          code: "VK_AUTH_INIT_FAILED"
        )
        return
      }

      guard SocialAuthBridge.hasQueryScheme("vkauthorize-silent") else {
        invoke.reject(
          "VK ID Sign-In failed: LSApplicationQueriesSchemes must contain vkauthorize-silent",
          code: "VK_AUTH_IOS_URL_SCHEME_MISSING"
        )
        return
      }

      let clientScheme = "vk\(clientId)"
      guard SocialAuthBridge.hasURLScheme(clientScheme) else {
        invoke.reject(
          "VK ID Sign-In failed: CFBundleURLTypes must contain \(clientScheme)",
          code: "VK_AUTH_IOS_URL_SCHEME_MISSING"
        )
        return
      }

      do {
        if self.configuredClientId != clientId || self.configuredClientSecret != clientSecret {
          let appearance = Appearance(
            colorScheme: self.resolveColorScheme(args?.theme),
            locale: .system
          )
          let config = Configuration(
            appCredentials: AppCredentials(
              clientId: clientId,
              clientSecret: clientSecret
            ),
            appearance: appearance,
            loggingEnabled: false
          )

          try VKID.shared.set(config: config)
          self.configuredClientId = clientId
          self.configuredClientSecret = clientSecret
        } else {
          VKID.shared.appearance = Appearance(
            colorScheme: self.resolveColorScheme(args?.theme),
            locale: .system
          )
        }
      } catch {
        invoke.reject("VK ID Sign-In initialization failed", code: "VK_AUTH_INIT_FAILED", error: error)
        return
      }

      let authConfiguration = AuthConfiguration(
        scope: Scope(Set(["vkid.personal_info", "email", "user_id"])),
        forceWebViewFlow: true
      )

      VKID.shared.authorize(
        with: authConfiguration,
        using: .uiViewController(presentingViewController)
      ) { result in
        do {
          let session = try result.get()
          guard let token = SocialAuthBridge.trimToNil(session.accessToken.value) else {
            invoke.reject("VK ID Sign-In failed: access token is empty", code: "VK_ACCESS_TOKEN_EMPTY")
            return
          }

          invoke.resolve(SocialAccessTokenResult(accessToken: token))
        } catch AuthError.cancelled {
          invoke.reject("VK ID Sign-In canceled by user", code: "VK_AUTH_CANCELED")
        } catch {
          invoke.reject("VK ID Sign-In failed", code: "VK_AUTH_FAILED", error: error)
        }
      }
#else
      invoke.reject(
        "VK ID SDK is not linked for iOS",
        code: "VK_AUTH_IOS_SDK_MISSING"
      )
#endif
    }
  }

#if canImport(VKID)
  private func resolveColorScheme(_ theme: String?) -> Appearance.ColorScheme {
    switch SocialAuthBridge.trimToNil(theme)?.lowercased() {
    case "dark":
      return .dark
    case "light":
      return .light
    default:
      return .system
    }
  }
#endif
}

@_cdecl("init_plugin_vk_auth")
func initPluginVkAuth() -> Plugin {
  VkAuthPlugin()
}
