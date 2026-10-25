import AppKit
import PageTranslation

/// The offer to translate a page, from the Translate button, and the short notes translation leaves behind: the
/// pair isn't supported here, its download was turned down, or Sela won't offer a language again.
@MainActor
final class TranslationPopover: NSViewController {
    private let popover = NSPopover()
    private let heading = NSTextField(wrappingLabelWithString: "")
    private let detail = NSTextField(wrappingLabelWithString: "")
    private let buttons = NSStackView()
    private var onTranslate: (() -> Void)?
    private var onDismiss: (() -> Void)?

    override init(nibName: NSNib.Name?, bundle: Bundle?) {
        super.init(nibName: nil, bundle: nil)
        popover.contentViewController = self
        popover.behavior = .transient
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        heading.font = .systemFont(ofSize: 13, weight: .semibold)
        detail.font = .systemFont(ofSize: 12)
        detail.textColor = .secondaryLabelColor
        buttons.orientation = .horizontal
        buttons.spacing = 8
        let stack = NSStackView(views: [heading, detail, buttons])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 6
        stack.setCustomSpacing(12, after: detail)
        stack.edgeInsets = NSEdgeInsets(top: 14, left: 14, bottom: 14, right: 14)
        for label in [heading, detail] {
            label.preferredMaxLayoutWidth = 252
        }
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 280),
            buttons.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
        ])
        view = stack
    }

    /// Asks whether to translate the page. `onTranslate` and `onDismiss` answer; closing the popover any other
    /// way answers nothing.
    func showOffer(from source: Locale.Language, to target: Locale.Language, relativeTo anchor: NSView,
                   onTranslate: @escaping () -> Void, onDismiss: @escaping () -> Void) {
        self.onTranslate = onTranslate
        self.onDismiss = onDismiss
        _ = view
        heading.stringValue = "This page is in \(source.displayName)"
        detail.stringValue = "Sela can translate it to \(target.displayName) on this Mac. The page's text stays on your computer."
        let notNow = NSButton(title: "Not Now", target: self, action: #selector(dismissOffer))
        let translate = NSButton(title: "Translate", target: self, action: #selector(translate))
        translate.keyEquivalent = "\r"
        // The spacer pushes the buttons to the trailing edge, as in a sheet.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        setButtons([spacer, notNow, translate])
        show(relativeTo: anchor)
    }

    /// A one-line note with nothing to answer.
    func showNote(_ title: String, _ text: String, relativeTo anchor: NSView) {
        onTranslate = nil
        onDismiss = nil
        _ = view
        heading.stringValue = title
        detail.stringValue = text
        setButtons([])
        show(relativeTo: anchor)
    }

    func close() {
        popover.performClose(nil)
    }

    private func show(relativeTo anchor: NSView) {
        if popover.isShown {
            popover.performClose(nil)
        }
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    private func setButtons(_ views: [NSView]) {
        buttons.arrangedSubviews.forEach { $0.removeFromSuperview() }
        views.forEach(buttons.addArrangedSubview)
        buttons.isHidden = views.isEmpty
    }

    @objc private func translate() {
        let action = onTranslate
        onTranslate = nil
        onDismiss = nil
        popover.performClose(nil)
        action?()
    }

    @objc private func dismissOffer() {
        let action = onDismiss
        onTranslate = nil
        onDismiss = nil
        popover.performClose(nil)
        action?()
    }
}
