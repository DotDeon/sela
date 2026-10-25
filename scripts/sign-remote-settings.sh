#!/bin/sh
# Signs website/public/remote-settings.json and writes the signature beside it as
# remote-settings.json.sig. Sela ignores the file unless the signature matches the public key built
# into it. Run this after every change to the file, and commit both files together.
#
# The private key comes from the file named in REMOTE_SETTINGS_KEY_FILE when that's set, or else
# from your login keychain, where scripts/make-remote-settings-key.sh put it.
# Usage: scripts/sign-remote-settings.sh
set -eu
cd "$(dirname "$0")/.."
file=website/public/remote-settings.json
work=$(mktemp -d -t sela-sign)
script="$work/sign.swift"
trap 'rm -rf "$work"' EXIT

cat > "$script" <<'SWIFT'
import CryptoKit
import Foundation

func fail(_ text: String) -> Never {
    FileHandle.standardError.write(Data((text + "\n").utf8))
    exit(1)
}

let file = CommandLine.arguments[1]
let keyText = String(decoding: FileHandle.standardInput.readDataToEndOfFile(), as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
guard let raw = Data(base64Encoded: keyText), let key = try? Curve25519.Signing.PrivateKey(rawRepresentation: raw) else {
    fail("The key isn't a base64 Ed25519 private key.")
}
guard let data = FileManager.default.contents(atPath: file) else { fail("Couldn't read \(file).") }
guard data.count <= 64 * 1024 else { fail("\(file) is over 64 KB, so Sela would refuse it.") }
guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any], object["version"] as? Int == 1 else {
    fail("\(file) isn't a JSON object with \"version\": 1.")
}
let signature = try key.signature(for: data)
guard key.publicKey.isValidSignature(signature, for: data) else { fail("The signature didn't check out.") }
try Data((signature.base64EncodedString() + "\n").utf8).write(to: URL(fileURLWithPath: file + ".sig"), options: .atomic)
print("Signed \(file) with the key whose public half is \(key.publicKey.rawRepresentation.base64EncodedString())")
SWIFT

if [ -n "${REMOTE_SETTINGS_KEY_FILE:-}" ]; then
    xcrun swift "$script" "$file" < "$REMOTE_SETTINGS_KEY_FILE"
else
    security find-generic-password -s "Sela remote settings key" -w | xcrun swift "$script" "$file"
fi
