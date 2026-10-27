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
    private let empty = NSTextField(labelWithString: "No downloads")
    private lazy var clear = NSButton(title: "Clear", target: self, action: #selector(clearFinished))

    init(list: DownloadList) {
        self.list = list
        super.init(nibName: nil, bundle: nil)
        popover.contentViewController = self
        popover.behavior = .transient
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func loadView() {
        let title = NSTextField(labelWithString: "Downloads")
        title.font = .systemFont(ofSize: 13, weight: .semibold)
        clear.bezelStyle = .inline
        // The spacer pushes Clear to the trailing edge, across from the title.
        let spacer = NSView()
        spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)
        let header = NSStackView(views: [title, spacer, clear])
        header.orientation = .horizontal
        rows.orientation = .vertical
        rows.alignment = .leading
        rows.spacing = 8
        empty.textColor = .secondaryLabelColor
        let stack = NSStackView(views: [header, rows])
        stack.orientation = .vertical
        stack.alignment = .leading
        stack.spacing = 10
        stack.edgeInsets = NSEdgeInsets(top: 12, left: 14, bottom: 14, right: 14)
        NSLayoutConstraint.activate([
            stack.widthAnchor.constraint(equalToConstant: 300),
            header.widthAnchor.constraint(equalTo: stack.widthAnchor, constant: -28),
            rows.widthAnchor.constraint(equalTo: header.widthAnchor),
        ])
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
            rows.addArrangedSubview(empty)
        }
        rowViews.forEach { row in
            rows.addArrangedSubview(row)
            row.widthAnchor.constraint(equalTo: rows.widthAnchor).isActive = true
        }
        clear.isHidden = rowViews.isEmpty
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
        name.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        status.textColor = .secondaryLabelColor
        status.font = .systemFont(ofSize: 11)
        bar.style = .bar
        bar.controlSize = .small
        let text = NSStackView(views: [name, bar, status])
        text.orientation = .vertical
        text.alignment = .leading
        text.spacing = 2
        // The text takes the row's spare width, so the button sits at the trailing edge.
        text.setContentHuggingPriority(.defaultLow, for: .horizontal)
        bar.widthAnchor.constraint(equalTo: text.widthAnchor).isActive = true
        button.target = self
        button.action = #selector(buttonClicked)
        button.setContentHuggingPriority(.required, for: .horizontal)
        distribution = .fill
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
