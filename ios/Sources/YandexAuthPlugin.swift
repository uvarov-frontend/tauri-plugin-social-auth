import Foundation
import Tauri

#if canImport(YandexLoginSDK)
import YandexLoginSDK
#endif

@objc(YandexAuthPlugin)
class YandexAuthPlugin: Plugin {
#if canImport(YandexLoginSDK)
  private var pendingInvoke: Invoke?
  private var observerAttached = false
#endif

  @objc public func signIn(_ invoke: Invoke) {
    SocialAuthBridge.runOnMain {
#if canImport(YandexLoginSDK)
      guard let presentingViewController = SocialAuthBridge.presentingViewController(from: self.manager) else {
        invoke.reject("Yandex Sign-In failed: presenting view controller is missing", code: "YANDEX_AUTH_INIT_FAILED")
        return
      }

      guard let clientId = SocialAuthBridge.socialConfigValue("YA_IOS_CLIENT_ID") else {
        invoke.reject(
          "Yandex Sign-In failed: YA_IOS_CLIENT_ID is missing in iOS build config",
          code: "YANDEX_AUTH_INIT_FAILED"
        )
        return
      }

      let urlScheme = "yx\(clientId)"
      guard SocialAuthBridge.hasURLScheme(urlScheme) else {
        invoke.reject(
          "Yandex Sign-In failed: CFBundleURLTypes must contain \(urlScheme)",
          code: "YANDEX_AUTH_IOS_URL_SCHEME_MISSING"
        )
        return
      }

      if self.pendingInvoke != nil {
        invoke.reject("Yandex Sign-In is already in progress", code: "YANDEX_AUTH_IN_PROGRESS")
        return
      }

      if !self.observerAttached {
        YandexLoginSDK.shared.add(observer: self)
        self.observerAttached = true
      }

      do {
        try YandexLoginSDK.shared.activate(with: clientId)
      } catch {
        invoke.reject("Yandex Sign-In initialization failed", code: "YANDEX_AUTH_INIT_FAILED", error: error)
        return
      }

      self.pendingInvoke = invoke

      do {
        try YandexLoginSDK.shared.authorize(
          with: presentingViewController,
          customValues: nil,
          authorizationStrategy: .webOnly
        )
      } catch {
        self.pendingInvoke = nil
        invoke.reject("Yandex Sign-In failed", code: "YANDEX_AUTH_FAILED", error: error)
      }
#else
      invoke.reject(
        "Yandex Login SDK is not linked for iOS",
        code: "YANDEX_AUTH_IOS_SDK_MISSING"
      )
#endif
    }
  }
}

#if canImport(YandexLoginSDK)
extension YandexAuthPlugin: YandexLoginSDKObserver {
  func didFinishLogin(with result: Result<LoginResult, any Error>) {
    SocialAuthBridge.runOnMain {
      guard let invoke = self.pendingInvoke else { return }
      self.pendingInvoke = nil

      switch result {
      case .success(let loginResult):
        guard let token = SocialAuthBridge.trimToNil(loginResult.token) else {
          invoke.reject("Yandex Sign-In failed: access token is empty", code: "YANDEX_ACCESS_TOKEN_EMPTY")
          return
        }

        invoke.resolve(SocialAccessTokenResult(accessToken: token))

      case .failure(let error):
        if self.isCanceled(error) {
          invoke.reject("Yandex Sign-In canceled by user", code: "YANDEX_AUTH_CANCELED")
          return
        }

        invoke.reject("Yandex Sign-In failed", code: "YANDEX_AUTH_FAILED", error: error)
      }
    }
  }

  private func isCanceled(_ error: Error) -> Bool {
    guard let sdkError = error as? any YandexLoginSDKError else { return false }
    return sdkError.message.localizedCaseInsensitiveContains("user has closed the view controller")
  }
}
#endif

@_cdecl("init_plugin_yandex_auth")
func initPluginYandexAuth() -> Plugin {
  YandexAuthPlugin()
}
