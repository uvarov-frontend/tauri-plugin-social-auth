import AuthenticationServices
import Foundation
import Tauri

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

#if canImport(VKID)
import VKID
#endif

#if canImport(YandexLoginSDK)
import YandexLoginSDK
#endif

private struct VkSignInArgs: Decodable {
  let theme: String?
}

private final class AppleSignInCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private let invoke: Invoke
  private weak var presentationWindow: UIWindow?
  private let onComplete: () -> Void

  init(invoke: Invoke, presentationWindow: UIWindow, onComplete: @escaping () -> Void) {
    self.invoke = invoke
    self.presentationWindow = presentationWindow
    self.onComplete = onComplete
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    presentationWindow ?? ASPresentationAnchor()
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    defer { onComplete() }

    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      invoke.reject("Apple Sign-In failed: unsupported credential", code: "APPLE_AUTH_FAILED")
      return
    }

    guard let idToken = SocialAuthBridge.decodeDataString(credential.identityToken) else {
      invoke.reject("Apple Sign-In failed: identity token is empty", code: "APPLE_ID_TOKEN_EMPTY")
      return
    }

    let result = AppleSignInResult(
      idToken: idToken,
      userIdentifier: credential.user,
      authorizationCode: SocialAuthBridge.decodeDataString(credential.authorizationCode),
      email: SocialAuthBridge.trimToNil(credential.email),
      givenName: SocialAuthBridge.trimToNil(credential.fullName?.givenName),
      familyName: SocialAuthBridge.trimToNil(credential.fullName?.familyName)
    )

    invoke.resolve(result)
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    defer { onComplete() }

    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
      invoke.reject("Apple Sign-In canceled by user", code: "APPLE_AUTH_CANCELED")
      return
    }

    invoke.reject("Apple Sign-In failed", code: "APPLE_AUTH_FAILED", error: error)
  }
}

@objc(SocialAuthPlugin)
class SocialAuthPlugin: Plugin {
#if canImport(VKID)
  private var configuredVkClientId: String?
  private var configuredVkClientSecret: String?
#endif

#if canImport(YandexLoginSDK)
  private var pendingYandexInvoke: Invoke?
  private var isYandexObserverAttached = false
#endif

  private var appleCoordinator: AppleSignInCoordinator?

