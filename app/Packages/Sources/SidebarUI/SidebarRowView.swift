import AppKit

/// A row with a soft rounded highlight instead of the system selection colour, and a fainter one under the pointer.
/// The outline view sets `isHovered`, because rows don't hear that the pointer left when the list scrolls under it.
final class SidebarRowView: NSTableRowView {
    /// Off for the divider row, which isn't something to click.
    var showsHover = true

    var isHovered = false {
        didSet {
            guard isHovered != oldValue else { return }
            needsDisplay = true
            for case let cell as ItemCellView in subviews { cell.isHovered = isHovered }
        }
    }

    private var highlightRect: NSRect { bounds.insetBy(dx: 6, dy: 1) }

    override func drawBackground(in dirtyRect: NSRect) {
        guard isHovered, showsHover, !isSelected else { return }
        NSColor.white.withAlphaComponent(effectiveAppearance.isDark ? 0.06 : 0.3).setFill()
        NSBezierPath(roundedRect: highlightRect, xRadius: 8, yRadius: 8).fill()
    }

    override func drawSelection(in dirtyRect: NSRect) {
        guard selectionHighlightStyle != .none else { return }
        let dark = effectiveAppearance.isDark
        NSGraphicsContext.saveGraphicsState()
        let shadow = NSShadow()
        shadow.shadowColor = NSColor.black.withAlphaComponent(dark ? 0.3 : 0.08)
        shadow.shadowOffset = NSSize(width: 0, height: -1)
        shadow.shadowBlurRadius = 2
        shadow.set()
        NSColor.white.withAlphaComponent(dark ? 0.15 : 0.82).setFill()
        NSBezierPath(roundedRect: highlightRect, xRadius: 8, yRadius: 8).fill()
        NSGraphicsContext.restoreGraphicsState()
    }

    override var interiorBackgroundStyle: NSView.BackgroundStyle { .normal }
}

extension NSAppearance {
    var isDark: Bool {
        bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }
}
