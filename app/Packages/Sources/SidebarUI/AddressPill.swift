import AppKit

/// The address at the top of the sidebar. Shows the site's host; editing shows the full address, all selected.
final class AddressPill: NSTextField {
    var onSubmit: ((String) -> Void)?
    /// When set, a click calls this instead of editing in place.
    var onClick: (() -> Void)?
    /// The full address of the selected tab.
    var address: String = "" {
        didSet { if currentEditor() == nil { showHost() } }
    }

    private var isHovered = false {
        didSet { updateBackground() }
    }

    init() {
        super.init(frame: .zero)
        let paddedCell = PaddedTextFieldCell(textCell: "")
        paddedCell.isEditable = true
        paddedCell.isSelectable = true
        paddedCell.isScrollable = true
        cell = paddedCell
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 13, weight: .medium)
        textColor = .labelColor
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
        placeholderString = "Search or enter address"
        cell?.sendsActionOnEndEditing = false
        target = self
        action = #selector(submitted)
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous
        updateBackground()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 34)
    }

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: .zero, options: [.mouseEnteredAndExited, .activeInActiveApp, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) { isHovered = true }

    override func mouseExited(with event: NSEvent) { isHovered = false }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateBackground()
    }

    private func updateBackground() {
        let dark = effectiveAppearance.isDark
        let alpha: CGFloat = isHovered ? (dark ? 0.12 : 0.55) : (dark ? 0.08 : 0.38)
        layer?.backgroundColor = NSColor.white.withAlphaComponent(alpha).cgColor
    }

    /// With `onClick` set, editing happens in the command bar, so the pill never takes keyboard focus,
    /// even as the first thing in the window when it opens.
    override var acceptsFirstResponder: Bool {
        onClick == nil && super.acceptsFirstResponder
    }

    override func becomeFirstResponder() -> Bool {
        let became = super.becomeFirstResponder()
        if became {
            stringValue = address
            currentEditor()?.selectAll(nil)
        }
        return became
    }

    override func mouseDown(with event: NSEvent) {
        if let onClick {
            onClick()
            return
        }
        // The first click selects the whole address instead of placing the caret.
        if currentEditor() == nil {
            window?.makeFirstResponder(self)
            return
        }
        super.mouseDown(with: event)
    }

    override func textDidEndEditing(_ notification: Notification) {
        super.textDidEndEditing(notification)
        showHost()
    }

    override func cancelOperation(_ sender: Any?) {
        stringValue = address
        window?.makeFirstResponder(nil)
    }

    @objc private func submitted() {
        let text = stringValue
        window?.makeFirstResponder(nil)
        onSubmit?(text)
    }

    private func showHost() {
        let url = URL(string: address)
        stringValue = url?.host().map { $0.hasPrefix("www.") ? String($0.dropFirst(4)) : $0 } ?? address
    }
}

/// A text field cell that centres its single line vertically and keeps the text off the rounded edges.
final class PaddedTextFieldCell: NSTextFieldCell {
    var horizontalPadding: CGFloat = 11

    private func textRect(_ rect: NSRect) -> NSRect {
        let font = font ?? .systemFont(ofSize: NSFont.systemFontSize)
        let lineHeight = ceil(font.ascender - font.descender + font.leading)
        var result = rect.insetBy(dx: horizontalPadding, dy: 0)
        result.origin.y += floor((rect.height - lineHeight) / 2)
        result.size.height = lineHeight
        return result
    }

    override func titleRect(forBounds rect: NSRect) -> NSRect {
        textRect(rect)
    }

    override func drawInterior(withFrame cellFrame: NSRect, in controlView: NSView) {
        super.drawInterior(withFrame: textRect(cellFrame), in: controlView)
    }

    override func edit(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, event: NSEvent?) {
        super.edit(withFrame: textRect(rect), in: controlView, editor: textObj, delegate: delegate, event: event)
    }

    override func select(withFrame rect: NSRect, in controlView: NSView, editor textObj: NSText, delegate: Any?, start selStart: Int, length selLength: Int) {
        super.select(withFrame: textRect(rect), in: controlView, editor: textObj, delegate: delegate, start: selStart, length: selLength)
    }
}
