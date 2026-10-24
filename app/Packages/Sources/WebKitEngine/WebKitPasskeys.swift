import Passkeys

extension WebKitEngine {
    /// Whether pages can sign in and sign up with passkeys. WebKit handles `navigator.credentials` itself and hands
    /// passkey requests to macOS, which shows its own sheet over the tab's window. macOS only serves a browser signed
    /// with `PasskeyEntitlement`, so in a copy without it pages get the same refusals they get today.
    public var servesPasskeys: Bool { PasskeyEntitlement.isPresent }
}
