#import <TargetConditionals.h>

#if TARGET_OS_IOS && !TARGET_OS_MACCATALYST

#import "AppAuthIOSCompatibility.h"
@import AppAuth;

void SocialAuthAppAuthIOSCompatibilityForceLoad(void) {}

@implementation OIDAuthorizationService (SocialAuthIOSCompatibility)

+ (id<OIDExternalUserAgentSession>)presentAuthorizationRequest:(OIDAuthorizationRequest *)request
                                    presentingViewController:(UIViewController *)presentingViewController
                                                    callback:(OIDAuthorizationCallback)callback {
  id<OIDExternalUserAgent> externalUserAgent =
      [[OIDExternalUserAgentIOS alloc] initWithPresentingViewController:presentingViewController];
  return [self presentAuthorizationRequest:request
                         externalUserAgent:externalUserAgent
                                  callback:callback];
}

+ (id<OIDExternalUserAgentSession>)presentAuthorizationRequest:(OIDAuthorizationRequest *)request
                                    presentingViewController:(UIViewController *)presentingViewController
                                     prefersEphemeralSession:(BOOL)prefersEphemeralSession
                                                    callback:(OIDAuthorizationCallback)callback {
  id<OIDExternalUserAgent> externalUserAgent =
      [[OIDExternalUserAgentIOS alloc] initWithPresentingViewController:presentingViewController
                                                prefersEphemeralSession:prefersEphemeralSession];
  return [self presentAuthorizationRequest:request
                         externalUserAgent:externalUserAgent
                                  callback:callback];
}

@end

#endif
