import BrowserEngine
import SidebarModel

extension ProfileIdentifier {
    /// The engine's name for a sidebar profile's website data.
    public init(_ id: ProfileID) {
        self = id == .default ? .default : ProfileIdentifier(rawValue: id.rawValue)
    }
}
