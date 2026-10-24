import Foundation

/// Where links from other apps open.
public enum ExternalLinkDestination: String, CaseIterable, Sendable {
    /// A small Little Sela window of its own.
    case littleWindow
    /// A new tab in the frontmost window, as before Little Sela.
    case newTab
}

/// Where links from other apps open, stored in `UserDefaults`. Little Sela unless you choose otherwise.
public struct ExternalLinkSettings {
    public static let key = "OpenLinksFromOtherAppsIn"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    public var destination: ExternalLinkDestination {
        get { defaults.string(forKey: Self.key).flatMap(ExternalLinkDestination.init(rawValue:)) ?? .littleWindow }
        nonmutating set { defaults.set(newValue.rawValue, forKey: Self.key) }
    }
}

/// The addresses another app asked Sela to open that Sela can show: web pages and files. Others, such as `mailto`, are dropped.
public func pagesToOpen(_ urls: [URL]) -> [URL] {
    urls.filter { ["http", "https", "file"].contains($0.scheme?.lowercased() ?? "") }
}

/// Whether launch should open a main window. Not when Sela was opened only to show links in Little Sela windows.
public func opensMainWindowAtLaunch(linksWaiting: [URL], destination: ExternalLinkDestination) -> Bool {
    pagesToOpen(linksWaiting).isEmpty || destination == .newTab
}
