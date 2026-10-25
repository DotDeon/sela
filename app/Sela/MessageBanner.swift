import AppKit
import RemoteSettings
import SidebarUI

/// A quiet notice at the bottom of the page for a message from the remote settings, with a link when the
/// message has one. It stays until closed.
@MainActor
final class MessageBanner: NSVisualEffectView {
    private let link: URL?
    private let openLink: (URL) -> Void

    /// `openLink` opens the message's link in a tab.
    static func show(_ message: RemoteMessage, in host: NSView, openLink: @escaping (URL) -> Void) {
        let banner = MessageBanner(message, openLink: openLink)
        banner.translatesAutoresizingMaskIntoConstraints = false
        host.addSubview(banner)
        NSLayoutConstraint.activate([
            banner.centerXAnchor.constraint(equalTo: host.centerXAnchor),
            banner.bottomAnchor.constraint(equalTo: host.bottomAnchor, constant: -12),
            banner.widthAnchor.constraint(lessThanOrEqualTo: host.widthAnchor, constant: -24),
        ])
        // Rises from the bottom edge, where it sits.
        banner.alphaValue = 0
        host.layoutSubtreeIfNeeded()
        OverlayTransition.appear(banner, offset: CGPoint(x: 0, y: -Motion.settleDistance))
    }

    private func dismiss() {
        OverlayTransition.disappear(self, offset: CGPoint(x: 0, y: -Motion.settleDistance))
    }

    private init(_ message: RemoteMessage, openLink: @escaping (URL) -> Void) {
        link = message.link
        self.openLink = openLink
        super.init(frame: .zero)
        material = .popover
        blendingMode = .withinWindow
        state = .active
        wantsLayer = true
        layer?.cornerRadius = 10
        layer?.cornerCurve = .continuous

        let text = NSTextField(wrappingLabelWithString: message.text)
        text.font = .systemFont(ofSize: 12)
        text.textColor = .secondaryLabelColor
        text.preferredMaxLayoutWidth = 420
        var views: [NSView] = [text]
        if link != nil {
            let more = NSButton(title: "Learn More", target: self, action: #selector(openClicked))
            more.bezelStyle = .accessoryBarAction
            more.controlSize = .small
            views.append(more)
        }
        let close = HoverButton(symbol: "xmark", label: "Close", pointSize: 11)
        close.target = self
        close.action = #selector(closeClicked)
        views.append(close)

        let stack = NSStackView(views: views)
        stack.spacing = 8
        stack.edgeInsets = NSEdgeInsets(top: 8, left: 12, bottom: 8, right: 6)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)
        NSLayoutConstraint.activate([
            stack.leadingAnchor.constraint(equalTo: leadingAnchor),
            stack.trailingAnchor.constraint(equalTo: trailingAnchor),
            stack.topAnchor.constraint(equalTo: topAnchor),
            stack.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    @objc private func openClicked() {
        if let link { openLink(link) }
        dismiss()
    }

    @objc private func closeClicked() {
        dismiss()
    }
}
