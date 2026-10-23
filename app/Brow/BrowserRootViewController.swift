import AppKit
import Browsing
import Favicons
import Sidebar
import SidebarUI

/// The window's layout: the sidebar on the left and the page in a rounded card.
/// With the sidebar hidden, the page fills the window and the sidebar slides out from the left edge.
@MainActor
final class BrowserRootViewController: NSViewController {
    static let widthKey = "SidebarWidth"
    static let defaultWidth: CGFloat = 260
    static let widthRange: ClosedRange<CGFloat> = 200...420

    let sidebarController: SidebarViewController
    private let content: WebContentViewController
    private let model: BrowserWindowModel
    private let tint = NSView()
    private let card = NSView()
    private let resizeHandle = ResizeHandle()
    private let edgeZone = EdgeZone()

    private var sidebarWidth: NSLayoutConstraint!
    private var sidebarLeading: NSLayoutConstraint!
    private var cardDockedConstraints: [NSLayoutConstraint] = []
    private var cardFullConstraints: [NSLayoutConstraint] = []
    private(set) var isSidebarHidden = false
    private var isRevealed = false
    private var hideTask: Task<Void, Never>?

    init(model: BrowserWindowModel, favicons: FaviconStore) {
        self.model = model
        sidebarController = SidebarViewController(model: model, favicons: favicons)
        content = WebContentViewController(model: model)
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let root = NSVisualEffectView()
        root.material = .sidebar
        root.blendingMode = .behindWindow
        root.state = .followsWindowActiveState
        view = root

        tint.wantsLayer = true
        card.wantsLayer = true
        card.layer?.cornerRadius = 10
        card.layer?.masksToBounds = true
        card.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        let cardShadow = NSView()
        cardShadow.wantsLayer = true
        cardShadow.shadow = NSShadow()
        cardShadow.layer?.shadowOpacity = 0.12
        cardShadow.layer?.shadowRadius = 6
        cardShadow.layer?.shadowOffset = NSSize(width: 0, height: -1)

        addChild(sidebarController)
        addChild(content)
        let sidebar = sidebarController.view
        sidebar.wantsLayer = true
        sidebar.shadow = NSShadow()
        sidebar.layer?.shadowOpacity = 0

        for subview in [tint, cardShadow, card, sidebar, resizeHandle, edgeZone] {
            subview.translatesAutoresizingMaskIntoConstraints = false
            root.addSubview(subview)
        }
        content.view.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(content.view)

        let saved = UserDefaults.standard.double(forKey: Self.widthKey)
        let width = saved > 0 ? min(max(saved, Self.widthRange.lowerBound), Self.widthRange.upperBound) : Self.defaultWidth
        sidebarWidth = sidebar.widthAnchor.constraint(equalToConstant: width)
        sidebarLeading = sidebar.leadingAnchor.constraint(equalTo: root.leadingAnchor)
        let inset: CGFloat = 8
        cardDockedConstraints = [
            card.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            card.topAnchor.constraint(equalTo: root.topAnchor, constant: inset),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor, constant: -inset),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor, constant: -inset),
        ]
        cardFullConstraints = [
            card.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            card.topAnchor.constraint(equalTo: root.topAnchor),
            card.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            card.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ]

        NSLayoutConstraint.activate(cardDockedConstraints + [
            tint.topAnchor.constraint(equalTo: root.topAnchor),
            tint.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            tint.trailingAnchor.constraint(equalTo: root.trailingAnchor),
            tint.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            sidebarLeading,
            sidebarWidth,
            sidebar.topAnchor.constraint(equalTo: root.topAnchor),
            sidebar.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            cardShadow.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            cardShadow.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            cardShadow.topAnchor.constraint(equalTo: card.topAnchor),
            cardShadow.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            content.view.leadingAnchor.constraint(equalTo: card.leadingAnchor),
            content.view.trailingAnchor.constraint(equalTo: card.trailingAnchor),
            content.view.topAnchor.constraint(equalTo: card.topAnchor),
            content.view.bottomAnchor.constraint(equalTo: card.bottomAnchor),

            resizeHandle.leadingAnchor.constraint(equalTo: sidebar.trailingAnchor, constant: -3),
            resizeHandle.widthAnchor.constraint(equalToConstant: 5),
            resizeHandle.topAnchor.constraint(equalTo: root.topAnchor),
            resizeHandle.bottomAnchor.constraint(equalTo: root.bottomAnchor),

            edgeZone.leadingAnchor.constraint(equalTo: root.leadingAnchor),
            edgeZone.widthAnchor.constraint(equalToConstant: 6),
            edgeZone.topAnchor.constraint(equalTo: root.topAnchor),
            edgeZone.bottomAnchor.constraint(equalTo: root.bottomAnchor),
        ])
        cardShadow.layer?.backgroundColor = NSColor.windowBackgroundColor.cgColor
        cardShadow.layer?.cornerRadius = 10

        edgeZone.isHidden = true
        edgeZone.onEnter = { [weak self] in self?.reveal() }
        resizeHandle.onDrag = { [weak self] delta in self?.resize(by: delta) }
        resizeHandle.onEnd = { [weak self] in
            guard let self else { return }
            UserDefaults.standard.set(Double(sidebarWidth.constant), forKey: Self.widthKey)
        }
        let tracking = HoverTracker()
        tracking.onExit = { [weak self] in self?.scheduleHide() }
        tracking.onEnter = { [weak self] in self?.hideTask?.cancel() }
        tracking.translatesAutoresizingMaskIntoConstraints = false
        sidebar.addSubview(tracking, positioned: .below, relativeTo: nil)
        NSLayoutConstraint.activate([
            tracking.leadingAnchor.constraint(equalTo: sidebar.leadingAnchor),
            tracking.trailingAnchor.constraint(equalTo: sidebar.trailingAnchor),
            tracking.topAnchor.constraint(equalTo: sidebar.topAnchor),
            tracking.bottomAnchor.constraint(equalTo: sidebar.bottomAnchor),
        ])
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keepObserving { [weak self] in self?.updateTint() }
    }

    private func updateTint() {
        let document = model.sidebar.document
        guard let index = document.spaces.firstIndex(where: { $0.id == model.selectedSpaceID }) else { return }
        let color = themeColor(for: document.spaces[index], at: index)
        tint.layer?.backgroundColor = NSColor(srgbRed: color.red, green: color.green, blue: color.blue, alpha: 0.18).cgColor
    }

    // MARK: Hiding

    func toggleSidebar() {
        isSidebarHidden.toggle()
        hideTask?.cancel()
        isRevealed = false
        let hidden = isSidebarHidden
        animate {
            NSLayoutConstraint.deactivate(hidden ? self.cardDockedConstraints : self.cardFullConstraints)
            NSLayoutConstraint.activate(hidden ? self.cardFullConstraints : self.cardDockedConstraints)
            self.sidebarLeading.animator().constant = hidden ? -self.sidebarWidth.constant : 0
            self.card.animator().layer?.cornerRadius = hidden ? 0 : 10
        }
        edgeZone.isHidden = !hidden
        resizeHandle.isHidden = hidden
        sidebarController.view.layer?.shadowOpacity = 0
        setWindowButtonsHidden(hidden)
    }

    /// Shows the sidebar, sliding it out when it's hidden. Returns once it's on screen.
    func revealSidebarIfHidden() {
        if isSidebarHidden { reveal() }
    }

    private func reveal() {
        guard isSidebarHidden, !isRevealed else { return }
        isRevealed = true
        edgeZone.isHidden = true
        hideTask?.cancel()
        sidebarController.view.layer?.shadowOpacity = 0.25
        sidebarController.view.layer?.shadowRadius = 12
        setWindowButtonsHidden(false)
        animate { self.sidebarLeading.animator().constant = 0 }
        // A keyboard reveal (Cmd+L, Cmd+T) never gets a pointer exit, so start watching now.
        scheduleHide()
    }

    /// Slides the revealed sidebar back once the pointer is off it and nothing in it is being edited.
    private func scheduleHide() {
        guard isSidebarHidden, isRevealed else { return }
        hideTask?.cancel()
        hideTask = Task { @MainActor [weak self] in
            while true {
                try? await Task.sleep(for: .milliseconds(400))
                guard !Task.isCancelled, let self, self.isSidebarHidden, self.isRevealed else { return }
                if self.isEditingInSidebar || self.isPointerOverSidebar { continue }
                self.isRevealed = false
                self.edgeZone.isHidden = false
                self.setWindowButtonsHidden(true)
                self.animate { self.sidebarLeading.animator().constant = -self.sidebarWidth.constant }
                return
            }
        }
    }

    private var isEditingInSidebar: Bool {
        guard let responder = view.window?.firstResponder as? NSView else { return false }
        return responder.isDescendant(of: sidebarController.view)
    }

    private var isPointerOverSidebar: Bool {
        guard let window = view.window else { return false }
        let sidebar = sidebarController.view
        return sidebar.bounds.contains(sidebar.convert(window.mouseLocationOutsideOfEventStream, from: nil))
    }

    private func animate(_ changes: @escaping () -> Void) {
        if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            changes()
            view.layoutSubtreeIfNeeded()
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.18
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            context.allowsImplicitAnimation = true
            changes()
            view.layoutSubtreeIfNeeded()
        }
    }

    private func setWindowButtonsHidden(_ hidden: Bool) {
        for kind in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            view.window?.standardWindowButton(kind)?.isHidden = hidden
        }
    }

    private func resize(by delta: CGFloat) {
        sidebarWidth.constant = min(max(sidebarWidth.constant + delta, Self.widthRange.lowerBound), Self.widthRange.upperBound)
    }
}

/// The thin strip at the sidebar's edge that resizes it.
final class ResizeHandle: NSView {
    var onDrag: ((CGFloat) -> Void)?
    var onEnd: (() -> Void)?

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .resizeLeftRight)
    }

    override func mouseDragged(with event: NSEvent) {
        onDrag?(event.deltaX)
    }

    override func mouseUp(with event: NSEvent) {
        onEnd?()
    }
}

/// The strip at the window's left edge that slides the hidden sidebar out.
final class EdgeZone: NSView {
    var onEnter: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func mouseEntered(with event: NSEvent) {
        onEnter?()
    }
}

/// Reports the pointer entering and leaving the view it fills, without taking clicks.
final class HoverTracker: NSView {
    var onEnter: (() -> Void)?
    var onExit: (() -> Void)?

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        trackingAreas.forEach(removeTrackingArea)
        addTrackingArea(NSTrackingArea(rect: bounds, options: [.mouseEnteredAndExited, .activeInKeyWindow, .inVisibleRect], owner: self))
    }

    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    override func mouseEntered(with event: NSEvent) { onEnter?() }

    override func mouseExited(with event: NSEvent) { onExit?() }
}
