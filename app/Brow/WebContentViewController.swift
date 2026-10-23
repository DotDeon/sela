import AppKit
import Browsing
import SidebarUI

/// Shows the selected tab's page.
@MainActor
final class WebContentViewController: NSViewController {
    private let model: BrowserWindowModel
    private weak var shownView: NSView?

    init(model: BrowserWindowModel) {
        self.model = model
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        view = NSView(frame: NSRect(x: 0, y: 0, width: 1000, height: 800))
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        keepObserving { [weak self] in self?.update() }
    }

    private func update() {
        let next = model.selectedTab?.contentView
        guard next !== shownView else { return }

        let previous = shownView
        let pageHadFocus = previous.map(hasFocus(in:)) ?? false
        if previous?.superview === view {
            previous?.removeFromSuperview()
        }
        shownView = next
        guard let next else { return }

        next.frame = view.bounds
        next.autoresizingMask = [.width, .height]
        view.addSubview(next)
        if pageHadFocus {
            view.window?.makeFirstResponder(next)
        }
    }

    private func hasFocus(in pageView: NSView) -> Bool {
        guard let responder = view.window?.firstResponder as? NSView else { return false }
        return responder === pageView || responder.isDescendant(of: pageView)
    }
}
