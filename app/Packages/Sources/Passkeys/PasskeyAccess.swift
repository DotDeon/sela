import AuthenticationServices
import Foundation
import Observation

/// Whether the user lets Sela see which sites they have passkeys for. macOS asks once, and after that the
/// choice lives in System Settings > Privacy & Security > Passkeys Access for Web Browsers.
public enum PasskeyAccess: Sendable, Equatable {
    case notDetermined
    case allowed
    case denied
}

/// Where the passkey access choice comes from. The system one asks macOS, and tests use their own.
@MainActor
public protocol PasskeyAccessSource: AnyObject {
    var access: PasskeyAccess { get }
    /// Shows macOS's prompt when the user hasn't chosen yet, and returns the choice.
    func requestAccess() async -> PasskeyAccess
    /// Whether this Mac has somewhere to keep passkeys, like iCloud Keychain or a password manager. Nil when macOS can't say.
    var isDeviceConfigured: Bool? { get }
}

/// The access macOS gives a browser through `ASAuthorizationWebBrowserPublicKeyCredentialManager`.
/// Only use it when `PasskeyEntitlement.isPresent`, since macOS turns down a browser without the entitlement.
@MainActor
public final class SystemPasskeyAccess: PasskeyAccessSource {
    private let manager = ASAuthorizationWebBrowserPublicKeyCredentialManager()

    public init() {}

    public var access: PasskeyAccess { Self.access(from: manager.authorizationStateForPlatformCredentials) }

    public func requestAccess() async -> PasskeyAccess {
        let state = await withCheckedContinuation { continuation in
            manager.requestAuthorizationForPublicKeyCredentials { continuation.resume(returning: $0) }
        }
        return Self.access(from: state)
    }

    public var isDeviceConfigured: Bool? {
        if #available(macOS 26.2, *) { return ASAuthorizationWebBrowserPublicKeyCredentialManager.isDeviceConfiguredForPasskeys }
        return nil
    }

    /// The passkeys saved for a site, for showing them in Sela's own interface. Empty until access is allowed.
    public func passkeys(forSite relyingParty: String) async -> [ASAuthorizationWebBrowserPlatformPublicKeyCredential] {
        await manager.platformCredentials(forRelyingParty: relyingParty)
    }

    nonisolated static func access(from state: ASAuthorizationWebBrowserPublicKeyCredentialManager.AuthorizationState) -> PasskeyAccess {
        switch state {
        case .authorized: .allowed
        case .denied: .denied
        case .notDetermined: .notDetermined
        @unknown default: .notDetermined
        }
    }
}

/// The Settings > Passwords row: what the access is, and what the button next to it does.
@MainActor
@Observable
public final class PasskeyAccessModel {
    public enum Action: Equatable {
        case requestAccess
        case openPrivacySettings

        public var title: String {
            switch self {
            case .requestAccess: "Allow Access"
            case .openPrivacySettings: "Open Privacy Settings"
            }
        }
    }

    public private(set) var access: PasskeyAccess
    public private(set) var isRequesting = false
    public private(set) var isDeviceConfigured: Bool?

    @ObservationIgnored private let source: any PasskeyAccessSource

    /// The pane in System Settings where the user changes their choice.
    public static let privacySettingsURL = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_PasskeyAccess")!

    public init(source: any PasskeyAccessSource) {
        self.source = source
        access = source.access
        isDeviceConfigured = source.isDeviceConfigured
    }

    /// Reads the choice again. It can change in System Settings while Sela runs.
    public func refresh() {
        access = source.access
        isDeviceConfigured = source.isDeviceConfigured
    }

    public func requestAccess() async {
        guard !isRequesting else { return }
        isRequesting = true
        access = await source.requestAccess()
        isRequesting = false
    }

    public var status: String {
        switch access {
        case .notDetermined: "Sela hasn't asked yet"
        case .allowed: "Allowed"
        case .denied: "Not allowed"
        }
    }

    public var action: Action? {
        switch access {
        case .notDetermined: .requestAccess
        case .allowed: nil
        case .denied: .openPrivacySettings
        }
    }

    /// The line under the row, telling the user what to do next.
    public var explanation: String {
        if isDeviceConfigured == false {
            return "This Mac has nowhere to keep passkeys. Turn on iCloud Keychain, or a password manager in System Settings > General > AutoFill & Passwords."
        }
        return switch access {
        case .notDetermined: "Sites can ask you to sign in or sign up with a passkey from the Passwords app or your password manager. Allowing access also lets Sela see which sites you have passkeys for."
        case .allowed: "Sites can ask you to sign in or sign up with a passkey from the Passwords app or your password manager."
        case .denied: "Turn on Sela in System Settings > Privacy & Security > Passkeys Access for Web Browsers, then quit and reopen Sela."
        }
    }
}
