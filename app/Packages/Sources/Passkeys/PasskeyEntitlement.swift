import Foundation
import Security

/// The managed entitlement that lets a browser use passkeys on any website. Apple grants it to a team on request,
/// and it only works with a provisioning profile that carries it. Without it, macOS turns down the passkey requests
/// WebKit makes for pages, and the browser can't ask to see which sites have passkeys.
public enum PasskeyEntitlement {
    public static let name = "com.apple.developer.web-browser.public-key-credential"

    /// Whether this copy of Sela is signed with the entitlement. Read once, since a running app's signature doesn't change.
    public static let isPresent: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return isGranted(SecTaskCopyValueForEntitlement(task, name as CFString, nil))
    }()

    /// An entitlement's value counts only when it's the Boolean true, the way macOS reads it.
    public static func isGranted(_ value: CFTypeRef?) -> Bool {
        guard let value, CFGetTypeID(value) == CFBooleanGetTypeID() else { return false }
        return CFBooleanGetValue((value as! CFBoolean))
    }
}
