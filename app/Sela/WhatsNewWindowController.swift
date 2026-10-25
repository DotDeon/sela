import AppKit
import WhatsNew

/// A small window shown once after an update, with a few notes on what changed and a Done button.
@MainActor
final class WhatsNewWindowController: NSWindowController {
    /// Reads the bundled notes and shows them when this launch is the first after an update. Records the
    /// version either way, so a first install shows nothing now and the next update does.
    static func showIfUpdated(version: String?, isFirstInstall: Bool, record: WhatsNewRecord = WhatsNewRecord()) -> WhatsNewWindowController? {
        guard let version else { return nil }
        let notes = Bundle.main.url(forResource: "WhatsNew", withExtension: "json")
            .flatMap { try? Data(contentsOf: $0) }
            .flatMap { try? WhatsNewNotes(json: $0) }
        let bullets = notes?.bullets(for: version) ?? []
        let show = WhatsNewDecision.shouldShow(current: version, lastShown: record.shownVersion, isFirstInstall: isFirstInstall, hasNotes: !bullets.isEmpty)
        record.shownVersion = version
        guard show else { return nil }
        let controller = WhatsNewWindowController(version: version, bullets: bullets)
        controller.showWindow(nil)
        controller.window?.makeKeyAndOrderFront(nil)
        return controller
    }

    init(version: String, bullets: [String]) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 200),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "What's new in Sela \(version)"
        window.isReleasedWhenClosed = false
        super.init(window: window)

        let rows = bullets.map { text in
            let bullet = NSTextField(labelWithString: "•")
            bullet.font = .systemFont(ofSize: 13)
            bullet.textColor = .secondaryLabelColor
            bullet.setContentHuggingPriority(.required, for: .horizontal)
            let label = NSTextField(wrappingLabelWithString: text)
            label.font = .systemFont(ofSize: 13)
            label.preferredMaxLayoutWidth = 370
            let row = NSStackView(views: [bullet, label])
            row.alignment = .firstBaseline
            row.spacing = 8
            return row
        }
        let list = NSStackView(views: rows)
        list.orientation = .vertical
        list.alignment = .leading
        list.spacing = 10

        let done = NSButton(title: "Done", target: self, action: #selector(doneClicked))
        done.bezelStyle = .push
        done.keyEquivalent = "\r"
        let buttons = NSStackView(views: [done])
        buttons.alignment = .trailing

        let content = NSStackView(views: [list, buttons])
        content.orientation = .vertical
        content.alignment = .trailing
        content.spacing = 18
        content.edgeInsets = NSEdgeInsets(top: 20, left: 24, bottom: 20, right: 24)
        content.translatesAutoresizingMaskIntoConstraints = false
        let container = NSView()
        container.addSubview(content)
        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            list.leadingAnchor.constraint(equalTo: content.leadingAnchor, constant: 24),
            content.widthAnchor.constraint(equalToConstant: 440),
        ])
        window.contentView = container
        window.setContentSize(container.fittingSize)
        window.center()
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func doneClicked() {
        window?.close()
    }
}