  @objc public func googleSignIn(_ invoke: Invoke) {
    SocialAuthBridge.runOnMain {
#if canImport(GoogleSignIn)
      guard let presentingViewController = SocialAuthBridge.presentingViewController(from: self.manager) else {
        invoke.reject("Google Sign-In failed: presenting view controller is missing", code: "GOOGLE_SIGN_IN_INIT_FAILED")
        return
      }

      guard let webClientId = SocialAuthBridge.socialConfigValue("GOOGLE_SERVER_CLIENT_ID") else {
        invoke.reject(
          "Google Sign-In failed: GOOGLE_SERVER_CLIENT_ID is missing in iOS build config",
          code: "GOOGLE_SIGN_IN_INIT_FAILED"
        )
        return
      }

      guard let iosClientId = SocialAuthBridge.socialConfigValue("GOOGLE_IOS_CLIENT_ID") else {
        invoke.reject(
          "Google Sign-In failed: GOOGLE_IOS_CLIENT_ID is missing in iOS build config",
          code: "GOOGLE_SIGN_IN_INIT_FAILED"
        )
        return
      }

      GIDSignIn.sharedInstance.configuration = GIDConfiguration(
        clientID: iosClientId,
        serverClientID: webClientId
      )

      GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController) { result, error in
        if let error = error as NSError? {
          if error.domain == kGIDSignInErrorDomain && error.code == -5 {
            invoke.reject("Google Sign-In canceled by user", code: "GOOGLE_AUTH_CANCELED")
            return
          }

          invoke.reject("Google Sign-In failed on iOS", code: "GOOGLE_SIGN_IN_FAILED", error: error)
          return
        }

        guard let token = SocialAuthBridge.trimToNil(result?.user.idToken?.tokenString) else {
          invoke.reject("Google Sign-In failed: idToken is empty", code: "GOOGLE_ID_TOKEN_EMPTY")
          return
        }

        invoke.resolve(SocialIdTokenResult(idToken: token))
      }
#else
      invoke.reject("Google Sign-In SDK is not linked for iOS", code: "GOOGLE_AUTH_IOS_SDK_MISSING")
#endif
    }
  }

  @objc public func vkSignIn(_ invoke: Invoke) {
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
        if self.configuredVkClientId != clientId || self.configuredVkClientSecret != clientSecret {
          let appearance = Appearance(
            colorScheme: self.resolveVkColorScheme(args?.theme),
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
          self.configuredVkClientId = clientId
          self.configuredVkClientSecret = clientSecret
        } else {
          VKID.shared.appearance = Appearance(
            colorScheme: self.resolveVkColorScheme(args?.theme),
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
      invoke.reject("VK ID SDK is not linked for iOS", code: "VK_AUTH_IOS_SDK_MISSING")
#endif
    }
  }

  @objc public func yandexSignIn(_ invoke: Invoke) {
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

      if self.pendingYandexInvoke != nil {
        invoke.reject("Yandex Sign-In is already in progress", code: "YANDEX_AUTH_IN_PROGRESS")
        return
      }

      if !self.isYandexObserverAttached {
        YandexLoginSDK.shared.add(observer: self)
        self.isYandexObserverAttached = true
      }

      do {
        try YandexLoginSDK.shared.activate(with: clientId)
      } catch {
        invoke.reject("Yandex Sign-In initialization failed", code: "YANDEX_AUTH_INIT_FAILED", error: error)
        return
      }

      self.pendingYandexInvoke = invoke

      do {
        try YandexLoginSDK.shared.authorize(
          with: presentingViewController,
          customValues: nil,
          authorizationStrategy: .webOnly
        )
      } catch {
        self.pendingYandexInvoke = nil
        invoke.reject("Yandex Sign-In failed", code: "YANDEX_AUTH_FAILED", error: error)
      }
#else
      invoke.reject("Yandex Login SDK is not linked for iOS", code: "YANDEX_AUTH_IOS_SDK_MISSING")
#endif
    }
  }

  @objc public func appleSignIn(_ invoke: Invoke) {
    SocialAuthBridge.runOnMain {
      guard let presentingViewController = SocialAuthBridge.presentingViewController(from: self.manager) else {
        invoke.reject("Apple Sign-In failed: presenting view controller is missing", code: "APPLE_AUTH_INIT_FAILED")
        return
      }

      guard let presentationWindow = SocialAuthBridge.presentingWindow(from: presentingViewController) else {
        invoke.reject("Apple Sign-In failed: presentation window is missing", code: "APPLE_AUTH_INIT_FAILED")
        return
      }

      guard self.appleCoordinator == nil else {
        invoke.reject("Apple Sign-In is already in progress", code: "APPLE_AUTH_IN_PROGRESS")
        return
      }

      let coordinator = AppleSignInCoordinator(
        invoke: invoke,
        presentationWindow: presentationWindow,
        onComplete: { [weak self] in
          self?.appleCoordinator = nil
        }
      )
      self.appleCoordinator = coordinator

      let request = ASAuthorizationAppleIDProvider().createRequest()
      request.requestedScopes = [.fullName, .email]

      let controller = ASAuthorizationController(authorizationRequests: [request])
      controller.delegate = coordinator
      controller.presentationContextProvider = coordinator
      controller.performRequests()
    }
  }

#if canImport(VKID)
  private func resolveVkColorScheme(_ theme: String?) -> Appearance.ColorScheme {
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

#if canImport(YandexLoginSDK)
extension SocialAuthPlugin: YandexLoginSDKObserver {
  func didFinishLogin(with result: Result<LoginResult, any Error>) {
    SocialAuthBridge.runOnMain {
      guard let invoke = self.pendingYandexInvoke else { return }
      self.pendingYandexInvoke = nil

      switch result {
      case .success(let loginResult):
        guard let token = SocialAuthBridge.trimToNil(loginResult.token) else {
          invoke.reject("Yandex Sign-In failed: access token is empty", code: "YANDEX_ACCESS_TOKEN_EMPTY")
          return
        }

        invoke.resolve(SocialAccessTokenResult(accessToken: token))

      case .failure(let error):
        if self.isYandexCanceled(error) {
          invoke.reject("Yandex Sign-In canceled by user", code: "YANDEX_AUTH_CANCELED")
          return
        }

        invoke.reject("Yandex Sign-In failed", code: "YANDEX_AUTH_FAILED", error: error)
      }
    }
  }

  private func isYandexCanceled(_ error: Error) -> Bool {
    guard let sdkError = error as? any YandexLoginSDKError else { return false }
    return sdkError.message.localizedCaseInsensitiveContains("user has closed the view controller")
  }
}
#endif

@_cdecl("init_plugin_social_auth")
func initPluginSocialAuth() -> Plugin {
  SocialAuthPlugin()
}
