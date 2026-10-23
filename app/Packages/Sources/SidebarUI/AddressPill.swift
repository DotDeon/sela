import AppKit

/// The address at the top of the sidebar. Shows the site's host; editing shows the full address, all selected.
final class AddressPill: NSTextField {
    var onSubmit: ((String) -> Void)?
    /// The full address of the selected tab.
    var address: String = "" {
        didSet { if currentEditor() == nil { showHost() } }
    }

    init() {
        super.init(frame: .zero)
        isBezeled = false
        drawsBackground = false
        focusRingType = .none
        font = .systemFont(ofSize: 13)
        lineBreakMode = .byTruncatingTail
        usesSingleLineMode = true
        placeholderString = "Search or enter address"
        cell?.sendsActionOnEndEditing = false
        target = self
        action = #selector(submitted)
        wantsLayer = true
        layer?.cornerRadius = 8
        layer?.backgroundColor = NSColor.white.withAlphaComponent(0.25).cgColor
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override var intrinsicContentSize: NSSize {
        NSSize(width: NSView.noIntrinsicMetric, height: 30)
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
