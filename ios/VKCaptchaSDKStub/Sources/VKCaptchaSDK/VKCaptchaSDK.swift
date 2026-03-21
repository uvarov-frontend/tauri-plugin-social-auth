import Foundation
import UIKit

public enum VKCaptchaResultError: Error, Equatable, Hashable {
  case unknown
  case cancel
  case connection
}

public enum CaptchaHandlingError: Error {
  case failedToCreateCaptchaData
  case noCaptcha
  case captchaError(any Error)
}

public enum VKCaptchaType {
  case domain(String)
  case `default`
}

public struct VKCaptchaData: Sendable {
  public let type: VKCaptchaType

  public init(type: VKCaptchaType) {
    self.type = type
  }
}

public protocol VKCaptchaPresenter: AnyObject {
  var presentingViewController: UIViewController? { get }

  func navigate(viewController: UIViewController, presentationStyle: VKCaptchaPresentationStyle)
  func dismiss(viewController: UIViewController, animated: Bool, completion: (() -> Void)?)
}

public extension VKCaptchaPresenter {
  func dismiss(viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
    viewController.dismiss(animated: animated, completion: completion)
  }
}

public enum VKCaptchaPresentationStyle: Int {
  case modal
  case push
}

@objc
public class VKCaptchaPresenterDefault: NSObject, VKCaptchaPresenter {
  public var presentingViewController: UIViewController?

  public init(presentingViewController: UIViewController) {
    self.presentingViewController = presentingViewController
  }

  public func navigate(viewController: UIViewController, presentationStyle: VKCaptchaPresentationStyle) {
    presentingViewController?.present(viewController, animated: true)
  }
}

@objc
public class VKCaptchaNewUIWindowPresenter: NSObject, VKCaptchaPresenter {
  public var presentingViewController: UIViewController?

  public override init() {
    self.presentingViewController = nil
    super.init()
  }

  public func navigate(viewController: UIViewController, presentationStyle: VKCaptchaPresentationStyle) {
    presentingViewController?.present(viewController, animated: true)
  }

  public func dismiss(viewController: UIViewController, animated: Bool, completion: (() -> Void)?) {
    viewController.dismiss(animated: animated, completion: completion)
  }
}

public struct VKCaptchaToken: Sendable {
  public let value: String
  public let type: VKCaptchaType

  public init(value: String, type: VKCaptchaType) {
    self.value = value
    self.type = type
  }
}

public enum VKCaptchaConstants {
  public static let domainCaptchaHeaderName = "X-VKCaptcha-Token"
  public static let defaultCaptchaParamName = "captcha_token"
}

public final class VKCaptchaHandler {
  public init() {}

  public static func getDomainToken(for domain: String) -> VKCaptchaToken? {
    let trimmed = domain.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else { return nil }
    return nil
  }

  public func handleCaptcha(
    from response: Data?,
    responseHeaders: [AnyHashable: Any]?,
    domain: String,
    with presenter: any VKCaptchaPresenter = VKCaptchaNewUIWindowPresenter(),
    completion: @escaping (Result<VKCaptchaToken, CaptchaHandlingError>) -> Void
  ) {
    completion(.failure(.noCaptcha))
  }

  public func handleCaptchaData(
    from data: Data?,
    responseHeaders: [AnyHashable: Any]?,
    domain: String
  ) -> Result<VKCaptchaData, CaptchaHandlingError> {
    .failure(.noCaptcha)
  }

  public func openCaptcha(
    captchaData: VKCaptchaData,
    presenter: any VKCaptchaPresenter = VKCaptchaNewUIWindowPresenter(),
    completion: @escaping (Result<VKCaptchaToken, CaptchaHandlingError>) -> Void
  ) {
    completion(.failure(.captchaError(VKCaptchaResultError.unknown)))
  }

  public func getCaptchaViewController(
    captchaData: VKCaptchaData,
    completion: @escaping (Result<VKCaptchaToken, CaptchaHandlingError>) -> Void
  ) -> UIViewController? {
    completion(.failure(.noCaptcha))
    return nil
  }
}

public extension URLRequest {
  enum AddingCaptchaTokenError: Error, Equatable, Hashable {
    case urlError
  }

  mutating func addCaptchaToken(token: VKCaptchaToken) throws {
    switch token.type {
    case .domain:
      addDomainCaptcha(token: token.value)
    case .default:
      try addDefaultCaptcha(token: token.value)
    }
  }

  mutating func addDomainCaptcha(token: String) {
    setValue(token, forHTTPHeaderField: VKCaptchaConstants.domainCaptchaHeaderName)
  }

  mutating func addDefaultCaptcha(token: String) throws {
    guard let url else {
      throw AddingCaptchaTokenError.urlError
    }

    guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
      throw AddingCaptchaTokenError.urlError
    }

    var items = components.queryItems ?? []
    items.append(URLQueryItem(name: VKCaptchaConstants.defaultCaptchaParamName, value: token))
    components.queryItems = items

    guard let updatedURL = components.url else {
      throw AddingCaptchaTokenError.urlError
    }

    self.url = updatedURL
  }
}

public struct VKCaptchaConfiguration {
  public let url: URL

  public init(url: URL) {
    self.url = url
  }
}

@objc
public final class VKCaptcha: NSObject {
  private let configuration: VKCaptchaConfiguration

  public init(configuration: VKCaptchaConfiguration) {
    self.configuration = configuration
  }

  public static func getHitmanToken(for domain: String) -> String? {
    nil
  }

  public func getCaptchaViewController(
    completion: @escaping (Result<String, any Error>) -> Void
  ) -> UIViewController {
    completion(.failure(VKCaptchaResultError.unknown))
    return UIViewController()
  }

  public func openCaptcha(
    presenter: any VKCaptchaPresenter,
    completion: @escaping (Result<String, any Error>) -> Void
  ) {
    completion(.failure(VKCaptchaResultError.unknown))
  }

  public func passChallenge(
    presenter: any VKCaptchaPresenter,
    completion: @escaping (Result<String, any Error>) -> Void
  ) {
    completion(.failure(VKCaptchaResultError.unknown))
  }

  public func passChallenge(
    completion: @escaping (Result<String, any Error>) -> Void
  ) -> UIViewController {
    completion(.failure(VKCaptchaResultError.unknown))
    return UIViewController()
  }

  public func closeCaptcha(animated: Bool = true, completion: (() -> Void)? = nil) {
    completion?()
  }
}
