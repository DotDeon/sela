import BrowserEngine
import Foundation

extension ExtensionPermissions {
    /// Allows everything in `permissions` and `matchPatterns` for good, taking back any earlier refusal of them.
    public func granting(_ permissions: Set<String>, matchPatterns: Set<String>) -> ExtensionPermissions {
        var result = self
        for permission in permissions {
            result.granted[permission] = .distantFuture
            result.denied[permission] = nil
        }
        for pattern in matchPatterns {
            result.grantedMatchPatterns[pattern] = .distantFuture
            result.deniedMatchPatterns[pattern] = nil
        }
        return result
    }

    /// Drops choices that ran out before `date`, so they're asked again.
    public func removingExpired(at date: Date) -> ExtensionPermissions {
        ExtensionPermissions(
            granted: granted.filter { $0.value > date },
            denied: denied.filter { $0.value > date },
            grantedMatchPatterns: grantedMatchPatterns.filter { $0.value > date },
            deniedMatchPatterns: deniedMatchPatterns.filter { $0.value > date }
        )
    }

    /// What `details` asks for that isn't granted yet, for example after an update adds a permission.
    public func ungranted(in details: ExtensionDetails) -> (permissions: Set<String>, matchPatterns: Set<String>) {
        (details.requestedPermissions.subtracting(granted.keys), details.requestedMatchPatterns.subtracting(grantedMatchPatterns.keys))
    }
}
