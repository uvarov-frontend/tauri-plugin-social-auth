import Foundation
import Tauri

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@objc(GoogleAuthPlugin)
class GoogleAuthPlugin: Plugin {
  @objc public func signIn(_ invoke: Invoke) {
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

          invoke.reject(
            "Google Sign-In failed on iOS",
            code: "GOOGLE_SIGN_IN_FAILED",
            error: error
          )
          return
        }

        guard let token = SocialAuthBridge.trimToNil(result?.user.idToken?.tokenString) else {
          invoke.reject("Google Sign-In failed: idToken is empty", code: "GOOGLE_ID_TOKEN_EMPTY")
          return
        }

        invoke.resolve(SocialIdTokenResult(idToken: token))
      }
#else
      invoke.reject(
        "Google Sign-In SDK is not linked for iOS",
        code: "GOOGLE_AUTH_IOS_SDK_MISSING"
      )
#endif
    }
  }
}

@_cdecl("init_plugin_google_auth")
func initPluginGoogleAuth() -> Plugin {
  GoogleAuthPlugin()
}
