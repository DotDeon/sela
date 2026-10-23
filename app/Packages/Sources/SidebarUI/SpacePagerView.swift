import AppKit
import Browsing
import Favicons
import Sidebar
import SidebarModel

/// One page per space, side by side. A two-finger swipe moves one page and snaps.
@MainActor
final class SpacePagerView: NSScrollView {
    private(set) var pages: [SpacePageView] = []
    private(set) var currentPage = 0
    var onNewTab: (() -> Void)?

    private let model: BrowserWindowModel
    private let favicons: FaviconStore
    private let pageContainer = FlippedView()

    // The swipe in progress.
    private var swipeStartPage = 0
    private var samples: [(time: TimeInterval, offset: CGFloat)] = []
    private var isSwiping = false

    init(model: BrowserWindowModel, favicons: FaviconStore) {
        self.model = model
        self.favicons = favicons
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 600))
        drawsBackground = false
        hasHorizontalScroller = false
        hasVerticalScroller = false
        horizontalScrollElasticity = .allowed
        verticalScrollElasticity = .none
        documentView = pageContainer
        keepObserving { [weak self] in self?.update() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private var pageWidth: CGFloat { max(contentView.bounds.width, 1) }

    // MARK: Model

    private func update() {
        let spaces = model.sidebar.document.spaces
        if pages.map(\.spaceID) != spaces.map(\.id) {
            rebuildPages(for: spaces.map(\.id))
        }
        let index = spaces.firstIndex { $0.id == model.selectedSpaceID } ?? 0
        if index != currentPage, !isSwiping {
            scroll(toPage: index, animated: window != nil)
        }
    }

    private func rebuildPages(for spaceIDs: [SpaceID]) {
        let existing = Dictionary(uniqueKeysWithValues: pages.map { ($0.spaceID, $0) })
        pages.forEach { $0.removeFromSuperview() }
        pages = spaceIDs.map { id in
            let page = existing[id] ?? SpacePageView(spaceID: id, model: model, favicons: favicons)
            page.horizontalScrollTarget = self
            page.onNewTab = { [weak self] in self?.onNewTab?() }
            return page
        }
        pages.forEach(pageContainer.addSubview)
        needsLayout = true
        layoutPages()
    }

    // MARK: Layout

    override func layout() {
        super.layout()
        layoutPages()
    }

    private func layoutPages() {
        let size = contentView.bounds.size
        pageContainer.frame = NSRect(x: 0, y: 0, width: size.width * CGFloat(max(pages.count, 1)), height: size.height)
        for (index, page) in pages.enumerated() {
            page.frame = NSRect(x: CGFloat(index) * size.width, y: 0, width: size.width, height: size.height)
        }
        if !isSwiping {
            contentView.setBoundsOrigin(NSPoint(x: CGFloat(currentPage) * size.width, y: 0))
        }
    }

    func scroll(toPage index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        currentPage = index
        let origin = NSPoint(x: CGFloat(index) * pageWidth, y: 0)
        if animated, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = 0.25
                context.timingFunction = CAMediaTimingFunction(name: .easeOut)
                contentView.animator().setBoundsOrigin(origin)
            }
        } else {
            contentView.setBoundsOrigin(origin)
        }
        reflectScrolledClipView(contentView)
    }

    // MARK: Swiping

    override func scrollWheel(with event: NSEvent) {
        // Momentum after a snap would fight the animation.
        if event.momentumPhase != [] { return }

        switch event.phase {
        case .began:
            isSwiping = true
            swipeStartPage = currentPage
            samples = [(event.timestamp, contentView.bounds.origin.x)]
        case .changed:
            guard isSwiping else { return }
            // Only sideways movement; the pages scroll vertically on their own.
            var origin = contentView.bounds.origin
            origin.x -= event.scrollingDeltaX
            origin.x = min(max(origin.x, -pageWidth * 0.25), pageWidth * (CGFloat(pages.count) - 0.75))
            contentView.setBoundsOrigin(origin)
            reflectScrolledClipView(contentView)
            samples.append((event.timestamp, origin.x))
            samples = samples.filter { event.timestamp - $0.time < 0.1 }
        case .ended, .cancelled:
            guard isSwiping else { return }
            isSwiping = false
            let target = targetPage(
                startPage: swipeStartPage,
                offset: contentView.bounds.origin.x,
                pageWidth: pageWidth,
                velocity: velocity(),
                pageCount: pages.count
            )
            scroll(toPage: target, animated: true)
            if pages.indices.contains(target), pages[target].spaceID != model.selectedSpaceID {
                model.selectSpace(pages[target].spaceID)
            }
        default:
            // Mouse wheels have no phase; a vertical wheel over the pager does nothing.
            break
        }
    }

    /// Points per second over the last tenth of a second. Positive means moving towards later spaces.
    private func velocity() -> CGFloat {
        guard let first = samples.first, let last = samples.last, last.time > first.time else { return 0 }
        return (last.offset - first.offset) / CGFloat(last.time - first.time)
    }
}

/// A container whose origin is at the top left, so pages line up from the top.
final class FlippedView: NSView {
    override var isFlipped: Bool { true }
}
