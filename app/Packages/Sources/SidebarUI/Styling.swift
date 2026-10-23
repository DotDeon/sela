import AppKit
import Sidebar
import SidebarModel

extension NSColor {
    convenience init(_ color: RGBAColor) {
        self.init(srgbRed: color.red, green: color.green, blue: color.blue, alpha: color.alpha)
    }
}

/// A space's colour as an `NSColor`.
@MainActor
func spaceColor(_ space: Space, in document: SidebarDocument) -> NSColor {
    let index = document.spaces.firstIndex { $0.id == space.id } ?? 0
    return NSColor(themeColor(for: space, at: index))
}

/// A space's icon: the SF Symbol with that name, or nil when it's text such as an emoji.
@MainActor
func spaceSymbol(_ icon: String?) -> NSImage? {
    guard let icon, !icon.isEmpty else { return nil }
    return NSImage(systemSymbolName: icon, accessibilityDescription: nil)
}

/// Sets a button to show a space's icon: a symbol, the icon text, or a dot.
@MainActor
func configureSpaceIcon(_ button: NSButton, icon: String?, title: String?) {
    if let symbol = spaceSymbol(icon) {
        button.image = symbol
        button.title = ""
        button.imagePosition = .imageOnly
    } else if let icon, !icon.isEmpty, icon.count <= 2 {
        // Emoji and single characters. Longer text is a symbol name this Mac doesn't have, which would show as a word.
        button.image = nil
        button.title = icon
        button.imagePosition = .noImage
    } else {
        button.image = NSImage(systemSymbolName: "circle.fill", accessibilityDescription: title)?
            .withSymbolConfiguration(.init(pointSize: 7, weight: .regular))
        button.title = ""
        button.imagePosition = .imageOnly
    }
    button.toolTip = title
}

/// A first-letter tile for sites without an icon, in a colour picked from the text so each site keeps its own.
@MainActor
func letterImage(for text: String, size: CGFloat) -> NSImage {
    let name = text.hasPrefix("www.") ? String(text.dropFirst(4)) : text
    let letter = name.first.map { String($0).uppercased() } ?? "•"
    let palette: [NSColor] = [.systemBlue, .systemIndigo, .systemPurple, .systemPink, .systemRed, .systemOrange, .systemTeal, .systemGreen]
    // A stable hash, unlike `hashValue`, so a site's colour is the same on every launch.
    let hash = name.unicodeScalars.reduce(UInt32(5381)) { ($0 &<< 5) &+ $0 &+ $1.value }
    let color = palette[Int(hash % UInt32(palette.count))]
    return NSImage(size: NSSize(width: size, height: size), flipped: false) { rect in
        color.setFill()
        NSBezierPath(roundedRect: rect, xRadius: size * 0.22, yRadius: size * 0.22).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: size * 0.58, weight: .bold),
            .foregroundColor: NSColor.white,
        ]
        let string = NSAttributedString(string: letter, attributes: attributes)
        let bounds = string.size()
        string.draw(at: NSPoint(x: rect.midX - bounds.width / 2, y: rect.midY - bounds.height / 2))
        return true
    }
}

/// The title a sidebar tab shows: its custom title, its live page's title, its saved title, or its host.
@MainActor
public func sidebarTitle(for item: SidebarItem, liveState: (url: URL?, title: String)?) -> String {
    if let title = item.title, !title.isEmpty { return title }
    if let liveState { return liveState.title }
    guard case .tab(let info) = item.kind else { return item.title ?? "Folder" }
    if let saved = info.savedTitle, !saved.isEmpty { return saved }
    return info.savedURL?.host() ?? "New Tab"
}
