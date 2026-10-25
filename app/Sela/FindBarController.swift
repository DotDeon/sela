import AppKit
import BrowserEngine
import Browsing
import SidebarUI

/// Find in page: a small bar at the top right of the page. Return finds the next match, Shift+Return the
/// previous one, and Escape closes the bar.
@MainActor
final class FindBarController: NSObject, NSSearchFieldDelegate {
    private let model: any PageWindowModel
    private weak var host: NSView?
    private var bar: NSView?
    private let field = NSSearchField()
    private let status = NSTextField(labelWithString: "")

    init(model: any PageWindowModel, host: NSView) {
        self.model = model
        self.host = host
        super.init()
    }

    var isShowing: Bool { bar != nil }

    /// Shows the bar, or selects its text when it's already showing.
    func show() {
        if bar == nil { build() }
        host?.window?.makeFirstResponder(field)
        field.currentEditor()?.selectAll(nil)
    }

    func close() {
        if let bar { OverlayTransition.disappear(bar, offset: CGPoint(x: 0, y: Motion.settleDistance)) }
        bar = nil
        model.selectedTab?.clearFind()
        if let page = model.selectedTab?.contentView { host?.window?.makeFirstResponder(page) }
    }

    func findNext() { find(backwards: false) }

    func findPrevious() { find(backwards: true) }

    private func find(backwards: Bool) {
        if bar == nil { show() }
        let text = field.stringValue
        guard !text.isEmpty, let tab = model.selectedTab else {
            status.stringValue = ""
            return
        }
        Task {
            let found = await tab.find(text, backwards: backwards)
            status.stringValue = found ? "" : "Not found"
        }
    }

    private func build() {
        guard let host else { return }
        let pill = NSVisualEffectView()
        pill.material = .popover
        pill.blendingMode = .withinWindow
        pill.state = .active
        pill.wantsLayer = true
        pill.layer?.cornerRadius = 10
        pill.layer?.cornerCurve = .continuous

        field.placeholderString = "Find in Page"
        field.delegate = self
        field.sendsSearchStringImmediately = false
        field.target = self
        field.action = #selector(fieldSubmitted)
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 12)
        let previous = HoverButton(symbol: "chevron.up", label: "Previous Match", pointSize: 12)
        previous.target = self
        previous.action = #selector(previousClicked)
        let next = HoverButton(symbol: "chevron.down", label: "Next Match", pointSize: 12)
        next.target = self
        next.action = #selector(nextClicked)
        let done = HoverButton(symbol: "xmark", label: "Close Find", pointSize: 11)
        done.target = self
        done.action = #selector(doneClicked)

        let stack = NSStackView(views: [field, status, previous, next, done])
        stack.spacing = 4
        stack.edgeInsets = NSEdgeInsets(top: 6, left: 8, bottom: 6, right: 6)
        field.widthAnchor.constraint(equalToConstant: 200).isActive = true
        stack.translatesAutoresizingMaskIntoConstraints = false
        pill.addSubview(stack)
        pill.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(pill)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: pill.leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: pill.trailingAnchor),
            stack.topAnchor.constraint(equalTo: pill.topAnchor),
            stack.bottomAnchor.constraint(equalTo: pill.bottomAnchor),
            pill.topAnchor.constraint(equalTo: host.topAnchor, constant: 10),
            pill.trailingAnchor.constraint(equalTo: host.trailingAnchor, constant: -10),
        ])
        bar = pill
        // Drops in from the page's top edge, where it lives.
        pill.alphaValue = 0
        host.layoutSubtreeIfNeeded()
        OverlayTransition.appear(pill, offset: CGPoint(x: 0, y: Motion.settleDistance))
    }

    @objc private func fieldSubmitted() {
        let shift = NSApp.currentEvent?.modifierFlags.contains(.shift) ?? false
        find(backwards: shift)
    }

    @objc private func previousClicked() { findPrevious() }

    @objc private func nextClicked() { findNext() }

    @objc private func doneClicked() { close() }

    func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
        if selector == #selector(NSResponder.cancelOperation(_:)) {
            close()
            return true
        }
        return false
    }
}
