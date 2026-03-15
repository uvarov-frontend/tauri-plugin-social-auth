import AppKit
import AuthenticationServices
import Foundation
import SwiftRs

private struct AppleSignInPayload: Encodable, Sendable {
  let idToken: String
  let userIdentifier: String
  let authorizationCode: String?
  let email: String?
  let givenName: String?
  let familyName: String?
}

private struct SuccessEnvelope<T: Encodable>: Encodable {
  let data: T
}

private struct ErrorEnvelope: Encodable {
  let error: String
}

private enum SocialAuthError: LocalizedError {
  case windowUnavailable
  case unsupportedCredential
  case missingIdentityToken
  case canceled

  var errorDescription: String? {
    switch self {
    case .windowUnavailable:
      return "presentation window is unavailable"
    case .unsupportedCredential:
      return "unsupported Apple credential"
    case .missingIdentityToken:
      return "identity token is empty"
    case .canceled:
      return "Apple Sign-In canceled by user"
    }
  }
}

private final class BlockingResultBox<T: Sendable>: @unchecked Sendable {
  private let semaphore = DispatchSemaphore(value: 0)
  private let lock = NSLock()
  private var result: Result<T, Error>?

  func resolve(_ value: Result<T, Error>) {
    lock.lock()
    defer { lock.unlock() }
    guard result == nil else { return }
    result = value
    semaphore.signal()
  }

  func wait() throws -> T {
    semaphore.wait()
    lock.lock()
    defer { lock.unlock() }
    return try result!.get()
  }
}

private final class AppleAuthorizationCoordinator: NSObject, ASAuthorizationControllerDelegate, ASAuthorizationControllerPresentationContextProviding {
  private let box: BlockingResultBox<AppleSignInPayload>
  private weak var window: NSWindow?
  private let onComplete: () -> Void

  init(
    box: BlockingResultBox<AppleSignInPayload>,
    window: NSWindow,
    onComplete: @escaping () -> Void
  ) {
    self.box = box
    self.window = window
    self.onComplete = onComplete
  }

  func presentationAnchor(for controller: ASAuthorizationController) -> ASPresentationAnchor {
    window ?? NSWindow()
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithAuthorization authorization: ASAuthorization) {
    defer { onComplete() }

    guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
      box.resolve(.failure(SocialAuthError.unsupportedCredential))
      return
    }

    guard let idToken = decodeDataString(credential.identityToken) else {
      box.resolve(.failure(SocialAuthError.missingIdentityToken))
      return
    }

    let payload = AppleSignInPayload(
      idToken: idToken,
      userIdentifier: credential.user,
      authorizationCode: decodeDataString(credential.authorizationCode),
      email: trimToNil(credential.email),
      givenName: trimToNil(credential.fullName?.givenName),
      familyName: trimToNil(credential.fullName?.familyName)
    )

    box.resolve(.success(payload))
  }

  func authorizationController(controller: ASAuthorizationController, didCompleteWithError error: Error) {
    defer { onComplete() }

    if let authError = error as? ASAuthorizationError, authError.code == .canceled {
      box.resolve(.failure(SocialAuthError.canceled))
      return
    }

    box.resolve(.failure(error))
  }
}

private final class AppleAuthorizationContext {
  let id = UUID()
  let controller: ASAuthorizationController
  let coordinator: AppleAuthorizationCoordinator

  init(coordinator: AppleAuthorizationCoordinator) {
    let request = ASAuthorizationAppleIDProvider().createRequest()
    request.requestedScopes = [.fullName, .email]
    self.controller = ASAuthorizationController(authorizationRequests: [request])
    self.coordinator = coordinator
    self.controller.delegate = coordinator
    self.controller.presentationContextProvider = coordinator
  }
}

private let activeAuthorizationContextsQueue = DispatchQueue(label: "app.tauri.socialauth.apple-auth-contexts")
private var activeAuthorizationContexts: [UUID: AppleAuthorizationContext] = [:]

private func retainContext(_ context: AppleAuthorizationContext) {
  activeAuthorizationContextsQueue.sync {
    activeAuthorizationContexts[context.id] = context
  }
}

private func releaseContext(_ id: UUID) {
  activeAuthorizationContextsQueue.sync {
    activeAuthorizationContexts.removeValue(forKey: id)
  }
}

private func trimToNil(_ value: String?) -> String? {
  guard let value else { return nil }
  let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
  return trimmed.isEmpty ? nil : trimmed
}

private func decodeDataString(_ data: Data?) -> String? {
  guard let data, !data.isEmpty else { return nil }
  return trimToNil(String(data: data, encoding: .utf8))
}

private func encodeSuccess<T: Encodable>(_ value: T) -> SRString {
  do {
    let data = try JSONEncoder().encode(SuccessEnvelope(data: value))
    return SRString(String(decoding: data, as: UTF8.self))
  } catch {
    return encodeError(error)
  }
}

private func encodeError(_ error: Error) -> SRString {
  let envelope = ErrorEnvelope(error: error.localizedDescription)
  let data = (try? JSONEncoder().encode(envelope)) ?? Data("{\"error\":\"failed to encode error response\"}".utf8)
  return SRString(String(decoding: data, as: UTF8.self))
}

private func performAppleSignIn() throws -> AppleSignInPayload {
  let window = NSApp.keyWindow ?? NSApp.mainWindow ?? NSApplication.shared.windows.first
  guard let window else {
    throw SocialAuthError.windowUnavailable
  }

  let box = BlockingResultBox<AppleSignInPayload>()
  var context: AppleAuthorizationContext?
  let coordinator = AppleAuthorizationCoordinator(box: box, window: window) {
    if let id = context?.id {
      releaseContext(id)
    }
  }
  let createdContext = AppleAuthorizationContext(coordinator: coordinator)
  context = createdContext
  retainContext(createdContext)

  DispatchQueue.main.async {
    createdContext.controller.performRequests()
  }

  return try box.wait()
}

@_cdecl("social_auth_macos_apple_sign_in")
public func socialAuthMacOsAppleSignIn() -> SRString {
  do {
    return encodeSuccess(try performAppleSignIn())
  } catch {
    return encodeError(error)
  }
}
