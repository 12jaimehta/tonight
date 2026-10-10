import Foundation

/// Sign in with Apple needs a paid Apple Developer Program.
/// A Personal Team cannot use that capability, so the default build leaves it off
/// and the sign-in screen shows email OTP only.
enum SignInWithApple {
    /// Turn this on by defining `SIGN_IN_WITH_APPLE` in the target's compilation conditions.
    /// The checked-in target does not define it and does not include the capability.
    static var isEnabled: Bool {
        #if SIGN_IN_WITH_APPLE
        return true
        #else
        return false
        #endif
    }
}
