import AppKit

/// A borderless symbol button that lights up a rounded square under the pointer and darkens it while pressed,
/// like the toolbar buttons in Safari and Arc.
public final class HoverButton: NSButton {
    public static let size: CGFloat = 26

    private var isHovered = false {
        didSet { updateBackground() }
    }

    public init(symbol: String, label: String, pointSize: CGFloat = 13, weight: NSFont.Weight = .medium, size: CGFloat = HoverButton.size) {
        super.init(frame: NSRect(x: 0, y: 0, width: size, height: size))
        bezelStyle = .inline
        isBordered = false
        imagePosition = .imageOnly
        setSymbol(symbol, label: label, pointSize: pointSize, weight: weight)
        toolTip = label
        contentTintColor = .secondaryLabelColor
        wantsLayer = true
        layer?.cornerRadius = 6
        translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            widthAnchor.constraint(equalToConstant: size),
            heightAnchor.constraint(equalToConstant: size),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    public func setSymbol(_ symbol: String, label: String, pointSize: CGFloat = 13, weight: NSFont.Weight = .medium) {
        image = NSImage(systemSymbolName: symbol, accessibilityDescription: label)?
            .withSymbolConfiguration(.init(pointSize: pointSize, weight: weight))
        setAccessibilityLabel(label)
    }

    public override var isEnabled: Bool {
        didSet { alphaValue = isEnabled ? 1 : 0.35 }
    }

    public override var isHighlighted: Bool {
        didSet { updateBackground() }
    }

    public override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    public override func mouseEntered(with event: NSEvent) { isHovered = true }

    public override func mouseExited(with event: NSEvent) { isHovered = false }

    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        isHovered = false
    }

    private func updateBackground() {
        let alpha: CGFloat = !isEnabled ? 0 : isHighlighted ? 0.16 : isHovered ? 0.08 : 0
        layer?.backgroundColor = NSColor.labelColor.withAlphaComponent(alpha).cgColor
    }
}
