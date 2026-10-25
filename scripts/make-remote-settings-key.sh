#!/bin/sh
# Makes the Ed25519 key pair that signs website/public/remote-settings.json. The private key goes in
# your login keychain as a generic password named "Sela remote settings key", and the public key is
# printed for RemoteSettingsSignature.publicKey in
# app/Packages/Sources/RemoteSettings/RemoteSettingsSignature.swift.
#
# Run it once. It refuses to replace a key that's already in the keychain, because every Sela
# released with the old public key would stop accepting the file.
# Usage: scripts/make-remote-settings-key.sh
set -eu
work=$(mktemp -d -t sela-make-key)
script="$work/make-key.swift"
trap 'rm -rf "$work"' EXIT

cat > "$script" <<'SWIFT'
import CryptoKit
import Foundation
import Security

let name = "Sela remote settings key"
let key = Curve25519.Signing.PrivateKey()
let query: [String: Any] = [
    kSecClass as String: kSecClassGenericPassword,
    kSecAttrService as String: name,
    kSecAttrLabel as String: name,
    kSecAttrAccount as String: "Sela",
    kSecValueData as String: Data(key.rawRepresentation.base64EncodedString().utf8),
]
switch SecItemAdd(query as CFDictionary, nil) {
case errSecSuccess:
    print(key.publicKey.rawRepresentation.base64EncodedString())
case errSecDuplicateItem:
    FileHandle.standardError.write(Data("The keychain already has a \"\(name)\". Delete it in Keychain Access first if you really want a new one.\n".utf8))
    exit(1)
case let status:
    FileHandle.standardError.write(Data("Couldn't add the key to the keychain (\(status)).\n".utf8))
    exit(1)
}
SWIFT

public=$(xcrun swift "$script")
echo "Saved the private key in your login keychain as \"Sela remote settings key\"."
echo "Put this public key in RemoteSettingsSignature.publicKey:"
echo "$public"
