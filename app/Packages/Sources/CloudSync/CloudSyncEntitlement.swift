import Foundation
import Security

/// The iCloud entitlements that let Sela use CloudKit. They only work in a copy signed with a provisioning
/// profile that carries them, so a build without them never opens the container and hides the Sync settings.
public enum CloudSyncEntitlement {
    public static let servicesName = "com.apple.developer.icloud-services"
    public static let containersName = "com.apple.developer.icloud-container-identifiers"
    /// The CloudKit container Sela's sidebar lives in. One per Apple ID, in its private database.
    public static let containerIdentifier = "iCloud.app.brow.Brow"

    /// Whether this copy of Sela is signed for CloudKit with Sela's container. Read once, since a running app's signature doesn't change.
    public static let isPresent: Bool = {
        guard let task = SecTaskCreateFromSelf(nil) else { return false }
        return isGranted(
            services: SecTaskCopyValueForEntitlement(task, servicesName as CFString, nil),
            containers: SecTaskCopyValueForEntitlement(task, containersName as CFString, nil)
        )
    }()

    /// Both entitlements count only as arrays of strings naming CloudKit and Sela's container, the way macOS reads them.
    public static func isGranted(services: CFTypeRef?, containers: CFTypeRef?) -> Bool {
        strings(services).contains("CloudKit") && strings(containers).contains(containerIdentifier)
    }

    private static func strings(_ value: CFTypeRef?) -> [String] {
        guard let value, CFGetTypeID(value) == CFArrayGetTypeID() else { return [] }
        return (value as! [Any]).compactMap { $0 as? String }
    }
}
