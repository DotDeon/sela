import CryptoKit
import Foundation

/// Checks `remote-settings.json` against its Ed25519 signature in `remote-settings.json.sig`, so someone who
/// takes over the website can't send Sela their own search engine. The signature file holds the 64-byte
/// signature in base64. `scripts/sign-remote-settings.sh` writes it.
public struct RemoteSettingsSignature: Sendable {
    /// Marks the public key as not made yet. While it's in place Sela doesn't use remote settings at all.
    public static let placeholderKey = "PLACEHOLDER-REPLACE-WITH-THE-PUBLIC-KEY-FROM-make-remote-settings-key.sh"

    /// The public half of the "Sela remote settings key", in base64. `scripts/make-remote-settings-key.sh`
    /// prints it. Replace the placeholder with it.
    public static let publicKey = placeholderKey

    private let key: Curve25519.Signing.PublicKey

    /// Nil for the placeholder or a key that isn't 32 bytes of base64.
    public init?(publicKey: String = Self.publicKey) {
        guard publicKey != Self.placeholderKey, let data = Data(base64Encoded: publicKey),
              let key = try? Curve25519.Signing.PublicKey(rawRepresentation: data)
        else { return nil }
        self.key = key
    }

    /// `signature` is the signature file's contents.
    public func isValid(signature: Data, for data: Data) -> Bool {
        guard let text = String(data: signature, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines),
              let raw = Data(base64Encoded: text), raw.count == 64
        else { return false }
        return key.isValidSignature(raw, for: data)
    }
}
