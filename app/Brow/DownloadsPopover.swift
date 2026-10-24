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
    private var rowViews: [DownloadRow] = []

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

    /// Adds and removes rows as the list changes. Each row watches its own download and updates in place.
    private func update() {
        let downloads = list.downloads
        let wanted = downloads.map(\.id)
        guard wanted != rowViews.map(\.downloadID) || (wanted.isEmpty && rows.arrangedSubviews.isEmpty) else { return }
        let existing = Dictionary(uniqueKeysWithValues: rowViews.map { ($0.downloadID, $0) })
        rows.arrangedSubviews.forEach { $0.removeFromSuperview() }
        rowViews = downloads.map { existing[$0.id] ?? DownloadRow(download: $0, list: list) }
        if rowViews.isEmpty {
            rows.addArrangedSubview(NSTextField(labelWithString: "No downloads"))
        }
        rowViews.forEach(rows.addArrangedSubview)
    }

    @objc private func clearFinished() { list.clearFinished() }
}

/// One download: its name, a progress bar or status, and Cancel, Show in Finder or Remove.
@MainActor
private final class DownloadRow: NSStackView {
    let downloadID: UUID
    private let download: any BrowserDownload
    private weak var list: DownloadList?
    private let name = NSTextField(labelWithString: "")
    private let status = NSTextField(labelWithString: "")
    private let bar = NSProgressIndicator()
    private let button = HoverButton(symbol: "xmark.circle", label: "Cancel", pointSize: 13)
    private var shownState: DownloadState?

    init(download: any BrowserDownload, list: DownloadList) {
        self.download = download
        self.list = list
        downloadID = download.id
        super.init(frame: .zero)
        name.lineBreakMode = .byTruncatingMiddle
        name.widthAnchor.constraint(lessThanOrEqualToConstant: 220).isActive = true
        status.textColor = .secondaryLabelColor
        bar.style = .bar
        bar.widthAnchor.constraint(equalToConstant: 200).isActive = true
        let text = NSStackView(views: [name, bar, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        button.target = self
        button.action = #selector(buttonClicked)
        addArrangedSubview(text)
        addArrangedSubview(button)
        keepObserving { [weak self] in self?.refresh() }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    private func refresh() {
        name.stringValue = download.filename.isEmpty ? "Starting…" : download.filename
        let state = download.state
        if state == .downloading {
            bar.isIndeterminate = download.progress < 0
            bar.doubleValue = max(download.progress, 0) * 100
            if bar.isIndeterminate { bar.startAnimation(nil) } else { bar.stopAnimation(nil) }
        }
        // Everything else only changes with the state.
        guard state != shownState else { return }
        shownState = state
        bar.isHidden = state != .downloading
        status.isHidden = state == .downloading
        switch state {
        case .downloading:
            button.setSymbol("xmark.circle", label: "Cancel")
        case .finished:
            status.stringValue = "Done"
            button.setSymbol("magnifyingglass", label: "Show in Finder")
        case .failed(let reason):
            status.stringValue = "Failed: \(reason)"
            button.setSymbol("xmark", label: "Remove")
        case .cancelled:
            status.stringValue = "Cancelled"
            button.setSymbol("xmark", label: "Remove")
        }
    }

    @objc private func buttonClicked() {
        switch download.state {
        case .downloading: download.cancel()
        case .finished(let url): NSWorkspace.shared.activateFileViewerSelecting([url])
        case .failed, .cancelled: list?.remove(downloadID)
        }
    }
}
