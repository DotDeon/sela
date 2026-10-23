import AppKit

/// A row with a soft rounded highlight instead of the system selection colour.
final class SidebarRowView: NSTableRowView {
    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let rect = bounds.insetBy(dx: 6, dy: 2)
        NSColor.white.withAlphaComponent(effectiveAppearance.isDark ? 0.14 : 0.62).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 8, yRadius: 8).fill()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
