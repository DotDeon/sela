import AppKit
import BrowserEngine
import Browsing
import SidebarUI

/// Shows the window's Peek page in a floating card over the dimmed page area, with buttons to open it
/// in a split, open it as a tab, or close it. Escape or a click outside the card closes it.
@MainActor
final class PeekPresenter {
    static let horizontalInset: CGFloat = 48
    static let verticalInset: CGFloat = 32
    static let settleDistance: CGFloat = 8

    private let model: BrowserWindowModel
    private weak var host: NSView?
    private var overlay: NSView?
    private var splitButton: HoverButton?
    private var shownTabID: TabID?
    private var keyMonitor: Any?

    init(model: BrowserWindowModel, host: NSView) {
        self.model = model
        self.host = host
        keepObserving { [weak self] in self?.update() }
    }

    private func update() {
        let tab = model.peekTab
        splitButton?.isHidden = !model.canSplitPeek
        guard tab?.id != shownTabID else { return }
        hide()
        if let tab { show(tab) }
    }

    // MARK: Showing

    private func show(_ tab: any BrowserTab) {
        guard let host else { return }
        shownTabID = tab.id

        let overlay = NSView()
        overlay.translatesAutoresizingMaskIntoConstraints = false
        let backdrop = PeekBackdrop()
        backdrop.onClick = { [weak self] in self?.model.closePeek() }
        backdrop.wantsLayer = true
        backdrop.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.25).cgColor
        let shadow = PanelShadowView()
        shadow.cornerRadius = PageCardView.cornerRadius
        let card = PageCardView(frame: .zero)
        card.show(tab.contentView)
        let buttons = buttonPill()

        host.addSubview(overlay)
        for view in [backdrop, shadow, card, buttons] {
            view.translatesAutoresizingMaskIntoConstraints = false
            overlay.addSubview(view)
        }
        let settle = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion ? 0 : Self.settleDistance
        let top = card.topAnchor.constraint(equalTo: overlay.topAnchor, constant: Self.verticalInset - settle)
        let bottom = card.bottomAnchor.constraint(equalTo: overlay.bottomAnchor, constant: -Self.verticalInset - settle)
        NSLayoutConstraint.activate([
            overlay.leadingAnchor.constraint(equalTo: host.leadingAnchor),
            overlay.trailingAnchor.constraint(equalTo: host.trailingAnchor),
            overlay.topAnchor.constraint(equalTo: host.topAnchor),
            overlay.bottomAnchor.constraint(equalTo: host.bottomAnchor),
            backdrop.leadingAnchor.constraint(equalTo: overlay.leadingAnchor),
            backdrop.trailingAnchor.constraint(equalTo: overlay.trailingAnchor),
            backdrop.topAnchor.constraint(equalTo: overlay.topAnchor),
            backdrop.bottomAnchor.constraint(equalTo: overlay.bottomAnchor),
            card.leadingAnchor.constraint(equalTo: overlay.leadingAnchor, constant: Self.horizontalInset),
            card.trailingAnchor.constraint(equalTo: overlay.trailingAnchor, constant: -Self.horizontalInset),
            top,
            bottom,
            shadow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            shadow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            shadow.topAnchor.constraint(equalTo: card.topAnchor),
            shadow.bottomAnchor.constraint(equalTo: card.bottomAnchor),
            buttons.leadingAnchor.constraint(equalTo: card.trailingAnchor, constant: 8),
            buttons.topAnchor.constraint(equalTo: card.topAnchor),
        ])
        self.overlay = overlay
        host.window?.makeFirstResponder(tab.contentView)
        watchForEscape()

        overlay.alphaValue = 0
        overlay.layoutSubtreeIfNeeded()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.3, 1)
            context.allowsImplicitAnimation = true
            overlay.animator().alphaValue = 1
            top.animator().constant = Self.verticalInset
            bottom.animator().constant = -Self.verticalInset
        }
    }

    /// Fades the overlay out. When the page became a tab, it has already moved to the main page area.
    private func hide() {
        shownTabID = nil
        splitButton = nil
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
        guard let overlay else { return }
        self.overlay = nil
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.12
            overlay.animator().alphaValue = 0
        }, completionHandler: {
            MainActor.assumeIsolated { overlay.removeFromSuperview() }
        })
    }

    // MARK: Controls

    private func buttonPill() -> NSView {
        let pill = NSVisualEffectView()
        pill.material = .popover
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.layer?.cornerCurve = .continuous

        let split = HoverButton(symbol: "rectangle.split.2x1", label: "Open in Split View")
        split.target = self
        split.action = #selector(openInSplit)
        split.isHidden = !model.canSplitPeek
        splitButton = split
        let expand = HoverButton(symbol: "arrow.up.left.and.arrow.down.right", label: "Open as Tab")
        expand.target = self
        expand.action = #selector(openAsTab)
        let close = HoverButton(symbol: "xmark", label: "Close")
        close.target = self
        close.action = #selector(closePeek)

        let stack = NSStackView(views: [split, expand, close])
        stack.orientation = .vertical
        stack.spacing = 2
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor, constant: 4),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor, constant: -4),
            stack.topAnchor.constraint(equalTo: pill.topAnchor, constant: 4),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor, constant: -4),
        ])
        return pill
    }

    @objc private func openInSplit() { model.splitPeek() }

    @objc private func openAsTab() { model.expandPeek() }

    @objc private func closePeek() { model.closePeek() }

    /// Escape closes Peek while it shows in the key window.
    private func watchForEscape() {
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard event.keyCode == 53 else { return event }
            let window = event.window
            let handled = MainActor.assumeIsolated {
                guard let self, window === self.host?.window, self.model.peekTab != nil else { return false }
                self.model.closePeek()
                return true
            }
            return handled ? nil : event
        }
    }
}

/// The dimmed area around the Peek card. A click on it closes Peek.
private final class PeekBackdrop: NSView {
    var onClick: (() -> Void)?

    override func mouseDown(with event: NSEvent) {
        onClick?()
    }
}
