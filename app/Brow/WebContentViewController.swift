import AppKit
import Browsing
import SidebarModel
import SidebarUI

/// Shows the selected tab's page in a card, or every pane of the selected split side by side, each in its own card.
/// Clicking a pane focuses it, and dragging the gap between two panes resizes them.
@MainActor
final class WebContentViewController: NSViewController {
    static let gap: CGFloat = 8
    static let minimumPaneSize: CGFloat = 240

    private let model: BrowserWindowModel
    private var cards: [ItemID: PageCardView] = [:]
    private var paneIDs: [ItemID] = []
    private var focusedPage: NSView?
    private var mouseMonitor: Any?

    /// 10 with the sidebar showing, 0 when the page fills the window.
    var cornerRadius: CGFloat = PageCardView.cornerRadius {
        didSet { cards.values.forEach { $0.cornerRadius = cornerRadius } }
    }

    init(model: BrowserWindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let container = PaneContainerView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
        container.dividerFrames = { [weak self] in self?.dividerFrames() ?? [] }
        container.onDragDivider = { [weak self] index, position in self?.dragDivider(index, to: position) }
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keepObserving { [weak self] in self?.update() }
    }

    override func viewDidAppear() {
        super.viewDidAppear()
        guard mouseMonitor == nil else { return }
        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            MainActor.assumeIsolated { self?.focusPane(at: event) }
            return event
        }
    }

    override func viewWillDisappear() {
        super.viewWillDisappear()
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        mouseMonitor = nil
    }

    // MARK: Model

    private func update() {
        let split = model.selectedSplit
        let wanted = split?.paneIDs ?? model.selectedItemID.map { [$0] } ?? []
        let pageHadFocus = focusedPage.map(hasFocus(in:)) ?? false

        for (id, card) in cards where !wanted.contains(id) {
            card.show(nil)
            card.removeFromSuperview()
            cards[id] = nil
        }
        for id in wanted {
            let card = cards[id] ?? {
                let card = PageCardView(frame: .zero)
                card.cornerRadius = cornerRadius
                view.addSubview(card)
                cards[id] = card
                return card
            }()
            card.show(model.liveTab(for: id)?.contentView)
            card.isFocusedPane = wanted.count > 1 && id == model.selectedItemID
        }
        paneIDs = wanted
        view.needsLayout = true
        view.window?.invalidateCursorRects(for: view)

        let selectedPage = model.selectedTab?.contentView
        if selectedPage !== focusedPage {
            focusedPage = selectedPage
            if pageHadFocus, let selectedPage {
                view.window?.makeFirstResponder(selectedPage)
            }
        }
    }

    override func viewDidLayout() {
        super.viewDidLayout()
        for (id, frame) in zip(paneIDs, currentFrames()) {
            cards[id]?.frame = frame
        }
    }

    // MARK: Panes

    private func currentFrames() -> [CGRect] {
        guard let split = model.selectedSplit else { return paneIDs.isEmpty ? [] : [view.bounds] }
        return paneFrames(in: view.bounds, orientation: split.orientation, fractions: split.fractions, gap: Self.gap)
    }

    /// The gaps between neighbouring panes.
    private func dividerFrames() -> [CGRect] {
        guard let split = model.selectedSplit else { return [] }
        let frames = currentFrames()
        return zip(frames, frames.dropFirst()).map { first, second in
            switch split.orientation {
            case .horizontal: CGRect(x: first.maxX, y: view.bounds.minY, width: second.minX - first.maxX, height: view.bounds.height)
            case .vertical: CGRect(x: view.bounds.minX, y: first.maxY, width: view.bounds.width, height: second.minY - first.maxY)
            }
        }
    }

    private func dragDivider(_ index: Int, to position: CGFloat) {
        guard let split = model.selectedSplit else { return }
        model.resizeSelectedSplit(fractions(afterDragging: index, to: position, in: view.bounds, orientation: split.orientation,
                                            fractions: split.fractions, gap: Self.gap, minimum: Self.minimumPaneSize))
    }

    private func focusPane(at event: NSEvent) {
        guard event.window === view.window, paneIDs.count > 1 else { return }
        let point = view.convert(event.locationInWindow, from: nil)
        guard let (id, _) = cards.first(where: { $0.value.frame.contains(point) }), id != model.selectedItemID else { return }
        model.select(id)
    }

    private func hasFocus(in pageView: NSView) -> Bool {
        guard let responder = view.window?.firstResponder as? NSView else { return false }
        return responder === pageView || responder.isDescendant(of: pageView)
    }
}

/// Lays panes out top-down and turns drags in the gaps between them into divider moves.
private final class PaneContainerView: NSView {
    var dividerFrames: () -> [CGRect] = { [] }
    var onDragDivider: ((Int, CGFloat) -> Void)?
    private var draggingDivider: Int?

    override var isFlipped: Bool { true }

    private func isHorizontal(_ frame: CGRect) -> Bool { frame.height >= frame.width }

    override func resetCursorRects() {
        for frame in dividerFrames() {
            addCursorRect(frame, cursor: isHorizontal(frame) ? .resizeLeftRight : .resizeUpDown)
        }
    }

    override func mouseDown(with event: NSEvent) {
        let point = convert(event.locationInWindow, from: nil)
        draggingDivider = dividerFrames().firstIndex { $0.insetBy(dx: -2, dy: -2).contains(point) }
    }

    override func mouseDragged(with event: NSEvent) {
        guard let index = draggingDivider, let frame = dividerFrames()[safe: index] else { return }
        let point = convert(event.locationInWindow, from: nil)
        onDragDivider?(index, isHorizontal(frame) ? point.x : point.y)
    }

    override func mouseUp(with event: NSEvent) {
        draggingDivider = nil
        window?.invalidateCursorRects(for: self)
    }
}

private extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
