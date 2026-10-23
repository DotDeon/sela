import AppKit

/// A web page in a rounded card with a soft shadow. In a split, the focused pane's card gets an accent outline.
@MainActor
final class PageCardView: NSView {
    static let cornerRadius: CGFloat = 10

    private let clip = NSView()
    private let outline = ClickThroughView()
    private(set) weak var pageView: NSView?

    var cornerRadius: CGFloat = PageCardView.cornerRadius {
        didSet { updateCorners() }
    }

    var isFocusedPane = false {
        didSet { outline.isHidden = !isFocusedPane }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        wantsLayer = true
        layer?.shadowColor = NSColor.black.cgColor
        layer?.shadowOpacity = 0.12
        layer?.shadowRadius = 6
        layer?.shadowOffset = CGSize(width: 0, height: -1)

        clip.wantsLayer = true
        clip.layer?.masksToBounds = true
        clip.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        clip.autoresizingMask = [.width, .height]
        clip.frame = bounds
        addSubview(clip)

        // Above the page, and it never takes clicks.
        outline.wantsLayer = true
        outline.layer?.borderWidth = 2
        outline.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
        outline.autoresizingMask = [.width, .height]
        outline.frame = bounds
        outline.isHidden = true
        addSubview(outline)
        updateCorners()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    /// Puts `page` in the card, replacing whatever was there.
    func show(_ page: NSView?) {
        guard page !== pageView else { return }
        if pageView?.superview === clip { pageView?.removeFromSuperview() }
        pageView = page
        guard let page else { return }
        page.frame = clip.bounds
        page.autoresizingMask = [.width, .height]
        clip.addSubview(page)
    }

    override func layout() {
        super.layout()
        layer?.shadowPath = CGPath(roundedRect: bounds, cornerWidth: cornerRadius, cornerHeight: cornerRadius, transform: nil)
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        clip.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        outline.layer?.borderColor = NSColor.controlAccentColor.withAlphaComponent(0.6).cgColor
    }

    private func updateCorners() {
        for view in [clip, outline] {
            view.layer?.cornerRadius = cornerRadius
            view.layer?.cornerCurve = .continuous
        }
        needsLayout = true
    }
}

/// A view drawn on top that lets every click through to what's below.
private final class ClickThroughView: NSView {
    override func hitTest(_ point: NSPoint) -> NSView? { nil }
}
