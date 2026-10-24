import AppKit
import BrowserEngine
import Downloads
import SidebarUI

/// This session's downloads in a popover: each with its progress, and Cancel or Show in Finder.
@MainActor
final class DownloadsPopover: NSViewController {
    private let list: DownloadList
    private let rows = NSStackView()
    private let popover = NSPopover()

    init(list: DownloadList) {
        self.list = list
        super.init(nibName: nil, bundle: nil)
        popover.contentViewController = self
        popover.behavior = .transient
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 6
        let clear = NSButton(title: "Clear", target: self, action: #selector(clearFinished))
        clear.bezelStyle = .inline
        let stack = NSStackView(views: [rows, clear])
        stack.orientation = .vertical
        stack.alignment = .trailing
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 12, bottom: 12, right: 12)
        stack.widthAnchor.constraint(equalToConstant: 320).isActive = true
        view = stack
        keepObserving { [weak self] in self?.update() }
    }

    func show(relativeTo anchor: NSView) {
        popover.show(relativeTo: anchor.bounds, of: anchor, preferredEdge: .maxY)
    }

    private func update() {
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        if list.downloads.isEmpty {
            rows.addArrangedSubview(NSTextField(labelWithString: "No downloads"))
        }
        for download in list.downloads {
            rows.addArrangedSubview(row(for: download))
        }
    }

    private func row(for download: any BrowserDownload) -> NSView {
        let name = NSTextField(labelWithString: download.filename.isEmpty ? "Starting…" : download.filename)
        name.lineBreakMode = .byTruncatingMiddle
        name.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        let detail: NSView
        let button: NSButton
        switch download.state {
        case .downloading:
            let bar = NSProgressIndicator()
            bar.style = .bar
            bar.isIndeterminate = download.progress < 0
            bar.doubleValue = max(download.progress, 0) * 100
            bar.widthAnchor.constraint(equalToConstant: 200).isActive = true
            if bar.isIndeterminate { bar.startAnimation(nil) }
            detail = bar
            button = actionButton("xmark.circle", "Cancel") { download.cancel() }
        case .finished(let url):
            detail = NSTextField(labelWithString: "Done")
            button = actionButton("magnifyingglass", "Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        case .failed(let reason):
            detail = NSTextField(labelWithString: "Failed: \(reason)")
            button = actionButton("xmark", "Remove") { [weak self] in self?.list.clearFinished() }
        case .cancelled:
            detail = NSTextField(labelWithString: "Cancelled")
            button = actionButton("xmark", "Remove") { [weak self] in self?.list.clearFinished() }
        }
        (detail as? NSTextField)?.textColor = .secondaryLabelColor
        let text = NSStackView(views: [name, detail])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        return NSStackView(views: [text, button])
    }

    private func actionButton(_ symbol: String, _ label: String, _ action: @escaping () -> Void) -> NSButton {
        let button = HoverButton(symbol: symbol, label: label, pointSize: 13)
        let target = ActionTarget(action)
        button.target = target
        button.action = #selector(ActionTarget.run)
        objc_setAssociatedObject(button, &ActionTarget.key, target, .OBJC_ASSOCIATION_RETAIN)
        return button
    }

    @objc private func clearFinished() { list.clearFinished() }
}

/// Runs a closure as a button's action.
private final class ActionTarget: NSObject {
    nonisolated(unsafe) static var key = 0
    private let action: () -> Void
    init(_ action: @escaping () -> Void) { self.action = action }
    @MainActor @objc func run() { action() }
}
