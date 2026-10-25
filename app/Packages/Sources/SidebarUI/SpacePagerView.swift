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
    /// Where the pages would be without the rubber band, so a pull past the end springs back.
    private var swipeOffset: CGFloat = 0
    private var samples: [(time: TimeInterval, offset: CGFloat)] = []
    private var isSwiping = false
    /// Settles the pages after a swipe or a click, carrying the swipe's speed into the spring.
    private var settle: SpringAnimator!

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
        settle = SpringAnimator(value: 0, host: self)
        settle.onChange = { [weak self] offset in self?.place(offset) }
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
        if !isSwiping, !settle.isAnimating {
            settle.set(CGFloat(currentPage) * size.width)
        }
    }

    private func place(_ offset: CGFloat) {
        contentView.setBoundsOrigin(NSPoint(x: offset, y: 0))
        reflectScrolledClipView(contentView)
    }

    func scroll(toPage index: Int, animated: Bool) {
        guard pages.indices.contains(index) else { return }
        currentPage = index
        let offset = CGFloat(index) * pageWidth
        if animated {
            settle.animate(to: offset)
        } else {
            settle.set(offset)
        }
    }

    // MARK: Swiping

    /// The pages follow the fingers one to one, pull less and less past the first and last page, and settle on
    /// a spring that starts at the fingers' speed. A swipe that starts while they're still settling takes over.
    override func scrollWheel(with event: NSEvent) {
        // Momentum after the fingers lift is projected into the snap instead, so it never fights the spring.
        if event.momentumPhase != [] { return }

        switch event.phase {
        case .began:
            settle.stop()
            isSwiping = true
            swipeStartPage = currentPage
            swipeOffset = contentView.bounds.origin.x
            samples = [(event.timestamp, swipeOffset)]
        case .changed:
            guard isSwiping else { return }
            // Only sideways movement; the pages scroll vertically on their own.
            swipeOffset -= event.scrollingDeltaX
            let last = pageWidth * CGFloat(max(pages.count - 1, 0))
            let shown: CGFloat
            if swipeOffset < 0 {
                shown = Motion.rubberBand(swipeOffset, limit: pageWidth * 0.3)
            } else if swipeOffset > last {
                shown = last + Motion.rubberBand(swipeOffset - last, limit: pageWidth * 0.3)
            } else {
                shown = swipeOffset
            }
            place(shown)
            samples.append((event.timestamp, swipeOffset))
            samples = samples.filter { event.timestamp - $0.time < 0.1 }
        case .ended, .cancelled:
            guard isSwiping else { return }
            isSwiping = false
            // Fingers that rest before lifting send nothing, so the lift itself counts as standing still.
            samples.append((event.timestamp, swipeOffset))
            samples = samples.filter { event.timestamp - $0.time < 0.1 }
            let speed = velocity()
            let target = targetPage(
                startPage: swipeStartPage,
                offset: swipeOffset,
                pageWidth: pageWidth,
                velocity: speed,
                pageCount: pages.count
            )
            currentPage = target
            settle.animate(
                to: CGFloat(target) * pageWidth,
                velocity: speed,
                damping: abs(speed) >= Motion.flickVelocity ? Motion.flickDamping : Motion.damping
            )
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
